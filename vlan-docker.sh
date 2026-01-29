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

# ===== Global Variables =====
PARENT_INTERFACE=""
VLAN_ID=""
VLAN_INTERFACE=""
CONNECTION_NAME=""
SUBNET=""
GATEWAY=""
NETWORK_NAME=""
IP_RANGE=""

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

    if ! command -v nmcli &> /dev/null; then
        missing_deps+=("NetworkManager")
    fi

    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    fi

    if ! command -v ip &> /dev/null; then
        missing_deps+=("iproute2")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        exit 1
    fi
}

# ===== Check Sudo =====
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        print_info "This script requires sudo privileges"
        sudo -v || {
            print_error "Failed to obtain sudo privileges"
            exit 1
        }
    fi
}

# ===== Input Validation Functions =====
validate_interface() {
    local interface="$1"
    
    if [ -z "$interface" ]; then
        print_error "Interface name cannot be empty"
        return 1
    fi
    
    if ! ip link show "$interface" &> /dev/null; then
        print_error "Interface '$interface' does not exist"
        return 1
    fi
    
    return 0
}

validate_vlan_id() {
    local vlan="$1"
    
    if [ -z "$vlan" ]; then
        print_error "VLAN ID cannot be empty"
        return 1
    fi
    
    if ! [[ "$vlan" =~ ^[0-9]+$ ]] || [ "$vlan" -lt 1 ] || [ "$vlan" -gt 4094 ]; then
        print_error "VLAN ID must be a number between 1 and 4094"
        return 1
    fi
    
    return 0
}

