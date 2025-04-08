#!/bin/bash

CONFIG_FILE="$HOME/.ssh/connections.conf"
CONFIG_DIR="$HOME/.ssh"

# Make sure config directory exists
mkdir -p "$CONFIG_DIR"

# Create config file if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    touch "$CONFIG_FILE"
fi

add_connection() {
    echo "Adding new SSH connection"
    echo "Enter connection name (e.g., staging):"
    read -r name
    echo "Enter username:"
    read -r username
    echo "Enter hostname or IP:"
    read -r host
    echo "Enter port (press enter for default 22):"
    read -r port
    port=${port:-22}

    echo "$name:$username:$host:$port" >> "$CONFIG_FILE"
    echo "Connection '$name' added successfully!"
}

list_connections() {
    if [ ! -s "$CONFIG_FILE" ]; then
        echo "No connections found. Use 'nedara-connect add' to add a connection."
        exit 1
    fi
    echo "Available connections:"
    while IFS=: read -r name username host port; do
        echo "  - $name (${username}@${host}:${port})"
    done < "$CONFIG_FILE"
}

connect() {
    local search=$1
    if [ -z "$search" ]; then
        echo "Please specify a connection name"
        list_connections
        exit 1
    fi

    # Use grep to find the connection details in the config file
    connection_details=$(grep "^$search:" "$CONFIG_FILE")

    if [ -z "$connection_details" ]; then
        echo "Connection '$search' not found"
        list_connections
        exit 1
    fi

    # Extract the connection details
    IFS=: read -r name username host port <<< "$connection_details"

    echo "Connecting to $name ($username@$host:$port)..."
    # Use ssh with -tt to force pseudo-terminal allocation
    ssh -tt -p "$port" "$username@$host"
}

case "$1" in
    "add")
        add_connection
        ;;
    "list")
        list_connections
        ;;
    "help")
        echo "Usage:"
        echo "  nedara-connect add          # Add a new connection"
        echo "  nedara-connect list         # List all connections"
        echo "  nedara-connect <name>       # Connect to a saved connection"
        echo "  nedara-connect help         # Show this help message"
        ;;
    "")
        echo "Please specify a command. Use 'nedara-connect help' for usage information."
        exit 1
        ;;
    *)
        connect "$1"
        ;;
esac
