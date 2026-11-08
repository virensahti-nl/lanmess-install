#!/bin/bash
set -e

# --- 1. Install Python 3 and pip using the system package manager ---
if command -v apt-get &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip python3-full
elif command -v dnf &> /dev/null; then
    sudo dnf install -y python3 python3-pip
elif command -v pacman &> /dev/null; then
    sudo pacman -Sy --noconfirm python python-pip
else
    echo "Unsupported package manager. Please install Python 3 and pip manually."
    exit 1
fi

PYTHON=$(command -v python3)
echo "Using Python: $PYTHON"

# --- 2. Upgrade pip, setuptools, wheel ---
"$PYTHON" -m ensurepip --upgrade
"$PYTHON" -m pip install --upgrade pip setuptools wheel --user

# --- 3. Install lanmess ---
"$PYTHON" -m pip install --upgrade lanmess --user

# --- 4. Determine the user bin directory ---
USER_BASE=$("$PYTHON" -m site --user-base)
USER_BIN="$USER_BASE/bin"

# --- 5. Update PATH for the current session ---
if [[ ":$PATH:" != *":$USER_BIN:"* ]]; then
    export PATH="$USER_BIN:$PATH"
    echo "Added $USER_BIN to the current session PATH."
fi

# --- 6. Persist PATH in shell rc files (no duplicates) ---
for rc in ~/.bashrc ~/.zshrc ~/.profile; do
    if [ -f "$rc" ]; then
        if ! grep -qF "export PATH=\"$USER_BIN:\$PATH\"" "$rc"; then
            echo "export PATH=\"$USER_BIN:\$PATH\"" >> "$rc"
            echo "Updated $rc"
        fi
    fi
done

# --- 7. Locate the lanmess executable ---
LANMESS_EXEC="$USER_BIN/lanmess"
if [ ! -f "$LANMESS_EXEC" ]; then
    LANMESS_EXEC=$(command -v lanmess 2>/dev/null || echo "")
fi
if [ -z "$LANMESS_EXEC" ]; then
    echo "Error: lanmess executable not found."
    exit 1
fi
echo "lanmess executable: $LANMESS_EXEC"

# --- 8. Optional desktop entry ---
read -p "Create a desktop entry for lanmess? (y/n): " choice
if [[ "$choice" =~ ^[yY] ]]; then
    DESKTOP_DIR="$HOME/Desktop"
    [ -d "$DESKTOP_DIR" ] || DESKTOP_DIR="$HOME"
    DESKTOP_FILE="$DESKTOP_DIR/lanmess.desktop"
    cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Type=Application
Name=lanmess
Exec=$LANMESS_EXEC
Terminal=true
Categories=Network;
EOF
    chmod +x "$DESKTOP_FILE"
    # Refresh the desktop database if the tool is available
    if command -v update-desktop-database &> /dev/null; then
        update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    fi
    echo "Desktop entry created at $DESKTOP_FILE"
fi
