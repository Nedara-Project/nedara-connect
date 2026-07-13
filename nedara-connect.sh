#!/bin/bash
# :project:    Nedara Connect
# :version:    0.6.0
# :license:    MIT
# :copyright:  (c) 2025 Nedara Project
# :author:     Andrea Ulliana
# :repository: https://github.com/Nedara-Project/nedara-connect
# :overview:   Nedara-connect is a lightweight shell tool for managing and connecting to SSH hosts
# :published:  2025-04-08
# :modified:   2026-07-13

# Configuration
CONFIG_FILE="$HOME/.ssh/connections.conf"
PASS_FILE="$HOME/.ssh/connections_pass.gpg"
KEY_FILE="$HOME/.ssh/connections_key"
VERSION_CACHE="$HOME/.ssh/nedara_version_cache"
CONFIG_DIR="$HOME/.ssh"
GITHUB_RAW_URL="https://raw.githubusercontent.com/Nedara-Project/nedara-connect/main/nedara-connect.sh"

# Optional cloud sync (Nedara Connect Web) — nothing here runs unless the
# user explicitly opts in via `nedara-connect sync login`.
SYNC_CONFIG_FILE="$HOME/.ssh/connections_sync.conf"
SYNC_TOKEN_FILE="$HOME/.ssh/connections_sync_token.gpg"

# Local cache of shared directories known from the last `sync pull`/`sync
# directories` (id:name:org_name:role per line). Used to group connections
# into "My Connections" + shared directories, and to offer a location picker
# in add/edit. Only ever populated for users who opted into sync.
DIRECTORIES_CACHE_FILE="$HOME/.ssh/connections_directories.conf"

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
    print_color "$CYAN$BOLD" "│           ${WHITE}🚀 NEDARA CONNECT v0.6.0${CYAN}              │"
    print_color "$CYAN$BOLD" "│            ${DIM}${WHITE}SSH Connection Manager${CYAN}               │"
    print_color "$CYAN$BOLD" "╰─────────────────────────────────────────────────╯"
    echo
    _show_update_notice
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

# Compare two semver strings. Returns 0 if $1 < $2 (update available).
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

# Print a one-line update notice if a newer version is in the cache (no network).
_show_update_notice() {
    [ -f "$VERSION_CACHE" ] || return
    local local_version cached
    local_version=$(grep -m1 '^# :version:' "$0" | sed 's/.*:version:[[:space:]]*//')
    cached=$(cat "$VERSION_CACHE" 2>/dev/null)
    if [ -n "$cached" ] && _version_lt "$local_version" "$cached"; then
        print_color "$YELLOW" "  💡 v${cached} available — run: ${CYAN}nedara-connect update${RESET}"
        echo
    fi
}

