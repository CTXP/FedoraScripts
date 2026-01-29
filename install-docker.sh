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

# ===== Improved run_cmd: Prompts User on Failure =====
run_cmd() {
    echo -e "\n${CYAN}${BOLD}Running:${NC} ${BLUE}$*${NC}"

    # Capture stdout + stderr
    local output
    local status
    
    if output=$("$@" 2>&1); then
        status=0
        echo "$output"
        print_success "Command completed successfully"
    else
        status=$?
        echo "$output"
        print_error "Command failed (exit code $status)"
        echo -e "${YELLOW}Command:${NC} $*"

        read -rp "$(echo -e "${BOLD}Continue anyway? (y/N): ${NC}")" choice < /dev/tty
        case "$choice" in
            y|Y)
                print_warning "Continuing despite error..."
                ;;
            *)
                print_error "Script terminated by user"
                exit 1
                ;;
        esac
    fi
}

# ===== Check Root/Sudo =====
check_sudo() {
    if [ "$EUID" -eq 0 ]; then
        print_warning "Running as root. This is not recommended."
        read -rp "$(echo -e "${BOLD}Continue? (y/N): ${NC}")" choice < /dev/tty
        case "$choice" in
            y|Y) ;;
            *)
                print_error "Aborted by user"
                exit 1
                ;;
        esac
    fi

    if ! sudo -n true 2>/dev/null; then
        print_info "This script requires sudo privileges"
        sudo -v || {
            print_error "Failed to obtain sudo privileges"
            exit 1
        }
    fi
}

# ===== Verify Distribution =====
check_distribution() {
    if [ ! -f /etc/os-release ]; then
        print_error "Cannot determine OS distribution"
        exit 1
    fi

    source /etc/os-release
    if [[ "$ID" != "fedora" ]]; then
        print_warning "This script is designed for Fedora. Current OS: $PRETTY_NAME"
        read -rp "$(echo -e "${BOLD}Continue anyway? (y/N): ${NC}")" choice < /dev/tty
        case "$choice" in
            y|Y)
                print_warning "Proceeding on unsupported distribution..."
                ;;
            *)
                print_error "Aborted by user"
                exit 1
                ;;
        esac
    else
        print_success "Detected Fedora ($VERSION_ID)"
    fi
}

# ===== Main Script =====
clear
print_header "Docker Installation Script for Fedora"

check_sudo
check_distribution

print_info "Preparing Docker environment..."

# Install DNF plugins
run_cmd sudo dnf install -y dnf-plugins-core

# Add Docker repository
run_cmd sudo dnf config-manager addrepo \
    --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo

# Update package cache
run_cmd sudo dnf makecache

# Install Docker packages
run_cmd sudo dnf install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# Enable and start Docker service
print_info "Enabling and starting Docker service..."
run_cmd sudo systemctl enable --now docker

# Verify Docker installation
print_info "Verifying Docker installation..."
run_cmd sudo docker --version
run_cmd sudo docker info

# Add current user to docker group
print_info "Configuring user permissions..."
if ! groups | grep -q docker; then
    print_warning "Adding current user to 'docker' group..."
    run_cmd sudo usermod -aG docker "$USER"
    print_warning "You need to log out and back in for group changes to take effect"
else
    print_success "User already in 'docker' group"
fi

# ===== Portainer Installation =====
print_header "Portainer Installation (Optional)"

echo -e "${BOLD}Choose Portainer option:${NC}"
echo -e "  ${GREEN}1) None${NC} (default)"
echo -e "  ${BLUE}2) Portainer Server (Web UI)${NC}"
echo -e "  ${CYAN}3) Portainer Agent${NC}"
echo ""

read -rp "Selection [1]: " portainer_choice < /dev/tty
portainer_choice=${portainer_choice:-1}

portainer_version="latest"
if [[ "$portainer_choice" == "2" || "$portainer_choice" == "3" ]]; then
    read -rp "Portainer version (default: latest): " version_input < /dev/tty
    portainer_version=${version_input:-latest}
fi

case "$portainer_choice" in
    1)
        print_warning "Skipping Portainer installation"
        ;;
    2)
        print_header "Installing Portainer Server (${portainer_version})"

        print_info "Creating Portainer data volume..."
        run_cmd sudo docker volume create portainer_data

        print_info "Starting Portainer container..."
        run_cmd sudo docker run -d \
            --name portainer \
            --restart=always \
            -p 8000:8000 \
            -p 9443:9443 \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v portainer_data:/data \
            "portainer/portainer-ce:${portainer_version}"

        print_success "Portainer Server installed"
        print_info "Access Portainer at: https://localhost:9443"
        ;;
    3)
        print_header "Installing Portainer Agent (${portainer_version})"

        print_info "Starting Portainer Agent container..."
        run_cmd sudo docker run -d \
            --name portainer_agent \
            --restart=always \
            -p 9001:9001 \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v /var/lib/docker/volumes:/var/lib/docker/volumes \
            "portainer/agent:${portainer_version}"

        print_success "Portainer Agent installed"
        print_info "Agent is listening on port 9001"
        ;;
    *)
        print_warning "Invalid selection. Skipping Portainer installation"
        ;;
esac

# ===== Completion =====
print_header "Installation Complete!"
print_success "Docker has been successfully installed and configured"
print_info "Docker version: $(sudo docker --version | awk '{print $3}' | tr -d ',')"

if ! groups | grep -q docker; then
    echo ""
    print_warning "Remember to log out and back in for docker group permissions to take effect"
    print_info "After re-login, you can run Docker commands without sudo"
fi

echo ""
print_info "Next steps:"
echo -e "  ${YELLOW}• Test Docker: ${NC}docker run hello-world"
echo -e "  ${YELLOW}• View containers: ${NC}docker ps -a"
echo -e "  ${YELLOW}• View images: ${NC}docker images"
echo -e "  ${YELLOW}• Get help: ${NC}docker --help"
echo ""

print_success "All done!"
