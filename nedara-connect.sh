#!/bin/bash
# :project:    Nedara Connect
# :version:    0.4.0
# :license:    MIT
# :copyright:  (c) 2025 Nedara Project
# :author:     Andrea Ulliana
# :repository: https://github.com/Nedara-Project/nedara-connect
# :overview:   Nedara-connect is a lightweight shell tool for managing and connecting to SSH hosts
# :published:  2025-04-08
# :modified:   2025-06-26

# Configuration
CONFIG_FILE="$HOME/.ssh/connections.conf"
PASS_FILE="$HOME/.ssh/connections_pass.gpg"
KEY_FILE="$HOME/.ssh/connections_key"
CONFIG_DIR="$HOME/.ssh"
GITHUB_RAW_URL="https://raw.githubusercontent.com/Nedara-Project/nedara-connect/main/nedara-connect.sh"

# Configure GPG properly
export GPG_TTY=$(tty)
gpgconf --launch gpg-agent >/dev/null 2>&1

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
ICON_CONNECT="🔗"
ICON_SERVER="🖥️ "
ICON_USER="👤"
ICON_PORT="🔌"
ICON_SUCCESS="✅"
ICON_ERROR="❌"
ICON_INFO="ℹ️ "
ICON_ARROW="➤"
ICON_BULLET="•"
ICON_PLUS="+"
ICON_TRASH="🗑️"
ICON_LOCK="🔒"

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
    print_color "$CYAN$BOLD" "│           ${WHITE}🚀 NEDARA CONNECT v0.4.0${CYAN}              │"
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

# Function to print prompt
print_prompt() {
    echo -n -e "${YELLOW}${ICON_ARROW} ${WHITE}$1${RESET}"
}

# Make sure config directory exists
mkdir -p "$CONFIG_DIR"

# Create config file if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    touch "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
fi

# Create password file if it doesn't exist
if [ ! -f "$PASS_FILE" ]; then
    touch "$PASS_FILE"
    chmod 600 "$PASS_FILE"
fi

# Returns the per-machine encryption key, generating it on first use.
# The key is stored in KEY_FILE (chmod 600) and never leaves the machine.
get_encryption_key() {
    if [ ! -f "$KEY_FILE" ]; then
        od -A n -t x1 -N 32 /dev/urandom | tr -d ' \n' > "$KEY_FILE"
        chmod 600 "$KEY_FILE"
    fi
    cat "$KEY_FILE"
}

# One-time migration: re-encrypts passwords from the legacy hardcoded passphrase
# to the new per-machine key. Runs silently and only when needed (KEY_FILE absent).
migrate_legacy_passwords() {
    [ -s "$PASS_FILE" ] && [ ! -f "$KEY_FILE" ] || return 0

    local legacy_content
    legacy_content=$(gpg --batch --yes --quiet --pinentry-mode loopback \
        --passphrase 'nedaraconnect' --decrypt "$PASS_FILE" 2>/dev/null) || return 0

    [ -n "$legacy_content" ] || return 0

    get_encryption_key > /dev/null
    echo "$legacy_content" | gpg --batch --yes --quiet --pinentry-mode loopback \
        --passphrase "$(get_encryption_key)" --symmetric --output "$PASS_FILE"
    chmod 600 "$PASS_FILE"
    print_info "Passwords migrated to new encryption key."
}

migrate_legacy_passwords

# Function to validate input
validate_input() {
    local input=$1
    local field_name=$2

    if [ -z "$input" ]; then
        print_error "The '$field_name' field cannot be empty"
        return 1
    fi

    # Check for invalid characters in connection name
    if [ "$field_name" = "connection name" ] && [[ "$input" =~ [^a-zA-Z0-9_-] ]]; then
        print_error "Connection name can only contain letters, numbers, hyphens and underscores"
        return 1
    fi

    return 0
}

# Function to check if connection exists
connection_exists() {
    local name=$1
    grep -q "^$name:" "$CONFIG_FILE" 2>/dev/null
}

# Function to decrypt passwords file
decrypt_passwords() {
    if [ -s "$PASS_FILE" ]; then
        gpg --batch --yes --quiet --pinentry-mode loopback \
            --passphrase "$(get_encryption_key)" --decrypt "$PASS_FILE" 2>/dev/null
    else
        echo ""
    fi
}