# Refresh the remote version cache silently in the background.
# Uses a tmpfile + mv to avoid partial reads by _show_update_notice.
_refresh_version_cache() {
    (
        local tmp
        tmp=$(mktemp) || exit
        if curl -sf --max-time 5 "$GITHUB_RAW_URL" 2>/dev/null \
            | head -15 \
            | grep -m1 '^# :version:' \
            | sed 's/.*:version:[[:space:]]*//' \
            > "$tmp" && [ -s "$tmp" ]; then
            mv "$tmp" "$VERSION_CACHE"
        else
            rm -f "$tmp"
        fi
    ) &
    disown $! 2>/dev/null
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

# Refresh the version cache in the background if it is missing or older than 24h.
if [ ! -f "$VERSION_CACHE" ] || \
   [ -n "$(find "$VERSION_CACHE" -mmin +1440 2>/dev/null)" ]; then
    _refresh_version_cache
fi

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

# ─── Directory grouping ("My Connections" + shared directories) ─────────────
#
# Each CONFIG_FILE line has an optional 5th field: the shared directory_id a
# connection was synced into (empty/absent = personal "My Connections").
# Old 4-field lines are unaffected — a missing 5th field simply reads as
# empty, which is exactly the personal scope. No migration is required.

# Prints the CONFIG_FILE lines belonging to one location.
# Usage: _connections_in_group <directory_id>  (empty = "My Connections")
_connections_in_group() {
    local dir_id="$1"
    awk -F: -v d="$dir_id" '{ if ($5 == d) print }' "$CONFIG_FILE" 2>/dev/null
}

# Human label for a directory id, using the local cache populated by
# `sync pull` / `sync directories`. Falls back gracefully if the directory is
# unknown locally (e.g. cache not refreshed since it was created/renamed).
_directory_label() {
    local dir_id="$1"
    if [ -z "$dir_id" ]; then
        echo "My Connections"
        return 0
    fi

    local line
    line=$([ -s "$DIRECTORIES_CACHE_FILE" ] && awk -F: -v id="$dir_id" '$1==id{print; exit}' "$DIRECTORIES_CACHE_FILE" 2>/dev/null)
    if [ -n "$line" ]; then
        local _id name org _role
        IFS=: read -r _id name org _role <<< "$line"
        echo "${name} (${org})"
    else
        echo "Shared directory (${dir_id})"
    fi
}

# The access role ('read-only' / 'read-write' / 'read-write-delete') this
# machine's account has on a directory, per the local cache. Empty if unknown.
_directory_role() {
    local dir_id="$1"
    [ -s "$DIRECTORIES_CACHE_FILE" ] || return 0
    awk -F: -v id="$dir_id" '$1==id{print $4; exit}' "$DIRECTORIES_CACHE_FILE" 2>/dev/null
}

# Refreshes the local directories cache from a JSON array of
# {id, name, org_name, role} objects (as returned by the CLI API).
_write_directories_cache() {
    local directories_json="$1"
    local tmp
    tmp=$(mktemp)
    echo "$directories_json" | jq -r '.[] | [.id, .name, .org_name, (.role // "")] | @tsv' \
        | tr '\t' ':' > "$tmp"
    mv "$tmp" "$DIRECTORIES_CACHE_FILE"
    chmod 600 "$DIRECTORIES_CACHE_FILE"
}

# Non-interactive location picker: prints "0) My Connections" then each known
# shared directory. Only ever shown if directories are known locally (i.e.
# the user has used sync at least once) — never forces sync on anyone.
_print_location_choices() {
    echo -e "     ${GRAY}0)${RESET} My Connections"
    awk -F: '{printf "     %d) %s (%s)\n", NR, $2, $3}' "$DIRECTORIES_CACHE_FILE"
}

# Prompts for a location (only if directories are known locally). Result is
# stored in LOCATION_RESULT; defaults to $1 (current/personal) if skipped,
# cancelled, or sync was never used.
_prompt_location() {
    local default_id="${1:-}"
    LOCATION_RESULT="$default_id"
    [ -s "$DIRECTORIES_CACHE_FILE" ] || return 0

    echo
    print_info "Location:"
    _print_location_choices
    local default_index
    default_index=$(awk -F: -v id="$default_id" '$1==id{print NR}' "$DIRECTORIES_CACHE_FILE")
    default_index=${default_index:-0}
    print_prompt "Choice [$default_index]: "
    read -r choice
    choice=${choice:-$default_index}

    if [ -z "$choice" ] || [ "$choice" = "0" ]; then
        LOCATION_RESULT=""
    elif [[ "$choice" =~ ^[0-9]+$ ]]; then
        local picked
        picked=$(awk -F: -v n="$choice" 'NR==n{print $1}' "$DIRECTORIES_CACHE_FILE")
        LOCATION_RESULT="${picked:-$default_id}"
    fi
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

# ─── Cloud Sync (optional) ───────────────────────────────────────────────────
#
# Everything below is 100% opt-in. Nothing here runs unless the user
# explicitly runs `nedara-connect sync login`; existing users who never touch
# sync see no behavior change on add/list/edit/delete/connect/tui/update.

# Function to check for sync-only dependencies (curl is already required elsewhere)
_check_sync_deps() {
    if ! command -v curl &>/dev/null; then
        print_error "curl is required for sync but not installed."
        return 1
    fi
    if ! command -v jq &>/dev/null; then
        print_error "jq is required for sync but not installed."
        print_info "Install it with your package manager, e.g. 'brew install jq' or 'apt-get install jq'."
        return 1
    fi
    return 0
}

# Function to read a key's value from the sync config file
_sync_config_get() {
    local key=$1
    [ -f "$SYNC_CONFIG_FILE" ] || return 0
    grep "^$key:" "$SYNC_CONFIG_FILE" 2>/dev/null | cut -d: -f2- | tr -d '\n'
}

# Function to write/update a key's value in the sync config file
_sync_config_set() {
    local key=$1
    local value=$2
    local tmp
    tmp=$(mktemp)
    [ -f "$SYNC_CONFIG_FILE" ] && grep -v "^$key:" "$SYNC_CONFIG_FILE" > "$tmp"
    echo "$key:$value" >> "$tmp"
    mv "$tmp" "$SYNC_CONFIG_FILE"
    chmod 600 "$SYNC_CONFIG_FILE"
}

is_sync_enabled() {
    [ "$(_sync_config_get enabled)" = "yes" ]
}

# Function to decrypt the stored personal API token (PAT)
decrypt_sync_token() {
    if [ -s "$SYNC_TOKEN_FILE" ]; then
        gpg --batch --yes --quiet --pinentry-mode loopback \
            --passphrase "$(get_encryption_key)" --decrypt "$SYNC_TOKEN_FILE" 2>/dev/null \
            | grep '^token:' | cut -d: -f2- | tr -d '\n'
    fi
}

# Function to encrypt and store the personal API token (PAT)
encrypt_sync_token() {
    local token=$1
    echo "token:$token" | gpg --batch --yes --quiet --pinentry-mode loopback \
        --passphrase "$(get_encryption_key)" --symmetric --output "$SYNC_TOKEN_FILE"
    chmod 600 "$SYNC_TOKEN_FILE"
}

# Function to call the Nedara Connect Web REST API, authenticated with the PAT.
# Always returns the response body, even on 4xx/5xx (so callers can inspect a
# `.error` field with `_print_api_error`) — an empty result means the request
# never reached the server at all.
# Usage: _curl_json <method> <path> [json_body]
_curl_json() {
    local method=$1
    local path=$2
    local body=$3
    local endpoint
    endpoint=$(_sync_config_get endpoint)
    local token
    token=$(decrypt_sync_token)

    if [ -n "$body" ]; then
        curl -s --max-time 15 -X "$method" "${endpoint}${path}" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "$body"
    else
        curl -s --max-time 15 -X "$method" "${endpoint}${path}" \
            -H "Authorization: Bearer $token"
    fi
}

# Prints `.error` from a JSON API response, prefixed with some context, if present.
# Returns 0 (an error was found and printed) / 1 (no error field).
_print_api_error() {
    local response="$1" context="$2"
    if [ -n "$response" ] && echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        print_error "${context}: $(echo "$response" | jq -r '.error')"
        return 0
    fi
    return 1
}

sync_login() {
    print_header
    print_color "$PURPLE$BOLD" "☁️  Connect to Nedara Connect Web"
    print_divider
    _check_sync_deps || { echo; exit 1; }

    print_prompt "Endpoint [https://connect.nedara.org]: "
    read -r endpoint
    endpoint=${endpoint:-https://connect.nedara.org}
    endpoint=${endpoint%/}

    print_prompt "Personal API token: "
    read -rs token
    echo
    if [ -z "$token" ]; then
        print_error "A token is required. Generate one from the web app's API Tokens page."
        echo
        exit 1
    fi

    local response
    response=$(curl -sf --max-time 15 "${endpoint}/api/cli/verify" -H "Authorization: Bearer $token")
    if [ -z "$response" ] || ! echo "$response" | jq -e '.valid' >/dev/null 2>&1; then
        print_error "Could not verify this token against ${endpoint}."
        echo
        exit 1
    fi

    encrypt_sync_token "$token"
    _sync_config_set "endpoint" "$endpoint"
    _sync_config_set "enabled" "yes"

    local username
    username=$(echo "$response" | jq -r '.user.username')
    echo
    print_success "Signed in as ${username} (${endpoint})"
    print_info "Use ${CYAN}nedara-connect sync push${BLUE} / ${CYAN}sync pull${BLUE} to synchronize."
    echo
}

sync_status() {
    print_header
    print_color "$WHITE$BOLD" "☁️  Sync Status"
    print_divider
    if ! is_sync_enabled; then
        print_info "Sync is ${YELLOW}not configured${BLUE}. Run ${CYAN}nedara-connect sync login${BLUE} to enable it."
        echo
        return 0
    fi

    local endpoint
    endpoint=$(_sync_config_get endpoint)
    print_info "Endpoint:      ${CYAN}${endpoint}"

    _check_sync_deps || { echo; exit 1; }
    local response
    response=$(curl -sf --max-time 15 "${endpoint}/api/cli/verify" -H "Authorization: Bearer $(decrypt_sync_token)")
    if [ -n "$response" ] && echo "$response" | jq -e '.valid' >/dev/null 2>&1; then
        print_info "Signed in as: ${GREEN}$(echo "$response" | jq -r '.user.username')"
    else
        print_color "$RED$BOLD" "${ICON_ERROR} Token is invalid or revoked."
    fi

    local last_push last_pull
    last_push=$(_sync_config_get last_push)
    last_pull=$(_sync_config_get last_pull)
    print_info "Last push:     ${CYAN}${last_push:-never}"
    print_info "Last pull:     ${CYAN}${last_pull:-never}"
    echo
}

# Builds a JSON array of local connections for pushing.
# Usage: _build_connections_json <match_directory_id> <mode>
#   mode="all"    → every local connection, regardless of its tagged location
#   mode anything else → only connections tagged with directory_id == match_directory_id
#                         (empty match_directory_id = personal / "My Connections")
_build_connections_json() {
    local match_dir_id="$1" mode="$2"
    local connections_json="[]"
    local name username host port dir_id password entry
    while IFS=: read -r name username host port dir_id; do
        [ -n "$name" ] || continue
        if [ "$mode" != "all" ] && [ "${dir_id:-}" != "$match_dir_id" ]; then
            continue
        fi
        password=$(get_password "$name")
        entry=$(jq -n --arg name "$name" --arg host "$host" --argjson port "$port" \
            --arg username "$username" --arg password "$password" \
            '{name: $name, host: $host, port: $port, username: $username, password: $password}')
        connections_json=$(echo "$connections_json" | jq --argjson e "$entry" '. + [$e]')
    done < "$CONFIG_FILE"
    echo "$connections_json"
}

# Pushes one group of local connections to a single target location.
# Usage: _sync_push_group <label> <target_directory_id> <mode>
# (empty target_directory_id = personal; see _build_connections_json for mode)
_sync_push_group() {
    local label="$1" target_dir_id="$2" mode="$3"
    local connections_json
    connections_json=$(_build_connections_json "$target_dir_id" "$mode")
    local count
    count=$(echo "$connections_json" | jq 'length')
    [ "$count" -gt 0 ] || return 0

    local body
    if [ -n "$target_dir_id" ]; then
        body=$(jq -n --argjson connections "$connections_json" --arg dir "$target_dir_id" \
            '{connections: $connections, directory_id: $dir}')
    else
        body=$(jq -n --argjson connections "$connections_json" '{connections: $connections}')
    fi

    local response
    response=$(_curl_json POST "/api/cli/connections" "$body")
    if [ -z "$response" ]; then
        print_error "Push to ${label} failed — check your connection and token."
        return 1
    fi
    if _print_api_error "$response" "Push to ${label}"; then
        return 1
    fi

    local created updated conflicts
    created=$(echo "$response" | jq -r '.created | length')
    updated=$(echo "$response" | jq -r '.updated | length')
    conflicts=$(echo "$response" | jq -r '.conflicts | length')

    print_success "${label} — Created: ${created}  •  Updated: ${updated}  •  Conflicts: ${conflicts}"
    if [ "$conflicts" -gt 0 ]; then
        print_color "$YELLOW" "  Conflicting names (not overwritten remotely): $(echo "$response" | jq -r '.conflicts | join(", ")')"
    fi
    return 0
}

sync_push() {
    if ! is_sync_enabled; then
        print_error "Sync is not configured. Run 'nedara-connect sync login' first."
        exit 1
    fi
    _check_sync_deps || exit 1

    local explicit_dir=$1
    print_header
    print_color "$PURPLE$BOLD" "☁️  Pushing local connections..."
    print_divider

    if [ ! -s "$CONFIG_FILE" ]; then
        print_info "No local connections to push."
        echo
        return 0
    fi

    if [ -n "$explicit_dir" ]; then
        # Explicit target: push every local connection into this one
        # directory, regardless of where each is otherwise tagged.
        local role
        role=$(_directory_role "$explicit_dir")
        if [ "$role" = "read-only" ]; then
            print_error "You only have read-only access to this directory — push refused."
            echo
            exit 1
        fi
        _sync_push_group "directory ${explicit_dir}" "$explicit_dir" "all"
    else
        # Smart default: push everything to where it's tagged locally —
        # "My Connections" plus each shared directory, in one go.
        _sync_push_group "My Connections" "" "filter"
        local dir_ids
        dir_ids=$(cut -d: -f5 "$CONFIG_FILE" | grep -v '^$' | sort -u)
        if [ -n "$dir_ids" ]; then
            while IFS= read -r dir_id; do
                [ -n "$dir_id" ] || continue
                _sync_push_group "$(_directory_label "$dir_id")" "$dir_id" "filter"
            done <<< "$dir_ids"
        fi
    fi

    _sync_config_set "last_push" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
}

sync_pull() {
    if ! is_sync_enabled; then
        print_error "Sync is not configured. Run 'nedara-connect sync login' first."
        exit 1
    fi
    _check_sync_deps || exit 1

    local force=$1
    print_header
    print_color "$PURPLE$BOLD" "☁️  Pulling remote connections..."
    print_divider

    local response
    response=$(_curl_json GET "/api/cli/connections")
    if [ -z "$response" ]; then
        print_error "Pull failed. Check your connection and token."
        exit 1
    fi
    if _print_api_error "$response" "Pull"; then
        exit 1
    fi

    # Recreate the "My Connections" + shared-directories grouping locally.
    _write_directories_cache "$(echo "$response" | jq '[.directories[] | {id, name, org_name, role}]')"

    local added=0 skipped=0
    while IFS=$'\t' read -r name host port username password dir_id; do
        [ -n "$name" ] || continue
        if connection_exists "$name"; then
            local existing existing_host existing_username existing_dir
            existing=$(grep "^$name:" "$CONFIG_FILE")
            IFS=: read -r _ existing_username existing_host _ existing_dir <<< "$existing"
            if [ "$existing_host" = "$host" ] && [ "$existing_username" = "$username" ] && [ "${existing_dir:-}" = "${dir_id:-}" ]; then
                continue
            fi
            if [ "$force" != "--force" ]; then
                print_color "$YELLOW" "  ⚠ Conflict on '${name}' (local: ${existing_username}@${existing_host}, remote: ${username}@${host}) — skipped. Use --force to overwrite."
                skipped=$((skipped + 1))
                continue
            fi
            local tmp
            tmp=$(mktemp)
            grep -v "^$name:" "$CONFIG_FILE" > "$tmp"
            echo "$name:$username:$host:$port:$dir_id" >> "$tmp"
            mv "$tmp" "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE"
        else
            echo "$name:$username:$host:$port:$dir_id" >> "$CONFIG_FILE"
        fi
        [ -n "$password" ] && save_password "$name" "$password"
        added=$((added + 1))
    done < <(echo "$response" | jq -r '(.personal + ([.directories[].connections[]?])) | .[] | [.name, .host, (.port|tostring), .username, (.password // ""), (.directory_id // "")] | @tsv')

    print_success "Pulled: ${added}  •  Skipped (conflicts): ${skipped}"
    _sync_config_set "last_pull" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
}

sync_directories() {
    if ! is_sync_enabled; then
        print_error "Sync is not configured. Run 'nedara-connect sync login' first."
        exit 1
    fi
    _check_sync_deps || exit 1

    print_header
    print_color "$WHITE$BOLD" "☁️  Shared Directories"
    print_divider

    local response
    response=$(_curl_json GET "/api/cli/directories")
    if [ -z "$response" ]; then
        print_error "Could not reach the server. Check your connection and token."
        echo
        exit 1
    fi
    if _print_api_error "$response" "Directories"; then
        echo
        exit 1
    fi
    if [ "$(echo "$response" | jq 'length')" -eq 0 ]; then
        print_info "No shared directories available to this account."
        echo
        return 0
    fi

    _write_directories_cache "$response"

    echo "$response" | jq -r '.[] | "\(.id)\t\(.name)\t\(.org_name)\t\(.role)"' | while IFS=$'\t' read -r id name org role; do
        echo -e "  ${CYAN}${id}${RESET}  ${WHITE}${BOLD}${name}${RESET} ${GRAY}(${org})${RESET}  ${DIM}[${role}]${RESET}"
    done
    echo
    print_info "Connections already tagged with a location sync automatically with a plain ${CYAN}nedara-connect sync push${BLUE}."
    print_info "To bulk-assign every local connection to one directory: ${CYAN}nedara-connect sync push <directory-id>"
    echo
}

sync_logout() {
    print_header
    print_color "$WHITE$BOLD" "☁️  Disabling Sync"
    print_divider
    rm -f "$SYNC_TOKEN_FILE"
    _sync_config_set "enabled" "no"
    print_success "Sync disabled. Your local connections are untouched."
    echo
}

sync_dispatch() {
    local action=$1
    shift
    case "$action" in
        login)       sync_login ;;
        status)      sync_status ;;
        push)        sync_push "$@" ;;
        pull)        sync_pull "$@" ;;
        directories) sync_directories ;;
        logout)      sync_logout ;;
        *)
            print_error "Unknown sync command: ${action:-<none>}"
            print_info "Usage: nedara-connect sync {login|status|push|pull|directories|logout}"
            exit 1
            ;;
    esac
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

    _prompt_location ""
    local directory_id="$LOCATION_RESULT"

    echo "$name:$username:$host:$port:$directory_id" >> "$CONFIG_FILE"

    echo
    print_divider
    print_success "Connection '$name' added successfully!"
    print_info "Details: ${CYAN}${username}@${host}:${port}"
    print_info "Location: ${CYAN}$(_directory_label "$directory_id")"
    echo
}

