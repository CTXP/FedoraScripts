#!/usr/bin/env bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to print colored messages
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

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

# Check if nmcli is available
if ! command -v nmcli &> /dev/null; then
    print_error "nmcli (NetworkManager) is not installed"
    exit 1
fi

# Check if docker is available
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed"
    exit 1
fi

# Welcome message
clear
print_header "Docker Macvlan Network Setup"
echo -e "${BOLD}This script will help you create a Docker macvlan network${NC}\n"

# Step 1: Get parent interface
print_header "Step 1: Network Interface"
print_info "Available network interfaces:"
ip -br link show | grep -v "lo" | awk '{print "  - " $1}' | sed 's/@.*//'

read -rp "$(echo -e ${CYAN}Enter parent interface name ${NC}${BOLD}[e.g., eno1, eth0]${NC}: )" PARENT_INTERFACE < /dev/tty

if [ -z "$PARENT_INTERFACE" ]; then
    print_error "Parent interface cannot be empty"
    exit 1
fi

if ! ip link show "$PARENT_INTERFACE" &> /dev/null; then
    print_error "Interface '$PARENT_INTERFACE' does not exist"
    exit 1
fi

print_success "Using parent interface: $PARENT_INTERFACE"

# Step 2: Get VLAN ID
print_header "Step 2: VLAN Configuration"
read -rp "$(echo -e ${CYAN}Enter VLAN ID ${NC}${BOLD}[e.g., 11, 20, 100]${NC}: )" VLAN_ID < /dev/tty

if [ -z "$VLAN_ID" ]; then
    print_error "VLAN ID cannot be empty"
    exit 1
fi

if ! [[ "$VLAN_ID" =~ ^[0-9]+$ ]] || [ "$VLAN_ID" -lt 1 ] || [ "$VLAN_ID" -gt 4094 ]; then
    print_error "VLAN ID must be a number between 1 and 4094"
    exit 1
fi

VLAN_INTERFACE="${PARENT_INTERFACE}.${VLAN_ID}"
CONNECTION_NAME="vlan${VLAN_ID}"
print_success "VLAN interface will be: $VLAN_INTERFACE"

# Step 3: Get subnet
print_header "Step 3: Network Subnet"
read -rp "$(echo -e ${CYAN}Enter subnet ${NC}${BOLD}[e.g., 10.32.11.0/24]${NC}: )" SUBNET < /dev/tty

if [ -z "$SUBNET" ]; then
    print_error "Subnet cannot be empty"
    exit 1
fi