# Function to encrypt passwords file
encrypt_passwords() {
    local content=$1
    echo "$content" | gpg --batch --yes --quiet --pinentry-mode loopback \
        --passphrase "$(get_encryption_key)" --symmetric --output "$PASS_FILE"
    chmod 600 "$PASS_FILE"
}

# Function to get password for a connection
get_password() {
    local name=$1
    decrypt_passwords | grep "^$name:" | cut -d: -f2- | tr -d '\n'
}

# Function to save password for a connection
save_password() {
    local name=$1
    local password=$2
    local current_passwords
    current_passwords=$(decrypt_passwords)

    # Remove existing entry for this connection
    current_passwords=$(echo "$current_passwords" | grep -v "^$name:")

    if [ -n "$password" ]; then
        if [ -n "$current_passwords" ]; then
            current_passwords+=$'\n'"$name:$password"
        else
            current_passwords="$name:$password"
        fi
    fi

    encrypt_passwords "$current_passwords"
}

add_connection() {
    print_header
    print_color "$PURPLE$BOLD" "${ICON_PLUS} Adding new SSH connection"
    print_divider

    while true; do
        print_prompt "Connection name (e.g: staging, prod): "
        read -r name

        if validate_input "$name" "connection name"; then
            if connection_exists "$name"; then
                print_error "A connection with the name '$name' already exists"
                continue
            fi
            break
        fi
    done

    while true; do
        print_prompt "Username: "
        read -r username
        if validate_input "$username" "username"; then
            break
        fi
    done

    while true; do
        print_prompt "Hostname or IP address: "
        read -r host
        if validate_input "$host" "hostname"; then
            break
        fi
    done

    print_prompt "Port (press Enter for default 22): "
    read -r port
    port=${port:-22}

    # Validate port number
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        print_error "Invalid port. Using default port 22."
        port=22
    fi

    # Ask if user wants to save password
    print_prompt "Do you want to save a password for this connection? [y/N] "
    read -r save_pass
    if [[ "$save_pass" =~ ^[Yy]$ ]]; then
        while true; do
            print_prompt "Password (will be stored encrypted): "
            read -rs password
            echo
            if validate_input "$password" "password"; then
                save_password "$name" "$password"
                print_success "Password saved securely!"
                break
            fi
        done
    fi

    echo "$name:$username:$host:$port" >> "$CONFIG_FILE"

    echo
    print_divider
    print_success "Connection '$name' added successfully!"
    print_info "Details: ${CYAN}${username}@${host}:${port}"
    echo
}

list_connections() {
    if [ ! -s "$CONFIG_FILE" ]; then
        print_header
        print_color "$YELLOW$BOLD" "${ICON_INFO} No connections found"
        print_info "Use ${CYAN}nedara-connect add${BLUE} to add a connection."
        echo
        return 0
    fi

    print_header
    print_color "$GREEN$BOLD" "${ICON_SERVER} Available connections:"
    print_divider

    local count=0
    while IFS=: read -r name username host port; do
        count=$((count + 1))
        echo -e "  ${CYAN}${count}.${RESET} ${WHITE}${BOLD}${name}${RESET}"
        echo -e "     ${GRAY}${ICON_USER} User:${RESET} ${GREEN}${username}${RESET}"
        echo -e "     ${GRAY}${ICON_SERVER} Host:${RESET} ${BLUE}${host}${RESET}"
        echo -e "     ${GRAY}${ICON_PORT} Port:${RESET} ${YELLOW}${port}${RESET}"
        local stored_pass
        stored_pass=$(get_password "$name")
        if [ -n "$stored_pass" ]; then
            echo -e "     ${GRAY}${ICON_LOCK} Password:${RESET} ${GREEN}(stored securely)${RESET}"
        fi
        echo
    done < "$CONFIG_FILE"

    print_divider
    print_info "Total: ${WHITE}${count}${BLUE} connection(s) configured"
    echo
}