# Prints one "My Connections" / directory section for `list_connections`,
# incrementing the global _LIST_COUNT for each connection printed.
_print_connection_group() {
    local dir_id="$1" label="$2"
    local lines
    lines=$(_connections_in_group "$dir_id")
    [ -n "$lines" ] || return 0

    echo -e "  ${WHITE}${BOLD}📁 ${label}${RESET}"
    echo
    local name username host port _dir
    while IFS=: read -r name username host port _dir; do
        [ -n "$name" ] || continue
        _LIST_COUNT=$((_LIST_COUNT + 1))
        echo -e "  ${CYAN}${_LIST_COUNT}.${RESET} ${WHITE}${BOLD}${name}${RESET}"
        echo -e "     ${GRAY}${ICON_USER} User:${RESET} ${GREEN}${username}${RESET}"
        echo -e "     ${GRAY}${ICON_SERVER} Host:${RESET} ${BLUE}${host}${RESET}"
        echo -e "     ${GRAY}${ICON_PORT} Port:${RESET} ${YELLOW}${port}${RESET}"
        local stored_pass
        stored_pass=$(get_password "$name")
        if [ -n "$stored_pass" ]; then
            echo -e "     ${GRAY}${ICON_LOCK} Password:${RESET} ${GREEN}(stored securely)${RESET}"
        fi
        echo
    done <<< "$lines"
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
    echo

    _LIST_COUNT=0
    _print_connection_group "" "My Connections"

    local dir_ids
    dir_ids=$(cut -d: -f5 "$CONFIG_FILE" | grep -v '^$' | sort -u)
    if [ -n "$dir_ids" ]; then
        while IFS= read -r dir_id; do
            [ -n "$dir_id" ] || continue
            _print_connection_group "$dir_id" "$(_directory_label "$dir_id")"
        done <<< "$dir_ids"
    fi

    print_divider
    print_info "Total: ${WHITE}${_LIST_COUNT}${BLUE} connection(s) configured"
    echo
}

