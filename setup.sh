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

# Display menu using select
echo "📄 Available scripts:"
select SCRIPT in "${FILES[@]}"; do
    if [[ -n "$SCRIPT" ]]; then
        echo "✅ You selected: $SCRIPT"
        break
    else
        echo "⚠️ Invalid selection. Try again."
    fi
done

# Construct download URL
DOWNLOAD_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/${SCRIPT}"

echo "💻 Downloading and running $SCRIPT ..."
curl -sL "$DOWNLOAD_URL" | bash