delete_connection() {
    local name=$1

    if [ -z "$name" ]; then
        print_header
        print_error "Please specify a connection name to delete"
        echo
        list_connections
        exit 1
    fi

    if ! connection_exists "$name"; then
        print_header
        print_error "Connection '$name' not found"
        echo
        list_connections
        exit 1
    fi

    print_header
    print_color "$RED$BOLD" "${ICON_TRASH} Deleting connection '$name'"
    print_divider

    # Remove from config file
    sed -i "/^$name:/d" "$CONFIG_FILE"

    # Remove password if exists
    local current_passwords
    current_passwords=$(decrypt_passwords | grep -v "^$name:")
    encrypt_passwords "$current_passwords"

    print_success "Connection '$name' deleted successfully!"
    echo
}

connect() {
    local search=$1

    if [ -z "$search" ]; then
        print_header
        print_error "Please specify a connection name"
        echo
        list_connections
        exit 1
    fi

    local connection_details
    connection_details=$(grep "^$search:" "$CONFIG_FILE" 2>/dev/null)

    if [ -z "$connection_details" ]; then
        print_header
        print_error "Connection '$search' not found"
        echo
        list_connections
        exit 1
    fi

    local name username host port
    IFS=: read -r name username host port <<< "$connection_details"

    local password
    password=$(get_password "$name")

    print_header
    print_color "$GREEN$BOLD" "${ICON_CONNECT} Connecting to $name"
    print_divider
    print_info "User: ${GREEN}${username}"
    print_info "Host: ${BLUE}${host}"
    print_info "Port: ${YELLOW}${port}"
    if [ -n "$password" ]; then
        print_info "Auth: ${GREEN}Using saved password${RESET}"
    else
        print_info "Auth: ${YELLOW}Using SSH key or manual password entry${RESET}"
    fi
    echo
    print_color "$CYAN" "Establishing SSH connection..."
    print_divider
    echo

    if [ -n "$password" ]; then
        if ! command -v sshpass &> /dev/null; then
            print_error "sshpass is required for password authentication but not installed"
            print_info "Please install sshpass or connect without saved password"
            exit 1
        fi
        SSHPASS="$password" sshpass -e ssh -p "$port" "$username@$host"
    else
        ssh -p "$port" "$username@$host"
    fi

    echo
    print_divider
    print_info "Connection closed"
    echo
}

show_help() {
    print_header
    print_color "$WHITE$BOLD" "📖 Usage Guide"
    print_divider
    echo
    print_color "$CYAN$BOLD" "INTERACTIVE MODE (TUI):"
    echo
    echo -e "  ${GREEN}${BOLD}nedara-connect${RESET}               ${GRAY}# Launch interactive TUI (default)${RESET}"
    echo -e "  ${GREEN}${BOLD}nedara-connect tui${RESET}           ${GRAY}# Launch interactive TUI (explicit)${RESET}"
    echo
    print_color "$CYAN$BOLD" "CLI COMMANDS:"
    echo
    echo -e "  ${GREEN}${BOLD}nedara-connect add${RESET}           ${GRAY}# Add a new connection${RESET}"
    echo -e "  ${GREEN}${BOLD}nedara-connect list${RESET}          ${GRAY}# List all connections${RESET}"
    echo -e "  ${GREEN}${BOLD}nedara-connect delete <name>${RESET} ${GRAY}# Delete a connection${RESET}"
    echo -e "  ${GREEN}${BOLD}nedara-connect <name>${RESET}        ${GRAY}# Connect to a saved connection${RESET}"
    echo -e "  ${GREEN}${BOLD}nedara-connect update${RESET}        ${GRAY}# Check for updates and upgrade${RESET}"
    echo -e "  ${GREEN}${BOLD}nedara-connect help${RESET}          ${GRAY}# Show this help message${RESET}"
    echo
    print_color "$CYAN$BOLD" "EXAMPLES:"
    echo
    echo -e "  ${YELLOW}${ICON_BULLET} ${WHITE}nedara-connect add${RESET}      ${DIM}# Add a new connection${RESET}"
    echo -e "  ${YELLOW}${ICON_BULLET} ${WHITE}nedara-connect prod${RESET}     ${DIM}# Connect to 'prod' server${RESET}"
    echo -e "  ${YELLOW}${ICON_BULLET} ${WHITE}nedara-connect delete staging${RESET}  ${DIM}# Delete 'staging' connection${RESET}"
    echo
    print_divider
    print_info "Configuration stored in: ${CYAN}${CONFIG_FILE}"
    print_info "Passwords stored in:     ${CYAN}${PASS_FILE} (encrypted)"
    print_info "Encryption key in:       ${CYAN}${KEY_FILE} (keep this safe!)"
    echo
}