delete_connection() {
    local name=$1

    if [ -z "$name" ]; then
        print_error "Please specify a connection name to delete"
        echo
        list_connections
        exit 1
    fi

    if ! connection_exists "$name"; then
        print_error "Connection '$name' not found"
        echo
        list_connections
        exit 1
    fi

    print_header
    print_color "$RED$BOLD" "${ICON_TRASH} Deleting connection '$name'"
    print_divider

    # Remove from config file
    local tmp
    tmp=$(mktemp)
    grep -v "^$name:" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"

    # Remove password if exists
    local current_passwords
    current_passwords=$(decrypt_passwords | grep -v "^$name:")
    encrypt_passwords "$current_passwords"

    print_success "Connection '$name' deleted successfully!"
    echo
}

edit_connection() {
    local name=$1

    if [ -z "$name" ]; then
        print_error "Please specify a connection name to edit"
        echo
        list_connections
        exit 1
    fi

    if ! connection_exists "$name"; then
        print_error "Connection '$name' not found"
        echo
        list_connections
        exit 1
    fi

    local connection_details
    connection_details=$(grep "^$name:" "$CONFIG_FILE")
    local cur_name cur_username cur_host cur_port cur_dir_id
    IFS=: read -r cur_name cur_username cur_host cur_port cur_dir_id <<< "$connection_details"

    print_header
    print_color "$PURPLE$BOLD" "✏️  Editing connection '$name'"
    print_divider
    print_color "$DIM" "  Press Enter to keep the current value."
    echo

    while true; do
        print_prompt "Username [$cur_username]: "
        read -r username
        username=${username:-$cur_username}
        if validate_input "$username" "username"; then
            break
        fi
    done

    while true; do
        print_prompt "Hostname or IP address [$cur_host]: "
        read -r host
        host=${host:-$cur_host}
        if validate_input "$host" "hostname"; then
            break
        fi
    done

    print_prompt "Port [$cur_port]: "
    read -r port
    port=${port:-$cur_port}
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        print_error "Invalid port. Keeping current value $cur_port."
        port=$cur_port
    fi

    local stored_pass
    stored_pass=$(get_password "$name")
    if [ -n "$stored_pass" ]; then
        print_prompt "Update saved password? [y/N] "
    else
        print_prompt "Add a password for this connection? [y/N] "
    fi
    read -r update_pass
    if [[ "$update_pass" =~ ^[Yy]$ ]]; then
        while true; do
            print_prompt "New password (will be stored encrypted): "
            read -rs password
            echo
            if validate_input "$password" "password"; then
                save_password "$name" "$password"
                print_success "Password updated securely!"
                break
            fi
        done
    fi

    local directory_id="$cur_dir_id"
    if [ -s "$DIRECTORIES_CACHE_FILE" ]; then
        print_prompt "Move to a different location? (currently: $(_directory_label "$cur_dir_id")) [y/N] "
        read -r move_loc
        if [[ "$move_loc" =~ ^[Yy]$ ]]; then
            _prompt_location "$cur_dir_id"
            directory_id="$LOCATION_RESULT"
        fi
    fi

    local tmp
    tmp=$(mktemp)
    grep -v "^$name:" "$CONFIG_FILE" > "$tmp"
    echo "$name:$username:$host:$port:$directory_id" >> "$tmp"
    mv "$tmp" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"

    echo
    print_divider
    print_success "Connection '$name' updated successfully!"
    print_info "Details: ${CYAN}${username}@${host}:${port}"
    print_info "Location: ${CYAN}$(_directory_label "$directory_id")"
    echo
}

