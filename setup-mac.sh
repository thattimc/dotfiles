#!/bin/bash

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print status messages
print_status() {
    echo -e "${GREEN}==>${NC} $1"
}

# Function to handle errors
handle_error() {
    echo -e "${RED}Error: $1${NC}"
    exit 1
}

# Function to check command success
check_success() {
    if [ $? -ne 0 ]; then
        handle_error "$1"
    fi
}

# Check if Homebrew is already installed
if ! command -v brew &>/dev/null; then
    print_status "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    check_success "Failed to install Homebrew"
else
    print_status "Homebrew is already installed"
fi

# Add Homebrew to PATH
print_status "Adding Homebrew to PATH..."
eval "$(/opt/homebrew/bin/brew shellenv)"
check_success "Failed to add Homebrew to PATH"

# Install chezmoi
print_status "Installing chezmoi..."
brew install chezmoi
check_success "Failed to install chezmoi"

# Apply dotfiles
print_status "Applying dotfiles..."
chezmoi init --apply https://github.com/thattimc/dotfiles.git
check_success "Failed to apply dotfiles"

# Install apps via brew bundle
print_status "Installing apps via brew bundle..."
brew bundle
check_success "Failed to install apps via brew bundle"

# Source zprofile
print_status "Sourcing ~/.zprofile..."
source ~/.zprofile
check_success "Failed to source ~/.zprofile"

# Source zshrc
print_status "Sourcing ~/.zshrc..."
source ~/.zshrc
check_success "Failed to source ~/.zshrc"

# Check if nvm is installed
if ! command -v nvm &>/dev/null; then
    print_status "NVM not found. Please ensure NVM is installed before proceeding."
    exit 1
fi

# Install Node.js 20
print_status "Installing Node.js 20..."
nvm install 20
check_success "Failed to install Node.js 20"

# Set Node.js 20 as default
print_status "Setting Node.js 20 as default..."
nvm alias default 20
check_success "Failed to set Node.js 20 as default"

# Create symlink for Java
print_status "Creating Java symlink..."
sudo ln -sfn /opt/homebrew/opt/openjdk/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk.jdk
check_success "Failed to create Java symlink"

# Install ghtopdep using pipx
print_status "Installing ghtopdep..."
pipx install ghtopdep
check_success "Failed to install ghtopdep"

# Set rust
print_status "Setting rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
check_success "Failed to set rust"

print_status "Setup completed successfully!"