validate_subnet() {
    local subnet="$1"
    
    if [ -z "$subnet" ]; then
        print_error "Subnet cannot be empty"
        return 1
    fi
    
    if ! [[ "$subnet" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        print_error "Invalid subnet format. Use CIDR notation: e.g., 10.32.11.0/24"
        return 1
    fi
    
    return 0
}

validate_ip() {
    local ip="$1"
    
    if [ -z "$ip" ]; then
        print_error "IP address cannot be empty"
        return 1
    fi
    
    if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        print_error "Invalid IP format. Use format: e.g., 10.32.11.1"
        return 1
    fi
    
    return 0
}

validate_network_name() {
    local name="$1"
    
    if [ -z "$name" ]; then
        print_error "Network name cannot be empty"
        return 1
    fi
    
    if ! [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        print_error "Network name can only contain letters, numbers, hyphens, and underscores"
        return 1
    fi
    
    return 0
}

# ===== Configuration Steps =====
step_parent_interface() {
    print_header "Step 1: Network Interface"
    print_info "Available network interfaces:"
    ip -br link show | grep -v "lo" | awk '{print "  - " $1}' | sed 's/@.*//'
    echo ""
    
    while true; do
        read -rp "$(echo -e "${CYAN}${BOLD}Enter parent interface name ${NC}[e.g., eno1, eth0]: ")" PARENT_INTERFACE < /dev/tty
        
        if validate_interface "$PARENT_INTERFACE"; then
            print_success "Using parent interface: $PARENT_INTERFACE"
            break
        fi
    done
}

step_vlan_config() {
    print_header "Step 2: VLAN Configuration"
    
    while true; do
        read -rp "$(echo -e "${CYAN}${BOLD}Enter VLAN ID ${NC}[e.g., 11, 20, 100]: ")" VLAN_ID < /dev/tty
        
        if validate_vlan_id "$VLAN_ID"; then
            VLAN_INTERFACE="${PARENT_INTERFACE}.${VLAN_ID}"
            CONNECTION_NAME="vlan${VLAN_ID}"
            print_success "VLAN interface will be: $VLAN_INTERFACE"
            break
        fi
    done
}

step_subnet_config() {
    print_header "Step 3: Network Subnet"
    
    while true; do
        read -rp "$(echo -e "${CYAN}${BOLD}Enter subnet ${NC}[e.g., 10.32.11.0/24]: ")" SUBNET < /dev/tty
        
        if validate_subnet "$SUBNET"; then
            print_success "Using subnet: $SUBNET"
            break
        fi
    done
}

step_gateway_config() {
    print_header "Step 4: Gateway Configuration"
    
    while true; do
        read -rp "$(echo -e "${CYAN}${BOLD}Enter gateway IP ${NC}[e.g., 10.32.11.1]: ")" GATEWAY < /dev/tty
        
        if validate_ip "$GATEWAY"; then
            print_success "Using gateway: $GATEWAY"
            break
        fi
    done
}

step_network_name() {
    print_header "Step 5: Docker Network Name"
    
    while true; do
        read -rp "$(echo -e "${CYAN}${BOLD}Enter Docker network name ${NC}[e.g., service-vlan]: ")" NETWORK_NAME < /dev/tty
        
        if validate_network_name "$NETWORK_NAME"; then
            print_success "Docker network name: $NETWORK_NAME"
            break
        fi
    done
}

step_ip_range() {
    print_header "Step 6: IP Range (Optional)"
    print_info "You can limit Docker to a specific IP range within the subnet"
    print_info "This helps avoid IP conflicts with other devices on the VLAN"
    read -rp "$(echo -e "${CYAN}${BOLD}Enter IP range ${NC}[leave empty to use full subnet]: ")" IP_RANGE < /dev/tty
    
    if [ -n "$IP_RANGE" ]; then
        if validate_subnet "$IP_RANGE"; then
            print_success "Using IP range: $IP_RANGE"
        else
            print_warning "Invalid IP range format, will use full subnet"
            IP_RANGE=""
        fi
    fi
}

# ===== Display Summary =====
display_summary() {
    print_header "Configuration Summary"
    echo -e "${BOLD}Parent Interface:${NC} $PARENT_INTERFACE"
    echo -e "${BOLD}VLAN ID:${NC} $VLAN_ID"
    echo -e "${BOLD}VLAN Interface:${NC} $VLAN_INTERFACE"
    echo -e "${BOLD}Connection Name:${NC} $CONNECTION_NAME"
    echo -e "${BOLD}Subnet:${NC} $SUBNET"
    echo -e "${BOLD}Gateway:${NC} $GATEWAY"
    if [ -n "$IP_RANGE" ]; then
        echo -e "${BOLD}IP Range:${NC} $IP_RANGE"
    else
        echo -e "${BOLD}IP Range:${NC} (full subnet)"
    fi
    echo -e "${BOLD}Docker Network:${NC} $NETWORK_NAME"
    echo ""
}

# ===== Confirm Configuration =====
confirm_configuration() {
    read -rp "$(echo -e "${YELLOW}${BOLD}Do you want to proceed with this configuration? (y/N): ${NC}")" confirm < /dev/tty
    confirm=${confirm:-N}
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_warning "Setup cancelled by user"
        exit 0
    fi
}

# ===== VLAN Setup =====
setup_vlan_connection() {
    print_header "Creating VLAN Configuration"
    
    # Check if VLAN interface already exists (might be created by other means)
    if ip link show "$VLAN_INTERFACE" &> /dev/null; then
        print_info "VLAN interface '$VLAN_INTERFACE' already exists"
        
        # Check if it's managed by NetworkManager
        if nmcli connection show "$CONNECTION_NAME" &> /dev/null; then
            print_info "VLAN is managed by NetworkManager connection '$CONNECTION_NAME'"
            read -rp "$(echo -e "${YELLOW}${BOLD}Do you want to delete and recreate the connection? (y/N): ${NC}")" delete_vlan < /dev/tty
            delete_vlan=${delete_vlan:-N}
            
            if [[ "$delete_vlan" =~ ^[Yy]$ ]]; then
                print_info "Deleting existing VLAN connection..."
                nmcli connection delete "$CONNECTION_NAME" &> /dev/null || true
            else
                print_info "Using existing VLAN connection"
                return 0
            fi
        else
            print_warning "VLAN interface exists but is not managed by NetworkManager"
            print_info "Will create NetworkManager connection to manage it"
        fi
    fi
    
    # Check if connection exists without interface
    if nmcli connection show "$CONNECTION_NAME" &> /dev/null; then
        print_warning "VLAN connection '$CONNECTION_NAME' already exists"
        read -rp "$(echo -e "${YELLOW}${BOLD}Do you want to delete and recreate it? (y/N): ${NC}")" delete_vlan < /dev/tty
        delete_vlan=${delete_vlan:-N}
        
        if [[ "$delete_vlan" =~ ^[Yy]$ ]]; then
            print_info "Deleting existing VLAN connection..."
            if nmcli connection delete "$CONNECTION_NAME" &> /dev/null; then
                print_success "Deleted existing VLAN connection"
            else
                print_error "Failed to delete VLAN connection"
                return 1
            fi
        else
            print_info "Using existing VLAN connection"
            return 0
        fi
    fi
    
    # Create VLAN connection with NO IP (ipv4.method disabled)
    # This matches the working configuration on gateway host
    print_info "Creating VLAN connection '$CONNECTION_NAME'..."
    if nmcli connection add \
        type vlan \
        con-name "$CONNECTION_NAME" \
        ifname "$VLAN_INTERFACE" \
        dev "$PARENT_INTERFACE" \
        id "$VLAN_ID" \
        ipv4.method disabled \
        ipv6.method disabled \
        connection.autoconnect yes; then
        print_success "VLAN connection created successfully"
    else
        print_error "Failed to create VLAN connection"
        return 1
    fi
    
    return 0
}

# ===== Activate VLAN =====
activate_vlan() {
    print_info "Activating VLAN connection..."
    
    # Try to bring up the connection
    if nmcli connection up "$CONNECTION_NAME" 2>/dev/null; then
        print_success "VLAN connection activated"
    else
        print_warning "Could not activate via nmcli, checking interface directly..."
    fi
    
    # Wait a moment for interface to come up
    sleep 2
    
    # Verify interface is UP
    print_info "Verifying VLAN interface status..."
    
    local retries=5
    local count=0
    
    while [ $count -lt $retries ]; do
        if ip link show "$VLAN_INTERFACE" &> /dev/null; then
            local state
            state=$(ip -br link show "$VLAN_INTERFACE" | awk '{print $2}')
            
            if [ "$state" = "UP" ]; then
                print_success "VLAN interface '$VLAN_INTERFACE' is UP"
                return 0
            fi
        fi
        
        sleep 1
        count=$((count + 1))
    done
    
    # Last resort: try to bring interface up manually
    print_warning "VLAN interface not UP, attempting manual activation..."
    
    if sudo ip link set "$VLAN_INTERFACE" up 2>/dev/null; then
        sleep 1
        if ip link show "$VLAN_INTERFACE" | grep -q "state UP"; then
            print_success "VLAN interface brought UP manually"
            return 0
        fi
    fi
    
    print_error "Failed to bring VLAN interface UP"
    print_info "Debug info:"
    ip link show "$VLAN_INTERFACE" 2>/dev/null || echo "  Interface does not exist"
    nmcli connection show "$CONNECTION_NAME" 2>/dev/null | grep -E "connection\.|GENERAL\." || true
    
    return 1
}

# ===== Docker Network Setup =====
setup_docker_network() {
    print_header "Creating Docker Network"
    
    print_info "Checking for existing Docker network..."
    
    if sudo docker network inspect "$NETWORK_NAME" &> /dev/null; then
        print_warning "Docker network '$NETWORK_NAME' already exists"
        
        # Show current configuration
        print_info "Current network configuration:"
        sudo docker network inspect "$NETWORK_NAME" --format '  Parent: {{index .Options "parent"}}
  Subnet: {{range .IPAM.Config}}{{.Subnet}}{{end}}
  Gateway: {{range .IPAM.Config}}{{.Gateway}}{{end}}'
        echo ""
        
        read -rp "$(echo -e "${YELLOW}${BOLD}Do you want to delete and recreate it? (y/N): ${NC}")" delete_network < /dev/tty
        delete_network=${delete_network:-N}
        
        if [[ "$delete_network" =~ ^[Yy]$ ]]; then
            print_info "Deleting existing Docker network..."
            if sudo docker network rm "$NETWORK_NAME" &> /dev/null; then
                print_success "Deleted existing Docker network"
            else
                print_error "Failed to delete Docker network"
                print_warning "Containers might be using it. Stop them first with:"
                echo "  docker network inspect $NETWORK_NAME --format '{{range .Containers}}{{.Name}} {{end}}'"
                return 1
            fi
        else
            print_success "Using existing Docker network"
            return 0
        fi
    fi
    
    # Build and execute Docker network create command
    print_info "Creating Docker macvlan network '$NETWORK_NAME'..."
    print_info "  Parent interface: $VLAN_INTERFACE"
    print_info "  Subnet: $SUBNET"
    print_info "  Gateway: $GATEWAY"
    if [ -n "$IP_RANGE" ]; then
        print_info "  IP Range: $IP_RANGE"
    fi
    
    local cmd="sudo docker network create -d macvlan"
    cmd="$cmd --subnet=$SUBNET"
    cmd="$cmd --gateway=$GATEWAY"
    
    if [ -n "$IP_RANGE" ]; then
        cmd="$cmd --ip-range=$IP_RANGE"
    fi
    
    cmd="$cmd -o parent=$VLAN_INTERFACE"
    cmd="$cmd $NETWORK_NAME"
    
    if eval "$cmd"; then
        print_success "Docker network created successfully"
        return 0
    else
        print_error "Failed to create Docker network"
        return 1
    fi
}

# ===== Test Network =====
test_network() {
    print_header "Testing Network Configuration"
    
    print_info "Running a test container to verify network connectivity..."
    
    local test_container="macvlan-test-$$"
    
    # Run a test container
    if sudo docker run -d --rm \
        --name "$test_container" \
        --network "$NETWORK_NAME" \
        alpine:latest sleep 30 &> /dev/null; then
        
        print_success "Test container started"
        
        # Get container IP
        local container_ip
        container_ip=$(sudo docker inspect "$test_container" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
        print_info "Container IP: $container_ip"
        
        # Test gateway connectivity from container
        print_info "Testing connectivity to gateway ($GATEWAY)..."
        if sudo docker exec "$test_container" ping -c 2 -W 2 "$GATEWAY" &> /dev/null; then
            print_success "Container can reach gateway!"
        else
            print_warning "Container cannot reach gateway"
            print_info "This might be expected if gateway doesn't respond to ping"
        fi
        
        # Clean up test container
        sudo docker stop "$test_container" &> /dev/null || true
        print_success "Test container cleaned up"
    else
        print_warning "Could not start test container, but network may still work"
    fi
}

# ===== Display Usage Information =====
display_usage_info() {
    print_header "Setup Complete!"
    
    echo -e "${GREEN}${BOLD}✓ VLAN interface '$VLAN_INTERFACE' is configured and UP${NC}"
    echo -e "${GREEN}${BOLD}✓ Docker network '$NETWORK_NAME' is ready${NC}"
    echo ""
    
    echo -e "${CYAN}${BOLD}Verify Configuration:${NC}"
    echo -e "  ${YELLOW}VLAN connection:${NC} nmcli connection show $CONNECTION_NAME"
    echo -e "  ${YELLOW}VLAN interface:${NC}  ip link show $VLAN_INTERFACE"
    echo -e "  ${YELLOW}Docker network:${NC}  docker network inspect $NETWORK_NAME"
    echo ""
    
    echo -e "${CYAN}${BOLD}Using the Network:${NC}"
    echo ""
    echo -e "${BOLD}1. Run container with automatic IP:${NC}"
    echo -e "   ${YELLOW}docker run --network $NETWORK_NAME <image>${NC}"
    echo ""
    echo -e "${BOLD}2. Run container with specific IP:${NC}"
    echo -e "   ${YELLOW}docker run --network $NETWORK_NAME --ip 10.32.11.10 <image>${NC}"
    echo ""
    echo -e "${BOLD}3. Docker Compose example:${NC}"
    cat << EOF
${YELLOW}   services:
     myapp:
       image: nginx
       networks:
         $NETWORK_NAME:
           ipv4_address: 10.32.11.10

   networks:
     $NETWORK_NAME:
       external: true${NC}
EOF
    echo ""
    
    echo -e "${CYAN}${BOLD}Important Notes:${NC}"
    echo -e "  • Containers will get IPs on the $SUBNET network"
    echo -e "  • Containers can communicate with other devices on VLAN $VLAN_ID"
    echo -e "  • The host CANNOT directly communicate with containers (this is normal for macvlan)"
    echo -e "  • To test from host, use another device on the same VLAN"
    echo ""
    
    print_success "All done!"
}

# ===== Main =====
main() {
    clear
    print_header "Docker Macvlan VLAN Network Setup"
    
    echo -e "${BOLD}This script will create a Docker macvlan network attached to a VLAN.${NC}"
    echo -e "${BOLD}Containers will get IPs directly on the VLAN subnet.${NC}"
    echo ""
    
    check_dependencies
    check_sudo
    
    # Gather configuration
    step_parent_interface
    step_vlan_config
    step_subnet_config
    step_gateway_config
    step_network_name
    step_ip_range
    
    # Display and confirm
    display_summary
    confirm_configuration
    
    # Execute setup
    if ! setup_vlan_connection; then
        print_error "Failed to set up VLAN connection"
        exit 1
    fi
    
    if ! activate_vlan; then
        print_error "Failed to activate VLAN"
        exit 1
    fi
    
    if ! setup_docker_network; then
        print_error "Failed to create Docker network"
        exit 1
    fi
    
    # Optional: test the network
    echo ""
    read -rp "$(echo -e "${YELLOW}${BOLD}Would you like to run a quick connectivity test? (Y/n): ${NC}")" do_test < /dev/tty
    do_test=${do_test:-Y}
    
    if [[ "$do_test" =~ ^[Yy]$ ]]; then
        test_network
    fi
    
    # Show usage information
    display_usage_info
}

# Run main function
main