# Compare two semver strings. Returns 0 if $1 < $2 (i.e. update available).
_version_lt() {
    local IFS=.
    local -a a=($1) b=($2)
    for i in 0 1 2; do
        local x=${a[$i]:-0} y=${b[$i]:-0}
        [ "$x" -lt "$y" ] && return 0
        [ "$x" -gt "$y" ] && return 1
    done
    return 1
}

update_self() {
    print_header
    print_color "$PURPLE$BOLD" "🔄 Checking for updates..."
    print_divider
    echo

    if ! command -v curl &>/dev/null; then
        print_error "curl is required for updates but not installed."
        exit 1
    fi

    # Local version from this script's header
    local local_version
    local_version=$(grep -m1 '^# :version:' "$0" | sed 's/.*:version:[[:space:]]*//')
    print_info "Local version:  ${WHITE}${local_version}"

    # Remote version: fetch only the first 15 lines of the script
    local remote_version
    remote_version=$(curl -sf --max-time 10 "$GITHUB_RAW_URL" | head -15 \
        | grep -m1 '^# :version:' | sed 's/.*:version:[[:space:]]*//')

    if [ -z "$remote_version" ]; then
        print_error "Could not reach GitHub. Check your internet connection."
        exit 1
    fi

    print_info "Latest version: ${WHITE}${remote_version}"
    echo

    if ! _version_lt "$local_version" "$remote_version"; then
        print_success "Already up to date!"
        echo
        return
    fi

    print_color "$YELLOW$BOLD" "  New version available: ${remote_version}"
    echo
    print_prompt "Update now? [y/N] "
    read -r answer
    echo

    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        print_info "Update cancelled."
        echo
        return
    fi

    # Resolve the actual path of the installed script
    local script_path
    script_path=$(command -v nedara-connect 2>/dev/null)
    if [ -z "$script_path" ]; then
        script_path=$(readlink -f "$0" 2>/dev/null || echo "$0")
    fi

    print_color "$CYAN" "Downloading version ${remote_version}..."
    local tmpfile
    tmpfile=$(mktemp)
    if curl -sf --max-time 30 "$GITHUB_RAW_URL" -o "$tmpfile"; then
        chmod +x "$tmpfile"
        mv "$tmpfile" "$script_path"
        print_success "Updated to ${remote_version}!"
        print_info "Re-run any nedara-connect command to use the new version."
    else
        rm -f "$tmpfile"
        print_error "Download failed. Please try again."
        exit 1
    fi
    echo
}

# ─── Pure bash TUI (no external dependencies) ───────────────────────────────
#
# TUI functions NEVER use $() to return values — that would swallow their
# display output into a pipe and show nothing on screen. Instead they write
# to stdout (the terminal) directly, and store results in TUI_RESULT.

TUI_RESULT=""

# Read one keypress from the terminal, including arrow key escape sequences.
_tui_read_key() {
    local key seq
    IFS= read -rsn1 key </dev/tty
    if [[ "$key" == $'\x1b' ]]; then
        IFS= read -rsn2 -t 0.15 seq </dev/tty 2>/dev/null
        key="${key}${seq}"
    fi
    printf '%s' "$key"
}

# Draw the standard header, optionally with a subtitle line.
_tui_header() {
    local sub="${1:-}"
    clear
    echo
    print_color "$CYAN$BOLD" "  ╭─────────────────────────────────────────────╮"
    print_color "$CYAN$BOLD" "  │        ${WHITE}🚀 NEDARA CONNECT v0.4.0${CYAN}             │"
    if [ -n "$sub" ]; then
        printf "${CYAN}${BOLD}  │  ${WHITE}%-43s${CYAN}│${RESET}\n" "$sub"
    fi
    print_color "$CYAN$BOLD" "  ╰─────────────────────────────────────────────╯"
    echo
}

