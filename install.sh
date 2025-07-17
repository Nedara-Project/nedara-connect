#!/bin/bash
# :project:    Nedara Connect Installer
# :version:    0.3.2-alpha
# :license:    MIT
# :copyright:  (c) 2025 Nedara Project
# :author:     Andrea Ulliana
# :repository: https://github.com/Nedara-Project/nedara-connect
# :overview:   Installer for Nedara Connect SSH manager

# Configuration
INSTALL_PATH="$HOME/.local/bin"
SCRIPT_NAME="nedara-connect"
SCRIPT_FILE="$INSTALL_PATH/$SCRIPT_NAME"
# Locally this file should be exectued with chmod +x (./install.sh -> same for nedara-connect.sh)
GITHUB_URL="https://raw.githubusercontent.com/Nedara-Project/nedara-connect/main/nedara-connect.sh"

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# Unicode icons
ICON_SUCCESS="✅"
ICON_ERROR="❌"
ICON_INFO="ℹ️ "
ICON_DOWNLOAD="⬇️ "
ICON_INSTALL="🔧"
ICON_ROCKET="🚀"
ICON_FOLDER="📁"
ICON_SHELL="🐚"
ICON_LOCK="🔒"
ICON_WARNING="⚠️ "

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${RESET}"
}

# Function to print header
print_header() {
    echo
    print_color "$CYAN$BOLD" "╭─────────────────────────────────────────────────╮"
    print_color "$CYAN$BOLD" "│           ${WHITE}🚀 NEDARA CONNECT v0.3.2${CYAN}              │"
    print_color "$CYAN$BOLD" "│            ${DIM}${WHITE}SSH Connection Manager${CYAN}               │"
    print_color "$CYAN$BOLD" "╰─────────────────────────────────────────────────╯"
    echo
}

# Function to print section divider
print_divider() {
    print_color "$GRAY" "─────────────────────────────────────────────────"
}

# Function to print success message
print_success() {
    print_color "$GREEN$BOLD" "${ICON_SUCCESS} $1"
}

# Function to print error message
print_error() {
    print_color "$RED$BOLD" "${ICON_ERROR} $1"
}

# Function to print info message
print_info() {
    print_color "$BLUE" "${ICON_INFO} $1"
}

# Function to print warning message
print_warning() {
    print_color "$YELLOW$BOLD" "${ICON_WARNING} $1"
}

