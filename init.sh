#!/bin/bash

# Copy script to /usr/local/bin
sudo cp nmap_functions.sh /usr/local/bin/nmap_functions.sh

# Ask for confirmation to add to .zshrc
source_line="source /usr/local/bin/nmap_functions.sh"
echo
read -p "Add automatically to ~/.zshrc? (Y/n): " -n 1 -r
echo

if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "[!] No automatic addition to ~/.zshrc"
    echo "[*] To use the functions, manually add this line to your shell RC file:"
    echo "    $source_line"
    echo "[*] Or run directly: $source_line"
else
    # Check if the source line doesn't already exist in .zshrc
    if ! grep -Fxq "$source_line" ~/.zshrc 2>/dev/null; then
        echo "$source_line" >> ~/.zshrc
        echo "[+] Line added to ~/.zshrc"
        echo "[+] Installation complete. Restart your terminal or run: source ~/.zshrc"
    else
        echo "[!] Line already exists in ~/.zshrc - no modification"
        echo "[+] Installation complete. Functions are already available."
    fi
fi