connect() {
    local search=$1

    if [ -z "$search" ]; then
        print_error "Please specify a connection name"
        echo
        list_connections
        exit 1
    fi

    local connection_details
    connection_details=$(grep "^$search:" "$CONFIG_FILE" 2>/dev/null)

    if [ -z "$connection_details" ]; then
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
    echo -e "  ${GREEN}${BOLD}nedara-connect edit <name>${RESET}   ${GRAY}# Edit an existing connection${RESET}"
    echo -e "  ${GREEN}${BOLD}nedara-connect delete <name>${RESET} ${GRAY}# Delete a connection${RESET}"
    echo -e "  ${GREEN}${BOLD}nedara-connect <name>${RESET}        ${GRAY}# Connect to a saved connection${RESET}"
    echo -e "  ${GREEN}${BOLD}nedara-connect update${RESET}        ${GRAY}# Check for updates and upgrade${RESET}"
    echo -e "  ${GREEN}${BOLD}nedara-connect help${RESET}          ${GRAY}# Show this help message${RESET}"
    echo
    print_color "$CYAN$BOLD" "SYNC COMMANDS (optional, requires Nedara Connect Web):"
    echo
    echo -e "  ${GREEN}${BOLD}nedara-connect sync login${RESET}        ${GRAY}# Connect this machine with a personal API token${RESET}"
    echo -e "  ${GREEN}${BOLD}nedara-connect sync status${RESET}       ${GRAY}# Show sync status${RESET}"
    echo -e "  ${GREEN}${BOLD}nedara-connect sync push${RESET}         ${GRAY}# Push every local connection to its own location (My Connections + shared directories)${RESET}"
    echo -e "  ${GREEN}${BOLD}nedara-connect sync push <dir-id>${RESET} ${GRAY}# Push every local connection into one specific shared directory${RESET}"
    echo -e "  ${GREEN}${BOLD}nedara-connect sync pull [--force]${RESET} ${GRAY}# Pull remote connections, recreating My Connections + shared directories locally${RESET}"
    echo -e "  ${GREEN}${BOLD}nedara-connect sync directories${RESET}  ${GRAY}# List directories shared with you, with your access level${RESET}"
    echo -e "  ${GREEN}${BOLD}nedara-connect sync logout${RESET}       ${GRAY}# Disable sync and remove the stored token${RESET}"
    echo
    print_color "$DIM" "  'add'/'edit' let you assign a connection to a shared directory once you've"
    print_color "$DIM" "  pulled/listed them at least once. Pushing to a directory requires read-write"
    print_color "$DIM" "  access there; deleting a shared connection requires read-write-delete."
    echo
    print_color "$CYAN$BOLD" "EXAMPLES:"
    echo
    echo -e "  ${YELLOW}${ICON_BULLET} ${WHITE}nedara-connect add${RESET}           ${DIM}# Add a new connection${RESET}"
    echo -e "  ${YELLOW}${ICON_BULLET} ${WHITE}nedara-connect prod${RESET}          ${DIM}# Connect to 'prod' server${RESET}"
    echo -e "  ${YELLOW}${ICON_BULLET} ${WHITE}nedara-connect edit staging${RESET}  ${DIM}# Edit 'staging' connection${RESET}"
    echo -e "  ${YELLOW}${ICON_BULLET} ${WHITE}nedara-connect delete staging${RESET} ${DIM}# Delete 'staging' connection${RESET}"
    echo
    print_divider
    print_info "Configuration stored in: ${CYAN}${CONFIG_FILE}"
    print_info "Passwords stored in:     ${CYAN}${PASS_FILE} (encrypted)"
    print_info "Encryption key in:       ${CYAN}${KEY_FILE} (keep this safe!)"
    print_info "Sync config in:          ${CYAN}${SYNC_CONFIG_FILE} (only created if you use sync)"
    print_info "Sync token in:           ${CYAN}${SYNC_TOKEN_FILE} (encrypted, only created if you use sync)"
    print_info "Known directories in:    ${CYAN}${DIRECTORIES_CACHE_FILE} (only created if you use sync)"
    echo
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
# Uses -t 1 (integer) for bash 3.2 compatibility on macOS (fractional -t unsupported).
_tui_read_key() {
    local key c1 c2
    IFS= read -rsn1 key </dev/tty
    if [[ "$key" == $'\x1b' ]]; then
        IFS= read -rsn1 -t 1 c1 </dev/tty 2>/dev/null
        if [[ "$c1" == '[' || "$c1" == 'O' ]]; then
            IFS= read -rsn1 -t 1 c2 </dev/tty 2>/dev/null
            key="${key}${c1}${c2}"
        else
            key="${key}${c1}"
        fi
    fi
    printf '%s' "$key"
}

# Draw the standard header, optionally with a subtitle line.
_tui_header() {
    local sub="${1:-}"
    clear
    echo
    print_color "$CYAN$BOLD" "  ╭─────────────────────────────────────────────╮"
    print_color "$CYAN$BOLD" "  │        ${WHITE}🚀 NEDARA CONNECT v0.6.0${CYAN}             │"
    if [ -n "$sub" ]; then
        printf "${CYAN}${BOLD}  │  ${WHITE}%-43s${CYAN}│${RESET}\n" "$sub"
    fi
    print_color "$CYAN$BOLD" "  ╰─────────────────────────────────────────────╯"
    echo
    _show_update_notice
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

    local n=${#values[@]} key
    local selected=0
    # A value of "__header__" is a non-selectable section title (used to
    # group entries, e.g. "My Connections" vs. shared directories). Start
    # on the first selectable entry.
    while [ "$selected" -lt "$n" ] && [ "${values[$selected]}" = "__header__" ]; do
        selected=$((selected + 1))
    done

    while true; do
        _tui_header "$sub"
        for i in "${!values[@]}"; do
            if [ "${values[$i]}" = "__header__" ]; then
                echo -e "  ${CYAN}${BOLD}${labels[$i]}${RESET}"
            elif [ "$i" -eq "$selected" ]; then
                echo -e "  ${GREEN}${BOLD}▶  ${labels[$i]}${RESET}"
            else
                echo -e "  ${GRAY}   ${labels[$i]}${RESET}"
            fi
        done
        echo
        print_color "$DIM" "  ↑ ↓  navigate    Enter  select    q  quit"

        key=$(_tui_read_key)
        case "$key" in
            $'\x1b[A'|$'\x1bOA')
                local i=$selected
                while [ "$i" -gt 0 ]; do
                    i=$((i - 1))
                    if [ "${values[$i]}" != "__header__" ]; then selected=$i; break; fi
                done
                ;;
            $'\x1b[B'|$'\x1bOB')
                local i=$selected
                while [ "$i" -lt $((n - 1)) ]; do
                    i=$((i + 1))
                    if [ "${values[$i]}" != "__header__" ]; then selected=$i; break; fi
                done
                ;;
            ''|$'\n'|$'\r')
                [ "${values[$selected]}" = "__header__" ] && continue
                TUI_RESULT="${values[$selected]}"; return 0 ;;
            'q'|'Q'|$'\x1b'|$'\x03') TUI_RESULT=""; return 1 ;;
        esac
    done
}

