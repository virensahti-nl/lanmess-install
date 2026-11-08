if ! command -v python3 &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y python3 python3-pip python3-full
elif ! command -v pip3 &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y python3-pip
fi

python3 -m pip install --upgrade pip --user
python3 -m pip install lanmess --user

PYTHON_BIN_PATH="$HOME/.local/bin"
if ! echo "$PATH" | grep -q "$PYTHON_BIN_PATH"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    if [ -f ~/.zshrc ]; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
    fi
    export PATH="$HOME/.local/bin:$PATH"
fi

read -p "Do you want to create a desktop shortcut for lanmess? (y/n): " choice
if [ "$choice" = "y" ] || [ "$choice" = "Y" ]; then
    DESKTOP_DIR="$HOME/Desktop"
    [ -d "$DESKTOP_DIR" ] || DESKTOP_DIR="$HOME"
    cat << EOF > "$DESKTOP_DIR/lanmess.desktop"
[Desktop Entry]
Type=Application
Name=lanmess
Exec=$HOME/.local/bin/lanmess
Terminal=true
Categories=Network;
EOF
    chmod +x "$DESKTOP_DIR/lanmess.desktop"
fi
