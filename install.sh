#!/bin/bash
# :project:    Nedara Connect Installer
# :version:    0.2.0-alpha
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
    print_color "$CYAN$BOLD" "│           ${WHITE}🚀 NEDARA CONNECT v0.2.0${CYAN}              │"
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

# Function to print step
print_step() {
    print_color "$PURPLE$BOLD" "${1} ${2}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Main installation function
install_nedara_connect() {
    print_header
    print_step "$ICON_INSTALL" "Starting Nedara Connect installation..."
    print_divider

    # Check for required commands
    print_info "Checking system requirements..."

    if ! command_exists curl; then
        print_error "curl is required but not installed. Please install curl first."
        exit 1
    fi

    if ! command_exists ssh; then
        print_error "SSH client is required but not installed. Please install openssh-client."
        exit 1
    fi

    print_success "System requirements satisfied"
    echo

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
