#!/bin/bash
set -e

# --- 1. Ensure Python 3 is available ---
if ! command -v python3 &> /dev/null; then
    echo "Python3 not found. Attempting to install via Homebrew..."
    if command -v brew &> /dev/null; then
        brew install python
    else
        echo "Homebrew is not installed. Please install Python 3 from https://www.python.org/downloads/ or install Homebrew (https://brew.sh)."
        exit 1
    fi
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
for rc in ~/.bashrc ~/.zshrc ~/.bash_profile; do
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

# --- 8. Optional desktop launcher ---
read -p "Create a desktop launcher for lanmess? (y/n) (yes or no): " choice
if [[ "$choice" =~ ^[yY] ]]; then
    DESKTOP_DIR="$HOME/Desktop"
    [ -d "$DESKTOP_DIR" ] || DESKTOP_DIR="$HOME"
    LAUNCHER="$DESKTOP_DIR/lanmess.command"
    cat > "$LAUNCHER" << EOF
#!/bin/bash
exec "$LANMESS_EXEC"
EOF
    chmod +x "$LAUNCHER"
    echo "Launcher created at $LAUNCHER"
fi