# Populates the global array _MENU_ARGS with alternating value/label pairs for
# _tui_menu, grouped by location ("My Connections" first, then each shared
# directory), using "__header__" as a non-selectable section title.
_build_connection_menu_args() {
    _MENU_ARGS=()
    local group_dir_id group_label lines name username host port _dir

    for group_dir_id in "" $(cut -d: -f5 "$CONFIG_FILE" 2>/dev/null | grep -v '^$' | sort -u); do
        lines=$(_connections_in_group "$group_dir_id")
        [ -n "$lines" ] || continue
        group_label="$(_directory_label "$group_dir_id")"
        _MENU_ARGS+=("__header__" "── ${group_label} ──")
        while IFS=: read -r name username host port _dir; do
            [ -n "$name" ] || continue
            _MENU_ARGS+=("$name" "$name  ($username@$host:$port)")
        done <<< "$lines"
    done
}

# Location picker for the TUI. Sets TUI_RESULT to the chosen directory_id
# ("" = My Connections). Only shown if directories are known locally (i.e.
# sync has been used at least once) — returns 1 without prompting otherwise.
_tui_pick_location() {
    [ -s "$DIRECTORIES_CACHE_FILE" ] || return 1
    local -a args=("" "My Connections")
    local id name org role
    while IFS=: read -r id name org role; do
        [ -n "$id" ] || continue
        args+=("$id" "$name ($org)")
    done < "$DIRECTORIES_CACHE_FILE"
    _tui_menu "Choose a location" "${args[@]}"
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

    _build_connection_menu_args
    _tui_menu "Connect to a host" "${_MENU_ARGS[@]}" || return
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

    local directory_id=""
    if _tui_pick_location; then
        directory_id="$TUI_RESULT"
    fi

    echo "$name:$username:$host:$port:$directory_id" >> "$CONFIG_FILE"
    echo
    print_success "Connection '$name' added!"
    print_info "  $username@$host:$port"
    print_info "  Location: $(_directory_label "$directory_id")"
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
    local group_dir_id group_label lines name username host port _dir

    for group_dir_id in "" $(cut -d: -f5 "$CONFIG_FILE" 2>/dev/null | grep -v '^$' | sort -u); do
        lines=$(_connections_in_group "$group_dir_id")
        [ -n "$lines" ] || continue
        group_label="$(_directory_label "$group_dir_id")"
        echo -e "  ${CYAN}${BOLD}📁 ${group_label}${RESET}"
        while IFS=: read -r name username host port _dir; do
            [ -n "$name" ] || continue
            count=$((count + 1))
            local stored_pass
            stored_pass=$(get_password "$name")
            echo -e "  ${CYAN}${BOLD}${count}.${RESET} ${WHITE}${BOLD}${name}${RESET}"
            echo -e "     ${GRAY}User:${RESET} ${GREEN}${username}${RESET}  ${GRAY}Host:${RESET} ${BLUE}${host}${RESET}  ${GRAY}Port:${RESET} ${YELLOW}${port}${RESET}"
            [ -n "$stored_pass" ] && echo -e "     ${GRAY}${ICON_LOCK} Password stored securely${RESET}"
            echo
        done <<< "$lines"
    done

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

    _build_connection_menu_args
    _tui_menu "Delete a connection" "${_MENU_ARGS[@]}" || return
    local choice="$TUI_RESULT"

    _tui_header "Confirm Delete"
    echo -e "  ${RED}${BOLD}Delete '${choice}'?${RESET}"
    echo -e "  ${GRAY}This cannot be undone.${RESET}"
    echo
    _tui_yesno "Confirm deletion" || return

    local tmp
    tmp=$(mktemp)
    grep -v "^$choice:" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    local remaining
    remaining=$(decrypt_passwords | grep -v "^$choice:")
    encrypt_passwords "$remaining"

    echo
    print_success "Connection '$choice' deleted."
    echo
    print_color "$DIM" "  Press any key to continue..."
    IFS= read -rsn1 </dev/tty
}

