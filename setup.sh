#!/usr/bin/env bash

# Repo info
REPO="CTXP/FedoraScripts"
BRANCH="main"

# Fetch files from GitHub API
echo "🔍 Fetching available scripts from GitHub..."
FILES=$(curl -s "https://api.github.com/repos/${REPO}/contents/?ref=${BRANCH}" \
        | jq -r '.[] | select(.type=="file") | .name')

if [ -z "$FILES" ]; then
    echo "⚠️ No scripts found in the repo!"
    exit 1
fi

# Let user select a script
echo "📄 Available scripts:"
select SCRIPT in $FILES; do
    if [ -n "$SCRIPT" ]; then
        echo "✅ You selected: $SCRIPT"
        break
    else
        echo "⚠️ Invalid selection. Try again."
    fi
done

# Get the download URL
DOWNLOAD_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/${SCRIPT}"

# Confirm
echo "💻 Downloading and running $SCRIPT from $DOWNLOAD_URL ..."
curl -sL "$DOWNLOAD_URL" | bash
