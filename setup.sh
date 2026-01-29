#!/usr/bin/env bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Message helpers
print_info() {
    echo -e "${BLUE}${NC} $1"
}

print_success() {
    echo -e "${GREEN}${NC} $1"
}

print_error() {
    echo -e "${RED}${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}${NC} $1"
}

print_header() {
    echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════${NC}\n"
}

# Repo config
REPO="CTXP/FedoraScripts"
BRANCH="main"

clear
print_header "Fedora Script Launcher"

print_info "Fetching available scripts from GitHub..."

# Fetch file list (excluding setup.sh)
mapfile -t FILES < <(
    curl -s "https://api.github.com/repos/${REPO}/contents/?ref=${BRANCH}" |
    jq -r '.[] | select(.type=="file" and .name!="setup.sh") | .name'
)

if [ "${#FILES[@]}" -eq 0 ]; then
    print_warning "No scripts found!"
    exit 1
fi

# Display menu
print_header "Available Scripts"
for i in "${!FILES[@]}"; do
    echo -e "  %s%d)%s %s\n" "${CYAN}" $((i+1)) "${NC}" "${FILES[$i]}"
done
echo ""

# Prompt until valid selection
while true; do
    read -rp "$(echo -e ${CYAN}Enter the number of the script to run${NC}${BOLD}: ${NC}) " CHOICE < /dev/tty

    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#FILES[@]}" ]; then
        SCRIPT="${FILES[$((CHOICE-1))]}"
        print_success "Selected script: $SCRIPT"
        break
    else
        print_warning "Invalid selection. Enter a number between 1 and ${#FILES[@]}."
    fi
done

DOWNLOAD_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/${SCRIPT}"

# Confirmation
echo ""
read -rp "$(echo -e ${YELLOW}Do you want to download and execute ${BOLD}${SCRIPT}${NC}${YELLOW}? ${BOLD}(y/N)${NC}:) " CONFIRM < /dev/tty
CONFIRM=${CONFIRM:-N}

if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    print_info "Downloading and executing $SCRIPT..."
    if curl "$DOWNLOAD_URL" | sudo bash; then
        print_success "Script completed successfully"
    else
        print_error "Script execution failed"
        exit 1
    fi
else
    print_warning "Aborted by user"
    exit 0
fi