# Function to print step
print_step() {
    print_color "$PURPLE$BOLD" "${1} ${2}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install package
install_package() {
    local pkg=$1
    print_info "Attempting to install $pkg..."

    if command_exists apt-get; then
        sudo apt-get install -y "$pkg"
    elif command_exists yum; then
        sudo yum install -y "$pkg"
    elif command_exists brew; then
        brew install "$pkg"
    elif command_exists pacman; then
        sudo pacman -S --noconfirm "$pkg"
    else
        print_warning "Cannot install $pkg automatically - please install it manually"
        return 1
    fi
}

# Function to check and install dependencies
check_dependencies() {
    local missing=0
    local required=("curl" "ssh")
    local recommended=("gpg" "sshpass")

    print_step "$ICON_INSTALL" "Checking system requirements..."
    echo

    # Check required dependencies
    for dep in "${required[@]}"; do
        if ! command_exists "$dep"; then
            print_error "Required dependency missing: $dep"
            if ! install_package "$dep"; then
                missing=$((missing + 1))
            fi
        fi
    done

    # Check recommended dependencies
    for dep in "${recommended[@]}"; do
        if ! command_exists "$dep"; then
            print_warning "Recommended dependency missing: $dep (needed for password storage)"
            print_info "Would you like to install it now? [y/N]"
            read -r answer
            if [[ "$answer" =~ ^[Yy]$ ]]; then
                if ! install_package "$dep"; then
                    print_warning "Failed to install $dep - password storage won't be available"
                fi
            else
                print_info "Skipping $dep installation - password storage won't be available"
            fi
        fi
    done

    if [ "$missing" -gt 0 ]; then
        print_error "Cannot proceed without required dependencies"
        exit 1
    fi

    print_success "All dependencies verified"
    echo
}

# Main installation function
install_nedara_connect() {
    print_header

    # Check dependencies first
    check_dependencies

    print_step "$ICON_INSTALL" "Starting Nedara Connect installation..."
    print_divider

    # Create installation directory
    print_step "$ICON_FOLDER" "Creating installation directory..."
    mkdir -p "$INSTALL_PATH"

    if [ ! -d "$INSTALL_PATH" ]; then
        print_error "Failed to create directory: $INSTALL_PATH"
        exit 1
    fi

    print_success "Directory created: ${CYAN}$INSTALL_PATH"
    echo

    # Download the script
    print_step "$ICON_DOWNLOAD" "Downloading Nedara Connect..."
    print_info "Source: ${CYAN}$GITHUB_URL"

    if curl -s -f "$GITHUB_URL" -o "$SCRIPT_FILE"; then
        print_success "Download completed successfully"
    else
        print_error "Failed to download script from GitHub"
        print_info "Please check your internet connection and try again"
        exit 1
    fi
    echo

    # Make script executable
    print_step "$ICON_INSTALL" "Setting permissions..."
    if chmod +x "$SCRIPT_FILE"; then
        print_success "Script made executable"
    else
        print_error "Failed to set executable permissions"
        exit 1
    fi
    echo

    # Add to PATH via shell configuration
    print_step "$ICON_SHELL" "Configuring shell environment..."

    # Check if ~/.local/bin is in PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        PATH_CMD="export PATH=\"\$HOME/.local/bin:\$PATH\""

        for file in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
            if [ -f "$file" ]; then
                if ! grep -Fxq "$PATH_CMD" "$file"; then
                    echo "$PATH_CMD" >> "$file"
                    print_success "Added PATH to $(basename "$file")"
                else
                    print_info "PATH already configured in $(basename "$file")"
                fi
            fi
        done
    else
        print_info "PATH already includes ~/.local/bin"
    fi

    echo
    print_divider
    print_success "Installation completed successfully!"
    echo

    # Installation summary
    print_color "$WHITE$BOLD" "📋 INSTALLATION SUMMARY"
    print_divider
    print_info "Script installed to: ${GREEN}$SCRIPT_FILE"
    print_info "Configuration will be stored in: ${GREEN}$HOME/.ssh/connections.conf"
    print_info "Encrypted passwords will be stored in: ${GREEN}$HOME/.ssh/connections_pass.gpg"
    echo

    # Dependency status
    print_color "$WHITE$BOLD" "🔧 DEPENDENCY STATUS"
    print_divider
    if command_exists gpg; then
        print_info "GPG (password encryption): ${GREEN}Installed ${ICON_LOCK}"
    else
        print_info "GPG (password encryption): ${YELLOW}Not installed ${ICON_WARNING}"
    fi

    if command_exists sshpass; then
        print_info "sshpass (auto-login): ${GREEN}Installed ${ICON_SUCCESS}"
    else
        print_info "sshpass (auto-login): ${YELLOW}Not installed ${ICON_WARNING}"
    fi
    echo

    # Next steps
    print_color "$WHITE$BOLD" "🎯 NEXT STEPS"
    print_divider
    print_color "$YELLOW" "1. Restart your terminal or run:"
    print_color "$CYAN$BOLD" "   source ~/.bashrc  ${GRAY}# for Bash users"
    print_color "$CYAN$BOLD" "   source ~/.zshrc   ${GRAY}# for Zsh users"
    echo
    print_color "$YELLOW" "2. Start using Nedara Connect:"
    print_color "$CYAN$BOLD" "   nedara-connect help    ${GRAY}# Show help"
    print_color "$CYAN$BOLD" "   nedara-connect add     ${GRAY}# Add a connection"
    print_color "$CYAN$BOLD" "   nedara-connect list    ${GRAY}# List connections"
    echo

    print_color "$GREEN$BOLD" "${ICON_ROCKET} Ready to manage your SSH connections!"
    echo
}

# Error handling
set -e
trap 'print_error "Installation failed. Please check the error above."; exit 1' ERR

# Run installation
install_nedara_connect