# Interactive arrow-key menu.
# Usage: _tui_menu "Subtitle" val1 "Label 1" val2 "Label 2" ...
# Result is stored in TUI_RESULT. Returns 1 on quit/Esc.
_tui_menu() {
    local sub="$1"; shift
    local -a values labels
    while [[ $# -ge 2 ]]; do
        values+=("$1"); labels+=("$2"); shift 2
    done

    local selected=0 n=${#values[@]} key

    while true; do
        _tui_header "$sub"
        for i in "${!values[@]}"; do
            if [ "$i" -eq "$selected" ]; then
                echo -e "  ${GREEN}${BOLD}▶  ${labels[$i]}${RESET}"
            else
                echo -e "  ${GRAY}   ${labels[$i]}${RESET}"
            fi
        done
        echo
        print_color "$DIM" "  ↑ ↓  navigate    Enter  select    q  quit"

        key=$(_tui_read_key)
        case "$key" in
            $'\x1b[A'|$'\x1bOA') [ "$selected" -gt 0 ]        && selected=$((selected - 1)) ;;
            $'\x1b[B'|$'\x1bOB') [ "$selected" -lt $((n-1)) ] && selected=$((selected + 1)) ;;
            ''|$'\n'|$'\r')  TUI_RESULT="${values[$selected]}"; return 0 ;;
            'q'|'Q'|$'\x1b'|$'\x03') TUI_RESULT=""; return 1 ;;
        esac
    done
}

# Single-line text prompt. Result stored in TUI_RESULT.
# Usage: _tui_input "Prompt text" ["default"]
_tui_input() {
    local prompt="$1" default="${2:-}"
    if [ -n "$default" ]; then
        printf "  ${YELLOW}▶ ${WHITE}%s${RESET} ${DIM}[%s]${RESET}: " "$prompt" "$default"
    else
        printf "  ${YELLOW}▶ ${WHITE}%s${RESET}: " "$prompt"
    fi
    IFS= read -r TUI_RESULT </dev/tty
    [ -z "$TUI_RESULT" ] && TUI_RESULT="$default"
}

# Silent password prompt. Result stored in TUI_RESULT.
_tui_password() {
    printf "  ${YELLOW}▶ ${WHITE}%s${RESET}: " "$1"
    IFS= read -rs TUI_RESULT </dev/tty
    echo
}

# Yes/No prompt. Returns 0 for yes, 1 for no (no TUI_RESULT).
_tui_yesno() {
    local answer
    printf "  ${YELLOW}▶ ${WHITE}%s${RESET} ${DIM}[y/N]${RESET}: " "$1"
    IFS= read -rn1 answer </dev/tty
    echo
    [[ "$answer" =~ ^[Yy]$ ]]
}

# Full-screen message. Waits for any key.
_tui_message() {
    _tui_header "$1"
    echo -e "  $2"
    echo
    print_color "$DIM" "  Press any key to continue..."
    IFS= read -rsn1 </dev/tty
}

_tui_connect() {
    if [ ! -s "$CONFIG_FILE" ]; then
        _tui_message "Connect" "No connections saved yet.\n\n  Use 'Add connection' to create one."
        return
    fi

    local -a args=()
    while IFS=: read -r name username host port; do
        args+=("$name" "$name  ($username@$host:$port)")
    done < "$CONFIG_FILE"

    _tui_menu "Connect to a host" "${args[@]}" || return
    local choice="$TUI_RESULT"

    clear
    connect "$choice"
}

