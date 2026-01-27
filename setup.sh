#!/usr/bin/env bash

REPO="CTXP/FedoraScripts"
BRANCH="main"

echo "🔍 Fetching available scripts from GitHub..."

# Fetch file names into an array
mapfile -t FILES < <(curl -s "https://api.github.com/repos/${REPO}/contents/?ref=${BRANCH}" \
                | jq -r '.[] | select(.type=="file") | .name')

if [ ${#FILES[@]} -eq 0 ]; then
    echo "⚠️ No scripts found!"
    exit 1
fi

# Display menu
echo "📄 Available scripts:"
for i in "${!FILES[@]}"; do
    printf "  %d) %s\n" $((i+1)) "${FILES[$i]}"
done

# Loop until valid input - redirect from /dev/tty to read from keyboard
CHOICE=""
read -rp "👉 Enter the number of the script to run: " CHOICE < /dev/tty
    
# Validate input: must be a number within the array bounds
if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#FILES[@]}" ]; then
    SCRIPT="${FILES[$((CHOICE-1))]}"
    echo "✅ You selected: $SCRIPT"
else
    echo "⚠️ Invalid selection. Please enter a number between 1 and ${#FILES[@]}."
fi

# Construct download URL
DOWNLOAD_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/${SCRIPT}"

# Confirm and run - redirect from /dev/tty
read -rp "💻 Do you want to download and execute $SCRIPT? (y/N): " CONFIRM < /dev/tty
CONFIRM=${CONFIRM:-N}

if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "🚀 Downloading and running $SCRIPT ..."
    curl -sL "$DOWNLOAD_URL" | bash
else
    echo "🛑 Aborted by user."
    exit 0
fi