if ! [[ "$SUBNET" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    print_error "Invalid subnet format. Use format: 10.32.11.0/24"
    exit 1
fi

print_success "Using subnet: $SUBNET"

# Step 4: Get gateway
print_header "Step 4: Gateway Configuration"
read -rp "$(echo -e ${CYAN}Enter gateway IP ${NC}${BOLD}[e.g., 10.32.11.1]${NC}: )" GATEWAY < /dev/tty

if [ -z "$GATEWAY" ]; then
    print_error "Gateway cannot be empty"
    exit 1
fi

if ! [[ "$GATEWAY" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    print_error "Invalid gateway format. Use format: 10.32.11.1"
    exit 1
fi

print_success "Using gateway: $GATEWAY"

# Step 5: Get Docker network name
print_header "Step 5: Docker Network Name"
read -rp "$(echo -e ${CYAN}Enter Docker network name ${NC}${BOLD}[e.g., service-vlan]${NC}: )" NETWORK_NAME < /dev/tty

if [ -z "$NETWORK_NAME" ]; then
    print_error "Network name cannot be empty"
    exit 1
fi

print_success "Docker network name: $NETWORK_NAME"

# Step 6: Optional IP range
print_header "Step 6: IP Range (Optional)"
echo -e "${YELLOW}You can limit Docker to a specific IP range within the subnet${NC}"
read -rp "$(echo -e ${CYAN}Enter IP range ${NC}${BOLD}[leave empty to use full subnet]${NC}: )" IP_RANGE < /dev/tty

# Summary
print_header "Configuration Summary"
echo -e "${BOLD}Parent Interface:${NC} $PARENT_INTERFACE"
echo -e "${BOLD}VLAN ID:${NC} $VLAN_ID"
echo -e "${BOLD}VLAN Interface:${NC} $VLAN_INTERFACE"
echo -e "${BOLD}Connection Name:${NC} $CONNECTION_NAME"
echo -e "${BOLD}Subnet:${NC} $SUBNET"
echo -e "${BOLD}Gateway:${NC} $GATEWAY"
if [ -n "$IP_RANGE" ]; then
    echo -e "${BOLD}IP Range:${NC} $IP_RANGE"
fi
echo -e "${BOLD}Docker Network:${NC} $NETWORK_NAME"

echo ""
read -rp "$(echo -e ${YELLOW}Do you want to proceed with this configuration? ${NC}${BOLD}(y/N)${NC}: )" CONFIRM < /dev/tty
CONFIRM=${CONFIRM:-N}

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    print_warning "Setup cancelled by user"
    exit 0
fi

# Execute setup
print_header "Creating Configuration"

# Step 1: Check if VLAN connection already exists
print_info "Checking for existing VLAN connection..."
if nmcli connection show "$CONNECTION_NAME" &> /dev/null; then
    print_warning "VLAN connection '$CONNECTION_NAME' already exists"
    read -rp "$(echo -e ${YELLOW}Do you want to delete and recreate it? ${NC}${BOLD}(y/N)${NC}: )" DELETE_VLAN < /dev/tty
    DELETE_VLAN=${DELETE_VLAN:-N}
    
    if [[ "$DELETE_VLAN" =~ ^[Yy]$ ]]; then
        print_info "Deleting existing VLAN connection..."
        if nmcli connection delete "$CONNECTION_NAME" &> /dev/null; then
            print_success "Deleted existing VLAN connection"
        else
            print_error "Failed to delete VLAN connection"
            exit 1
        fi
    else
        print_info "Using existing VLAN connection"
    fi
fi

# Step 2: Create VLAN connection with nmcli (only if it doesn't exist)
if ! nmcli connection show "$CONNECTION_NAME" &> /dev/null; then
    print_info "Creating VLAN connection '$CONNECTION_NAME'..."
    
    if nmcli connection add \
        type vlan \
        con-name "$CONNECTION_NAME" \
        ifname "$VLAN_INTERFACE" \
        dev "$PARENT_INTERFACE" \
        id "$VLAN_ID" \
        ipv4.method disabled \
        ipv6.method disabled \
        connection.autoconnect yes &> /dev/null; then
        print_success "VLAN connection created successfully"
    else
        print_error "Failed to create VLAN connection with nmcli"
        exit 1
    fi
fi

# Step 3: Bring up the VLAN connection
print_info "Activating VLAN connection..."
if nmcli connection up "$CONNECTION_NAME" &> /dev/null; then
    print_success "VLAN connection activated"
else
    print_warning "VLAN connection already active or activation not needed"
fi

# Step 4: Verify VLAN interface is UP
print_info "Verifying VLAN interface status..."
sleep 1  # Give it a moment to come up
if ip link show "$VLAN_INTERFACE" &> /dev/null && ip link show "$VLAN_INTERFACE" | grep -q "state UP"; then
    print_success "VLAN interface is UP and ready"
else
    print_error "VLAN interface is not UP"
    print_info "Attempting to bring it up manually..."
    if nmcli device connect "$VLAN_INTERFACE" &> /dev/null; then
        print_success "VLAN interface brought UP"
    else
        print_error "Failed to bring VLAN interface UP"
        exit 1
    fi
fi

# Step 5: Check if Docker network already exists
print_info "Checking for existing Docker network..."
if docker network inspect "$NETWORK_NAME" &> /dev/null; then
    print_warning "Docker network '$NETWORK_NAME' already exists"
    read -rp "$(echo -e ${YELLOW}Do you want to delete and recreate it? ${NC}${BOLD}(y/N)${NC}: )" DELETE_NETWORK < /dev/tty
    DELETE_NETWORK=${DELETE_NETWORK:-N}
    
    if [[ "$DELETE_NETWORK" =~ ^[Yy]$ ]]; then
        print_info "Deleting existing Docker network..."
        if docker network rm "$NETWORK_NAME" &> /dev/null; then
            print_success "Deleted existing Docker network"
        else
            print_error "Failed to delete Docker network (containers might be using it)"
            exit 1
        fi
    else
        print_success "Setup complete (using existing network)"
        exit 0
    fi
fi

# Step 6: Create Docker macvlan network
print_info "Creating Docker macvlan network '$NETWORK_NAME'..."

CREATE_CMD="docker network create -d macvlan \
  --subnet=$SUBNET \
  --gateway=$GATEWAY"

if [ -n "$IP_RANGE" ]; then
    CREATE_CMD="$CREATE_CMD \
  --ip-range=$IP_RANGE"
fi

CREATE_CMD="$CREATE_CMD \
  -o parent=$VLAN_INTERFACE \
  $NETWORK_NAME"

if eval "$CREATE_CMD" &> /dev/null; then
    print_success "Docker network created successfully"
else
    print_error "Failed to create Docker network"
    docker network create -d macvlan \
      --subnet=$SUBNET \
      --gateway=$GATEWAY \
      -o parent=$VLAN_INTERFACE \
      $NETWORK_NAME
    exit 1
fi

# Final summary
print_header "Setup Complete!"
echo -e "${GREEN}${BOLD}✓ VLAN connection '$CONNECTION_NAME' is configured${NC}"
echo -e "${GREEN}${BOLD}✓ VLAN interface '$VLAN_INTERFACE' is UP${NC}"
echo -e "${GREEN}${BOLD}✓ Docker network '$NETWORK_NAME' is ready${NC}"
echo ""
echo -e "${CYAN}${BOLD}Connection Details:${NC}"
echo -e "  ${YELLOW}View connection: nmcli connection show $CONNECTION_NAME${NC}"
echo -e "  ${YELLOW}View device: nmcli device show $VLAN_INTERFACE${NC}"
echo -e "  ${YELLOW}View network: docker network inspect $NETWORK_NAME${NC}"
echo ""
echo -e "${CYAN}${BOLD}Using the network:${NC}"
echo -e "  1. Run container with automatic IP:"
echo -e "     ${YELLOW}docker run --network $NETWORK_NAME <image>${NC}"
echo ""
echo -e "  2. Run container with specific IP:"
echo -e "     ${YELLOW}docker run --network $NETWORK_NAME --ip <IP> <image>${NC}"
echo ""
echo -e "  3. In docker-compose.yml:"
echo -e "${YELLOW}     services:"
echo -e "       myapp:"
echo -e "         image: nginx"
echo -e "         networks:"
echo -e "           $NETWORK_NAME:"
echo -e "             ipv4_address: <IP>"
echo -e ""
echo -e "     networks:"
echo -e "       $NETWORK_NAME:"
echo -e "         external: true${NC}"
echo ""

print_success "All done! 🎉"