_tui_add() {
    local name username host port password

    _tui_header "Add Connection"

    while true; do
        _tui_input "Connection name (letters, numbers, - and _)"
        name="$TUI_RESULT"
        if [ -z "$name" ]; then
            print_error "Name cannot be empty."; continue
        elif [[ "$name" =~ [^a-zA-Z0-9_-] ]]; then
            print_error "Allowed characters: letters, numbers, - and _"; continue
        elif connection_exists "$name"; then
            print_error "A connection named '$name' already exists."; continue
        fi
        break
    done

    while true; do
        _tui_input "Username"
        username="$TUI_RESULT"
        [ -n "$username" ] && break
        print_error "Username cannot be empty."
    done

    while true; do
        _tui_input "Hostname or IP address"
        host="$TUI_RESULT"
        [ -n "$host" ] && break
        print_error "Hostname cannot be empty."
    done

    _tui_input "Port" "22"
    port="${TUI_RESULT:-22}"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        print_error "Invalid port — using default 22."
        port=22
    fi

    if _tui_yesno "Save a password for this connection?"; then
        while true; do
            _tui_password "Password (stored encrypted)"
            password="$TUI_RESULT"
            if [ -n "$password" ]; then
                save_password "$name" "$password"
                break
            fi
            print_error "Password cannot be empty."
        done
    fi

    echo "$name:$username:$host:$port" >> "$CONFIG_FILE"
    echo
    print_success "Connection '$name' added!"
    print_info "  $username@$host:$port"
    echo
    print_color "$DIM" "  Press any key to continue..."
    IFS= read -rsn1 </dev/tty
}

_tui_list() {
    _tui_header "Saved Connections"

    if [ ! -s "$CONFIG_FILE" ]; then
        echo -e "  ${YELLOW}No connections saved yet.${RESET}"
        echo -e "  Use 'Add connection' to create one."
        echo
        print_color "$DIM" "  Press any key to continue..."
        IFS= read -rsn1 </dev/tty
        return
    fi

    local count=0
    while IFS=: read -r name username host port; do
        count=$((count + 1))
        local stored_pass
        stored_pass=$(get_password "$name")
        echo -e "  ${CYAN}${BOLD}${count}.${RESET} ${WHITE}${BOLD}${name}${RESET}"
        echo -e "     ${GRAY}User:${RESET} ${GREEN}${username}${RESET}  ${GRAY}Host:${RESET} ${BLUE}${host}${RESET}  ${GRAY}Port:${RESET} ${YELLOW}${port}${RESET}"
        [ -n "$stored_pass" ] && echo -e "     ${GRAY}${ICON_LOCK} Password stored securely${RESET}"
        echo
    done < "$CONFIG_FILE"

    print_divider
    print_info "Total: ${WHITE}${count}${BLUE} connection(s)"
    echo
    print_color "$DIM" "  Press any key to continue..."
    IFS= read -rsn1 </dev/tty
}

_tui_delete() {
    if [ ! -s "$CONFIG_FILE" ]; then
        _tui_message "Delete" "No connections found."
        return
    fi

    local -a args=()
    while IFS=: read -r name username host port; do
        args+=("$name" "$name  ($username@$host:$port)")
    done < "$CONFIG_FILE"

    _tui_menu "Delete a connection" "${args[@]}" || return
    local choice="$TUI_RESULT"

    _tui_header "Confirm Delete"
    echo -e "  ${RED}${BOLD}Delete '${choice}'?${RESET}"
    echo -e "  ${GRAY}This cannot be undone.${RESET}"
    echo
    _tui_yesno "Confirm deletion" || return

    sed -i "/^$choice:/d" "$CONFIG_FILE"
    local remaining
    remaining=$(decrypt_passwords | grep -v "^$choice:")
    encrypt_passwords "$remaining"

    echo
    print_success "Connection '$choice' deleted."
    echo
    print_color "$DIM" "  Press any key to continue..."
    IFS= read -rsn1 </dev/tty
}

launch_tui() {
    while true; do
        _tui_menu "" \
            "connect" "Connect to a saved host" \
            "add"     "Add a new connection" \
            "list"    "List all connections" \
            "delete"  "Delete a connection" || break

        case "$TUI_RESULT" in
            connect) _tui_connect ;;
            add)     _tui_add ;;
            list)    _tui_list ;;
            delete)  _tui_delete ;;
        esac
    done
    clear
}

# ─── Main ────────────────────────────────────────────────────────────────────

case "$1" in
    "add")
        add_connection
        ;;
    "list")
        list_connections
        ;;
    "delete")
        delete_connection "$2"
        ;;
    "tui")
        launch_tui
        ;;
    "update")
        update_self
        ;;
    "help"|"-h"|"--help")
        show_help
        ;;
    "")
        launch_tui
        ;;
    *)
        connect "$1"
        ;;
esac
