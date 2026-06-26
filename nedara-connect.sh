#!/bin/bash
# :project:    Nedara Connect
# :version:    0.3.2-alpha
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

# ─── TUI ────────────────────────────────────────────────────────────────────

TUI_TOOL=""

# Wrapper: uses dialog (with mouse) if available, otherwise whiptail
_d() {
    if [ "$TUI_TOOL" = "dialog" ]; then
        dialog --mouse "$@"
    else
        whiptail "$@"
    fi
}

_tui_connect() {
    if [ ! -s "$CONFIG_FILE" ]; then
        _d --title " Nedara Connect " --msgbox \
            "\nNo connections saved yet.\n\nGo to 'Add connection' to create one." 9 52
        return
    fi

    local items=()
    while IFS=: read -r name username host port; do
        items+=("$name" "$username@$host:$port")
    done < "$CONFIG_FILE"

    local choice
    choice=$(_d --title " Connect " \
        --menu "\nSelect a connection:" 16 56 8 \
        "${items[@]}" 3>&1 1>&2 2>&3) || return

    clear
    connect "$choice"
}

_tui_add() {
    local name username host port password

    while true; do
        name=$(_d --title " Add Connection (1/4) " --inputbox \
            "\nConnection name  (letters, numbers, - and _):" 9 56 "" \
            3>&1 1>&2 2>&3) || return
        if [ -z "$name" ]; then
            _d --title " Error " --msgbox "\nName cannot be empty." 7 40
        elif [[ "$name" =~ [^a-zA-Z0-9_-] ]]; then
            _d --title " Error " --msgbox \
                "\nAllowed characters: letters, numbers, - and _" 8 50
        elif connection_exists "$name"; then
            _d --title " Error " --msgbox \
                "\nA connection named '$name' already exists." 7 50
        else
            break
        fi
    done

    while true; do
        username=$(_d --title " Add Connection (2/4) " --inputbox \
            "\nUsername:" 9 56 "" 3>&1 1>&2 2>&3) || return
        [ -n "$username" ] && break
        _d --title " Error " --msgbox "\nUsername cannot be empty." 7 40
    done

    while true; do
        host=$(_d --title " Add Connection (3/4) " --inputbox \
            "\nHostname or IP address:" 9 56 "" 3>&1 1>&2 2>&3) || return
        [ -n "$host" ] && break
        _d --title " Error " --msgbox "\nHostname cannot be empty." 7 40
    done

    port=$(_d --title " Add Connection (4/4) " --inputbox \
        "\nPort:" 9 56 "22" 3>&1 1>&2 2>&3) || return
    port=${port:-22}
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        _d --title " Warning " --msgbox "\nInvalid port — using default 22." 7 44
        port=22
    fi

    if _d --title " Add Connection " --yesno \
        "\nSave a password for this connection?" 7 50; then
        while true; do
            password=$(_d --title " Add Connection " --passwordbox \
                "\nPassword (stored encrypted):" 9 56 3>&1 1>&2 2>&3) || break
            if [ -n "$password" ]; then
                save_password "$name" "$password"
                break
            fi
            _d --title " Error " --msgbox "\nPassword cannot be empty." 7 40
        done
    fi

    echo "$name:$username:$host:$port" >> "$CONFIG_FILE"
    _d --title " Success " --msgbox \
        "\nConnection '$name' added!\n\n  User : $username\n  Host : $host\n  Port : $port" \
        11 50
}

_tui_list() {
    if [ ! -s "$CONFIG_FILE" ]; then
        _d --title " Connections " --msgbox \
            "\nNo connections saved yet.\n\nGo to 'Add connection' to create one." 9 52
        return
    fi

    local msg="" count=0
    while IFS=: read -r name username host port; do
        count=$((count + 1))
        local stored_pass
        stored_pass=$(get_password "$name")
        local lock=""
        [ -n "$stored_pass" ] && lock="  [password saved]"
        msg+="$count.  $name\n    $username@$host:$port$lock\n\n"
    done < "$CONFIG_FILE"

    _d --title " Connections ($count) " --msgbox "$msg" 20 60
}

_tui_delete() {
    if [ ! -s "$CONFIG_FILE" ]; then
        _d --title " Delete " --msgbox "\nNo connections found." 7 40
        return
    fi

    local items=()
    while IFS=: read -r name username host port; do
        items+=("$name" "$username@$host:$port")
    done < "$CONFIG_FILE"

    local choice
    choice=$(_d --title " Delete Connection " \
        --menu "\nSelect a connection to delete:" 16 56 8 \
        "${items[@]}" 3>&1 1>&2 2>&3) || return

    _d --title " Confirm " --yesno \
        "\nDelete '$choice'?\n\nThis cannot be undone." 9 48 || return

    sed -i "/^$choice:/d" "$CONFIG_FILE"
    local remaining
    remaining=$(decrypt_passwords | grep -v "^$choice:")
    encrypt_passwords "$remaining"

    _d --title " Deleted " --msgbox "\nConnection '$choice' deleted." 7 44
}

launch_tui() {
    if command -v dialog &>/dev/null; then
        TUI_TOOL="dialog"
    elif command -v whiptail &>/dev/null; then
        TUI_TOOL="whiptail"
    else
        print_error "TUI requires 'dialog' or 'whiptail'"
        print_info "Install with: sudo apt-get install dialog"
        exit 1
    fi

    while true; do
        local choice
        choice=$(_d \
            --title " Nedara Connect v0.3.2 " \
            --cancel-label "Exit" \
            --menu "\n  SSH Connection Manager\n" 14 54 4 \
            "connect" "  Connect to a saved host" \
            "add"     "  Add a new connection" \
            "list"    "  List all connections" \
            "delete"  "  Delete a connection" \
            3>&1 1>&2 2>&3) || break

        case "$choice" in
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
