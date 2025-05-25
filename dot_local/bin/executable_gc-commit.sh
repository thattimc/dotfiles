#!/bin/zsh

#==HELP==
# gc-commit.sh - Generate conventional commit messages using Claude AI
# Usage:
#   gc-commit.sh [options]
#
# Options:
#   -h                Show this help message and exit
#   Set CLAUDE_MODEL to override the Claude model (default: claude-3-haiku-20240307).
#   Set GC_COMMIT_DEBUG=true to save debug files in /tmp.
#   Set MAX_TOKENS to override the max_tokens sent to Claude (default: 100).
#
# Requirements:
#   - zsh (this script requires zsh for vared)
#   - jq (install with: brew install jq)
#   - ANTHROPIC_API_KEY environment variable set
#
# Exit Codes:
#   0   Success
#   1   General error (e.g., not in git repo, no staged files, jq missing, user abort)
#   2   API error (e.g., empty response, invalid JSON, Claude error)
#   3   Git commit error
#==ENDHELP==

# === Strict Shell Options (optional, comment out if undesired) ===
set -euo pipefail

# === Constants ===
MAX_STAGED=20      # Max number of staged files to show in prompt
MAX_SUMMARY=40     # Max number of summary lines to show in prompt
MAX_DIFF=500       # Max number of diff lines to show in prompt

# === Functions ===

# Extract the commit message from the Claude API response
extract_commit_message() {
  echo "$1" | jq -r '.content[0].text // (.content | if type=="array" then .[0].text else . end)'
}

# Print the locations of debug files
print_debug_locations() {
  echo "Debug: Request body saved to $REQUEST_FILE"
  echo "Debug: API response saved to $RESPONSE_FILE"
}

# === Option Parsing (getopts for extensibility) ===
while getopts "h" opt; do
  case $opt in
    h)
      sed -n '/#==HELP==/,/#==ENDHELP==/p' "$0" | sed 's/^# *//;1d;$d'
      exit 0
      ;;
    *)
      echo "Unknown option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# === Main Script ===

# --- Environment Checks ---
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "Error: Not in a git repository"
  exit 1
fi

if [ -z "$(git diff --cached --name-only)" ]; then
  echo "Error: No files staged for commit"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo "Error: jq is required for this script. Please install jq (e.g., brew install jq)."
  exit 1
fi

# --- Configurable Options ---
DEBUG="${GC_COMMIT_DEBUG:-false}"
MODEL="${CLAUDE_MODEL:-claude-3-haiku-20240307}"
MAX_TOKENS="${MAX_TOKENS:-100}"

# --- Gather Git Data (with truncation and truncation notice) ---
ALL_STAGED_FILES=$(git diff --cached --name-only)
STAGED_FILES=$(echo "$ALL_STAGED_FILES" | head -n $MAX_STAGED)
STAGED_COUNT=$(echo "$ALL_STAGED_FILES" | wc -l | tr -d ' ')
STAGED_TRUNCATED=""
if [ "$STAGED_COUNT" -gt "$MAX_STAGED" ]; then
  STAGED_TRUNCATED="...and $((STAGED_COUNT - MAX_STAGED)) more files omitted"
fi

ALL_SUMMARY=$(git diff --cached --stat)
DIFF_SUMMARY=$(echo "$ALL_SUMMARY" | head -n $MAX_SUMMARY)
SUMMARY_COUNT=$(echo "$ALL_SUMMARY" | wc -l | tr -d ' ')
SUMMARY_TRUNCATED=""
if [ "$SUMMARY_COUNT" -gt "$MAX_SUMMARY" ]; then
  SUMMARY_TRUNCATED="...and $((SUMMARY_COUNT - MAX_SUMMARY)) more summary lines omitted"
fi

DIFF_DETAILS=$(git diff --cached)
DIFF_DETAILS_TRUNCATED=$(echo "$DIFF_DETAILS" | head -n $MAX_DIFF)

# --- Check API Key ---
if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo "Error: ANTHROPIC_API_KEY environment variable is not set"
  echo "Please set it with: export ANTHROPIC_API_KEY=your_api_key"
  exit 1
fi

echo "Analyzing changes and generating commit message..."

# --- Prepare Prompt for Claude ---
PROMPT=$(cat <<EOF
I need to create a git commit message following the Conventional Commits standard.

Here are the staged files (truncated):
$STAGED_FILES
$STAGED_TRUNCATED

Here's a summary of the changes (truncated):
$DIFF_SUMMARY
$SUMMARY_TRUNCATED

Here are the details of the changes (truncated for brevity):
$DIFF_DETAILS_TRUNCATED

Based on these changes, generate a git commit message following the Conventional Commits format: type(scope): description
where:
- type is one of: feat, fix, docs, style, refactor, test, chore, etc.
- scope is optional and indicates the section of the codebase
- description is a short explanation of the change

The message should be concise (under 70 characters if possible), written in imperative mood, and not end with a period.

Just provide the commit message text with no additional explanation or formatting.
EOF
)

