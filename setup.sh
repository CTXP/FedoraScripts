#!/usr/bin/env bash

set -euo pipefail

# ===== Color Definitions =====
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'  # No Color

# ===== Configuration =====
readonly REPO="CTXP/FedoraScripts"
readonly BRANCH="main"
readonly API_URL="https://api.github.com/repos/${REPO}/contents/?ref=${BRANCH}"
readonly RAW_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

# ===== Message Helpers =====
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_header() {
    echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════${NC}\n"
}

# ===== Dependency Checks =====
check_dependencies() {
    local missing_deps=()

    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi

    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        print_info "Install them with: sudo dnf install -y ${missing_deps[*]}"
        exit 1
    fi
}

# ===== Fetch Scripts from GitHub =====
fetch_scripts() {
    local response
    local http_code
    
    print_info "Fetching available scripts from GitHub..."
    
    response=$(curl -s -w "\n%{http_code}" "$API_URL")
    http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" != "200" ]; then
        print_error "Failed to fetch scripts from GitHub (HTTP $http_code)"
        print_info "Repository: ${REPO}"
        print_info "Branch: ${BRANCH}"
        exit 1
    fi
    
    # Parse JSON and filter scripts (exclude setup.sh)
    mapfile -t FILES < <(
        echo "$response" | sed '$d' | \
        jq -r '.[] | select(.type=="file" and .name!="setup.sh" and (.name | endswith(".sh"))) | .name'
    )
    
    if [ ${#FILES[@]} -eq 0 ]; then
        print_warning "No executable scripts found in repository"
        exit 1
    fi
    
    print_success "Found ${#FILES[@]} script(s)"
}

# ===== Display Menu =====
display_menu() {
    print_header "Available Scripts"
    
    for i in "${!FILES[@]}"; do
        local script_name="${FILES[$i]}"
        local script_num=$((i + 1))
        
        # Remove .sh extension for display
        local display_name="${script_name%.sh}"
        display_name="${display_name//-/ }"
        
        echo -e "${CYAN}${BOLD} $script_num ${NC} ${display_name} ${BLUE}(${script_name})${NC}"
    done
    echo ""
}

# ===== Get User Selection =====
get_selection() {
    while true; do
        read -rp "$(echo -e "${CYAN}${BOLD}Enter the number of the script to run: ${NC}")" choice < /dev/tty
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#FILES[@]}" ]; then
            SELECTED_SCRIPT="${FILES[$((choice - 1))]}"
            print_success "Selected: $SELECTED_SCRIPT"
            return 0
        else
            print_warning "Invalid selection. Please enter a number between 1 and ${#FILES[@]}"
        fi
    done
}

# ===== Confirm and Execute =====
execute_script() {
    local download_url="${RAW_URL}/${SELECTED_SCRIPT}"
    
    echo ""
    print_warning "You are about to download and execute: ${BOLD}${SELECTED_SCRIPT}${NC}"
    print_info "Source: ${download_url}"
    echo ""
    
    read -rp "$(echo -e "${YELLOW}${BOLD}Do you want to proceed? (y/N): ${NC}")" confirm < /dev/tty
    confirm=${confirm:-N}
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_warning "Aborted by user"
        exit 0
    fi
    
    print_info "Downloading script..."
    
    local script_content
    local http_code
    
    script_content=$(curl -s -w "\n%{http_code}" "$download_url")
    http_code=$(echo "$script_content" | tail -n1)
    
    if [ "$http_code" != "200" ]; then
        print_error "Failed to download script (HTTP $http_code)"
        exit 1
    fi
    
    # Remove HTTP code from content
    script_content=$(echo "$script_content" | sed '$d')
    
    print_success "Script downloaded successfully"
    print_info "Executing $SELECTED_SCRIPT..."
    echo ""
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Execute the script
    if echo "$script_content" | sudo bash; then
        echo ""
        echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        print_success "Script completed successfully"
    else
        local exit_code=$?
        echo ""
        echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        print_error "Script execution failed (exit code $exit_code)"
        exit 1
    fi
}

# ===== Main =====
main() {
    clear
    print_header "Fedora Script Launcher"
    
    check_dependencies
    fetch_scripts
    display_menu
    get_selection
    execute_script
    
    echo ""
    print_success "All done!"
}

# Run main function
main
