#!/usr/bin/env bash

set -o pipefail

# ===== Colors =====
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
MAGENTA="\e[35m"
BOLD="\e[1m"
RESET="\e[0m"

# ===== Improved run_cmd: prompts user on failure =====
run_cmd() {
    echo -e "\n${CYAN}${BOLD}🚀 Running:${RESET} ${BLUE}$*${RESET}"

    # Capture stdout + stderr
    OUTPUT=$("$@" 2>&1)
    STATUS=$?

    # Show output
    echo "$OUTPUT"

    if [ $STATUS -ne 0 ]; then
        echo -e "\n${RED}${BOLD}💥 ERROR:${RESET} ${RED}Command failed (exit code $STATUS)${RESET}"
        echo -e "${YELLOW}👉 Command:${RESET} $*"

        read -rp "$(echo -e "${BOLD}❓ Continue anyway? (y/N): ${RESET}")" choice
        case "$choice" in
            y|Y)
                echo -e "${YELLOW}⚠️  Continuing despite error...${RESET}"
                ;;
            *)
                echo -e "${RED}${BOLD}🛑 Script terminated by user.${RESET}"
                exit 1
                ;;
        esac
    else
        echo -e "${GREEN}✅ Success${RESET}"
    fi
}

header() {
    echo -e "\n${BOLD}${MAGENTA}══════════════════════════════════════${RESET}"
    echo -e "${BOLD}${MAGENTA}🧭  $1${RESET}"
    echo -e "${BOLD}${MAGENTA}══════════════════════════════════════${RESET}"
}

# ===== Start =====
header "Docker Installation Script (Fedora)"

echo -e "${CYAN}🐳 Preparing Docker environment...${RESET}"

run_cmd sudo dnf install -y dnf-plugins-core

run_cmd sudo dnf config-manager addrepo \
  --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo

run_cmd sudo dnf makecache

run_cmd sudo dnf install -y \
  docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

run_cmd sudo systemctl enable --now docker
run_cmd sudo docker info

# ===== Portainer choice =====
header "Portainer Installation (Optional)"

echo -e "${BOLD}📦 Choose Portainer option:${RESET}"
echo -e "  ${GREEN}1) None${RESET} (default)"
echo -e "  ${BLUE}2) Portainer Server (UI)${RESET}"
echo -e "  ${CYAN}3) Portainer Agent${RESET}"

read -rp "👉 Selection [1]: " PORTAINER_CHOICE
PORTAINER_CHOICE=${PORTAINER_CHOICE:-1}

PORTAINER_VERSION="latest"
if [[ "$PORTAINER_CHOICE" == "2" || "$PORTAINER_CHOICE" == "3" ]]; then
    read -rp "🏷️  Portainer version (default: latest): " VERSION_INPUT
    PORTAINER_VERSION=${VERSION_INPUT:-latest}
fi

# ===== Portainer install =====
case "$PORTAINER_CHOICE" in
    1)
        echo -e "${YELLOW}ℹ️  Skipping Portainer installation.${RESET}"
        ;;
    2)
        header "Installing Portainer Server 🖥️ (${PORTAINER_VERSION})"

        run_cmd sudo docker volume create portainer_data

        run_cmd sudo docker run -d \
          --name portainer \
          --restart=always \
          -p 8000:8000 \
          -p 9443:9443 \
          -v /var/run/docker.sock:/var/run/docker.sock \
          -v portainer_data:/data \
          portainer/portainer-ce:${PORTAINER_VERSION}
        ;;
    3)
        header "Installing Portainer Agent 🤖 (${PORTAINER_VERSION})"

        run_cmd sudo docker run -d \
          --name portainer_agent \
          --restart=always \
          -p 9001:9001 \
          -v /var/run/docker.sock:/var/run/docker.sock \
          -v /var/lib/docker/volumes:/var/lib/docker/volumes \
          portainer/agent:${PORTAINER_VERSION}
        ;;
    *)
        echo -e "${RED}❌ Invalid selection. Skipping Portainer.${RESET}"
        ;;
esac

echo -e "\n${GREEN}${BOLD}🎉 All done! Script completed successfully.${RESET}"
echo -e "${CYAN}🐳 Docker is installed and ready to use.${RESET}"