# --- Prepare API Request ---
REQUEST_BODY=$(jq -n \
  --arg model "$MODEL" \
  --arg prompt "$PROMPT" \
  --argjson max_tokens "$MAX_TOKENS" \
  '{
    "model": $model,
    "max_tokens": $max_tokens,
    "messages": [
      {
        "role": "user",
        "content": $prompt
      }
    ]
  }')

# --- Temp Files ---
REQUEST_FILE=$(mktemp /tmp/claude_request.XXXXXX.json)
RESPONSE_FILE=$(mktemp /tmp/claude_response.XXXXXX.json)

if [ "$DEBUG" = true ]; then
  echo "$REQUEST_BODY" > "$REQUEST_FILE"
fi

# --- Call Claude API ---
API_RESPONSE=$(curl -s https://api.anthropic.com/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  --data-raw "$REQUEST_BODY")

if [ "$DEBUG" = true ]; then
  echo "$API_RESPONSE" > "$RESPONSE_FILE"
fi

# --- API Response Validation ---
if [ -z "$API_RESPONSE" ]; then
  echo "Error: Empty response from Claude API"
  [ "$DEBUG" != true ] && rm -f "$REQUEST_FILE" "$RESPONSE_FILE"
  exit 2
fi

if ! echo "$API_RESPONSE" | jq . >/dev/null 2>&1; then
  echo "Error: API did not return valid JSON."
  [ "$DEBUG" != true ] && rm -f "$REQUEST_FILE" "$RESPONSE_FILE"
  exit 2
fi

ERROR_MSG=$(echo "$API_RESPONSE" | jq -r '.error.message' 2>/dev/null)
if [ "$ERROR_MSG" != "null" ] && [ -n "$ERROR_MSG" ]; then
  echo "API Error: $ERROR_MSG"
  [ "$DEBUG" != true ] && rm -f "$REQUEST_FILE" "$RESPONSE_FILE"
  exit 2
fi

if [ "$DEBUG" = true ]; then
  echo "Response structure:"
  echo "$API_RESPONSE" | jq 'keys' 2>/dev/null
fi

# --- Extract Commit Message ---
COMMIT_MESSAGE=$(extract_commit_message "$API_RESPONSE")

if [ -z "$COMMIT_MESSAGE" ] || [ "$COMMIT_MESSAGE" = "null" ]; then
  echo "Error: Failed to generate commit message from Claude AI"
  if [ "$DEBUG" = true ]; then
    echo "Full API response:"
    echo "$API_RESPONSE"
  fi
  echo "Do you want to enter a commit message manually? (y/n)"
  read REPLY
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    while true; do
      echo "Enter commit message:"
      read COMMIT_MESSAGE
      if [ -z "$COMMIT_MESSAGE" ]; then
        echo "Commit message cannot be empty. Please enter a message."
      else
        break
      fi
    done
  else
    [ "$DEBUG" != true ] && rm -f "$REQUEST_FILE" "$RESPONSE_FILE"
    echo "No commit was made."
    exit 1
  fi
fi

echo "Extracted message: '$COMMIT_MESSAGE'"

# --- User Confirmation and Commit ---
echo "Generated commit message:"
echo "$COMMIT_MESSAGE"
echo ""
echo "Proceed with this commit message? (y/n/e to edit)"
read REPLY

if [[ $REPLY =~ ^[Yy]$ ]]; then
  if git commit -m "$COMMIT_MESSAGE"; then
    echo "Commit successful!"
  else
    echo "Commit failed!"
    [ "$DEBUG" != true ] && rm -f "$REQUEST_FILE" "$RESPONSE_FILE"
    exit 3
  fi
elif [[ $REPLY =~ ^[Ee]$ ]]; then
  echo "Edit commit message:"
  EDITED_MESSAGE="$COMMIT_MESSAGE"
  vared EDITED_MESSAGE
  while [ -z "$EDITED_MESSAGE" ]; do
    echo "Commit message cannot be empty. Please edit again:"
    vared EDITED_MESSAGE
  done
  if git commit -m "$EDITED_MESSAGE"; then
    echo "Commit successful!"
  else
    echo "Commit failed!"
    [ "$DEBUG" != true ] && rm -f "$REQUEST_FILE" "$RESPONSE_FILE"
    exit 3
  fi
else
  echo "Commit aborted"
  [ "$DEBUG" != true ] && rm -f "$REQUEST_FILE" "$RESPONSE_FILE"
  echo "No commit was made."
  exit 1
fi

# --- Debug Output ---
if [ "$DEBUG" = true ]; then
  print_debug_locations
fi

# --- Cleanup ---
test "$DEBUG" != true && rm -f "$REQUEST_FILE" "$RESPONSE_FILE"

exit 0

