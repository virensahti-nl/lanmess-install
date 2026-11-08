if ! command -v python3 &> /dev/null; then
    if command -v brew &> /dev/null; then
        brew install python
    else
        exit 1
    fi
fi

python3 -m ensurepip --upgrade
python3 -m pip install --upgrade pip --user
python3 -m pip install lanmess --user

PYTHON_BIN_PATH="$HOME/Library/Python/$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')/bin"
if [ ! -d "$PYTHON_BIN_PATH" ]; then
    PYTHON_BIN_PATH="$HOME/.local/bin"
fi

if ! echo "$PATH" | grep -q "$PYTHON_BIN_PATH"; then
    echo "export PATH=\"$PYTHON_BIN_PATH:\$PATH\"" >> ~/.zshrc
    echo "export PATH=\"$PYTHON_BIN_PATH:\$PATH\"" >> ~/.bash_profile
    export PATH="$PYTHON_BIN_PATH:$PATH"
fi

read -p "Do you want to create a desktop shortcut for lanmess? (y/n): " choice
if [ "$choice" = "y" ] || [ "$choice" = "Y" ]; then
    DESKTOP_DIR="$HOME/Desktop"
    cat << EOF > "$DESKTOP_DIR/lanmess.command"
#!/bin/bash
lanmess
EOF
    chmod +x "$DESKTOP_DIR/lanmess.command"
fi