_tui_edit() {
    if [ ! -s "$CONFIG_FILE" ]; then
        _tui_message "Edit" "No connections found."
        return
    fi

    _build_connection_menu_args
    _tui_menu "Edit a connection" "${_MENU_ARGS[@]}" || return
    local choice="$TUI_RESULT"

    local connection_details
    connection_details=$(grep "^$choice:" "$CONFIG_FILE")
    local cur_name cur_username cur_host cur_port cur_dir_id
    IFS=: read -r cur_name cur_username cur_host cur_port cur_dir_id <<< "$connection_details"

    _tui_header "Edit: $choice"
    print_color "$DIM" "  Press Enter to keep the current value."
    echo

    local username host port

    while true; do
        _tui_input "Username" "$cur_username"
        username="$TUI_RESULT"
        [ -n "$username" ] && break
        print_error "Username cannot be empty."
    done

    while true; do
        _tui_input "Hostname or IP address" "$cur_host"
        host="$TUI_RESULT"
        [ -n "$host" ] && break
        print_error "Hostname cannot be empty."
    done

    _tui_input "Port" "$cur_port"
    port="${TUI_RESULT:-$cur_port}"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        print_error "Invalid port — keeping current value $cur_port."
        port=$cur_port
    fi

    local stored_pass update_label
    stored_pass=$(get_password "$choice")
    if [ -n "$stored_pass" ]; then
        update_label="Update saved password?"
    else
        update_label="Add a password for this connection?"
    fi
    if _tui_yesno "$update_label"; then
        local password
        while true; do
            _tui_password "New password (stored encrypted)"
            password="$TUI_RESULT"
            if [ -n "$password" ]; then
                save_password "$choice" "$password"
                break
            fi
            print_error "Password cannot be empty."
        done
    fi

    local directory_id="$cur_dir_id"
    if [ -s "$DIRECTORIES_CACHE_FILE" ] && _tui_yesno "Move to a different location? (currently: $(_directory_label "$cur_dir_id"))"; then
        if _tui_pick_location; then
            directory_id="$TUI_RESULT"
        fi
    fi

    local tmp
    tmp=$(mktemp)
    grep -v "^$choice:" "$CONFIG_FILE" > "$tmp"
    echo "$choice:$username:$host:$port:$directory_id" >> "$tmp"
    mv "$tmp" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"

    echo
    print_success "Connection '$choice' updated!"
    print_info "  $username@$host:$port"
    print_info "  Location: $(_directory_label "$directory_id")"
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
            "edit"    "Edit a connection" \
            "delete"  "Delete a connection" || break

        case "$TUI_RESULT" in
            connect) _tui_connect ;;
            add)     _tui_add ;;
            list)    _tui_list ;;
            edit)    _tui_edit ;;
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
    "edit")
        edit_connection "$2"
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
    "sync")
        sync_dispatch "$2" "$3"
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
