#!/bin/bash

INSTALL_PATH="$HOME/.local/bin"
SCRIPT_NAME="nedara-connect"
SCRIPT_FILE="$INSTALL_PATH/$SCRIPT_NAME"

mkdir -p "$INSTALL_PATH"

curl -s https://raw.githubusercontent.com/Nedara-Project/nedara-connect/main/nedara-connect.sh -o "$SCRIPT_FILE"
chmod +x "$SCRIPT_FILE"

# Add to shell config
ALIAS_CMD="alias nedara-connect=\"$SCRIPT_FILE\""

for file in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$file" ] && ! grep -Fxq "$ALIAS_CMD" "$file"; then
        echo "$ALIAS_CMD" >> "$file"
        echo "Added alias to $file"
    fi
done

echo "Installation complete. Restart your terminal (or you can run 'source ~/.bashrc' or 'source ~/.zshrc' or [...] to activate)."
