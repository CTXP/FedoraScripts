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
SHIM_INTERFACE=""
SHIM_PARENT=""
CREATE_SHIM="y"

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
            SHIM_INTERFACE="macvlan${VLAN_ID}-shim"
            print_success "VLAN interface will be: $VLAN_INTERFACE"
            print_success "Shim interface will be: $SHIM_INTERFACE"
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

step_shim_config() {
    print_header "Step 7: Macvlan Shim (Host-to-Container Communication)"
    
    echo -e "${YELLOW}${BOLD}What is a Macvlan Shim?${NC}"
    echo -e "By default, the host cannot communicate directly with containers on a macvlan network."
    echo -e "A shim interface allows the host to talk to containers on the macvlan network."
    echo ""
    echo -e "${CYAN}Benefits:${NC}"
    echo -e "  • Host can access services running in containers"
    echo -e "  • Required for management/monitoring from the host"
    echo -e "  • Enables local development and testing"
    echo ""
    
    read -rp "$(echo -e "${YELLOW}${BOLD}Create macvlan shim interface? (Y/n): ${NC}")" CREATE_SHIM < /dev/tty
    CREATE_SHIM=${CREATE_SHIM:-y}
    
    if [[ "$CREATE_SHIM" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${CYAN}${BOLD}Shim Parent Interface:${NC}"
        echo -e "The shim can be attached to either:"
        echo -e "  ${GREEN}1) ${VLAN_INTERFACE}${NC} - VLAN interface (recommended if using VLANs)"
        echo -e "  ${BLUE}2) ${PARENT_INTERFACE}${NC} - Physical interface (works for untagged traffic)"
        echo ""
        echo -e "${YELLOW}Note:${NC} Both options work. Choose based on your network design."
        echo ""
        
        read -rp "$(echo -e "${CYAN}${BOLD}Attach shim to which interface? (1/2) ${NC}[1]: ")" shim_choice < /dev/tty
        shim_choice=${shim_choice:-1}
        
        case "$shim_choice" in
            1)
                SHIM_PARENT="$VLAN_INTERFACE"
                print_success "Shim will be attached to: $SHIM_PARENT (VLAN interface)"
                ;;
            2)
                SHIM_PARENT="$PARENT_INTERFACE"
                print_success "Shim will be attached to: $SHIM_PARENT (physical interface)"
                ;;
            *)
                print_warning "Invalid choice, using default: $VLAN_INTERFACE"
                SHIM_PARENT="$VLAN_INTERFACE"
                ;;
        esac
    else
        print_warning "Skipping shim interface creation"
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
    fi
    echo -e "${BOLD}Docker Network:${NC} $NETWORK_NAME"
    if [[ "$CREATE_SHIM" =~ ^[Yy]$ ]]; then
        echo -e "${BOLD}Shim Interface:${NC} $SHIM_INTERFACE ${GREEN}(will be created)${NC}"
        echo -e "${BOLD}Shim Parent:${NC} $SHIM_PARENT"
    else
        echo -e "${BOLD}Shim Interface:${NC} ${YELLOW}(skipped)${NC}"
    fi
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
    
    # Check if VLAN connection exists
    print_info "Checking for existing VLAN connection..."
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
    
    # Create VLAN connection
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
        print_error "Failed to create VLAN connection"
        return 1
    fi
    
    return 0
}

# ===== Activate VLAN =====
activate_vlan() {
    print_info "Activating VLAN connection..."
    
    if nmcli connection up "$CONNECTION_NAME" &> /dev/null; then
        print_success "VLAN connection activated"
    else
        print_warning "VLAN connection may already be active"
    fi
    
    # Verify interface is UP
    print_info "Verifying VLAN interface status..."
    sleep 2  # Give it time to come up
    
    if ip link show "$VLAN_INTERFACE" &> /dev/null && \
       ip link show "$VLAN_INTERFACE" | grep -q "state UP"; then
        print_success "VLAN interface is UP and ready"
        return 0
    else
        print_warning "VLAN interface is not UP, attempting to bring it up..."
        if nmcli device connect "$VLAN_INTERFACE" &> /dev/null; then
            print_success "VLAN interface brought UP"
            return 0
        else
            print_error "Failed to bring VLAN interface UP"
            return 1
        fi
    fi
}

# ===== Create Macvlan Shim =====
create_macvlan_shim() {
    if [[ ! "$CREATE_SHIM" =~ ^[Yy]$ ]]; then
        print_info "Skipping macvlan shim creation"
        return 0
    fi
    
    print_header "Creating Macvlan Shim Interface"
    
    # Check if shim already exists
    if ip link show "$SHIM_INTERFACE" &> /dev/null; then
        print_warning "Shim interface '$SHIM_INTERFACE' already exists"
        
        # Check current parent
        local current_parent
        current_parent=$(ip -d link show "$SHIM_INTERFACE" | grep -oP 'link/ether.*' | head -n1)
        local existing_parent
        existing_parent=$(ip link show "$SHIM_INTERFACE" | grep -oP '@\K[^:]+')
        
        if [ "$existing_parent" != "$SHIM_PARENT" ]; then
            print_warning "Existing shim is attached to '$existing_parent', but you selected '$SHIM_PARENT'"
        fi
        
        read -rp "$(echo -e "${YELLOW}${BOLD}Do you want to delete and recreate it? (y/N): ${NC}")" delete_shim < /dev/tty
        delete_shim=${delete_shim:-N}
        
        if [[ "$delete_shim" =~ ^[Yy]$ ]]; then
            print_info "Deleting existing shim interface..."
            # Remove the route first
            if ip route show | grep -q "$SHIM_INTERFACE"; then
                sudo ip route del "$SUBNET" dev "$SHIM_INTERFACE" 2>/dev/null || true
            fi
            # Delete the interface
            if sudo ip link delete "$SHIM_INTERFACE" &> /dev/null; then
                print_success "Deleted existing shim interface"
            else
                print_error "Failed to delete shim interface"
                return 1
            fi
        else
            print_info "Using existing shim interface"
            # Ensure route exists
            if ! ip route show | grep -q "$SHIM_INTERFACE"; then
                print_info "Adding missing route for shim interface..."
                if sudo ip route add "$SUBNET" dev "$SHIM_INTERFACE"; then
                    print_success "Route added"
                else
                    print_warning "Failed to add route (may already exist)"
                fi
            fi
            return 0
        fi
    fi
    
    # Wait for parent interface to be ready if it's the VLAN interface
    if [ "$SHIM_PARENT" = "$VLAN_INTERFACE" ]; then
        print_info "Waiting for VLAN interface to be ready..."
        local count=0
        local max_wait=10
        while [ $count -lt $max_wait ]; do
            if ip link show "$VLAN_INTERFACE" &> /dev/null && \
               ip link show "$VLAN_INTERFACE" | grep -q "state UP"; then
                break
            fi
            sleep 1
            count=$((count + 1))
        done
        
        if [ $count -eq $max_wait ]; then
            print_warning "VLAN interface may not be fully ready, but continuing..."
        fi
    fi
    
    # Create macvlan shim interface
    print_info "Creating macvlan shim interface '$SHIM_INTERFACE' on '$SHIM_PARENT'..."
    if sudo ip link add "$SHIM_INTERFACE" link "$SHIM_PARENT" type macvlan mode bridge; then
        print_success "Shim interface created"
    else
        print_error "Failed to create shim interface"
        return 1
    fi
    
    # Bring the interface up
    print_info "Bringing shim interface UP..."
    if sudo ip link set "$SHIM_INTERFACE" up; then
        print_success "Shim interface is UP"
    else
        print_error "Failed to bring shim interface UP"
        return 1
    fi
    
    # Add route to subnet via shim
    print_info "Adding route for container subnet..."
    if sudo ip route add "$SUBNET" dev "$SHIM_INTERFACE"; then
        print_success "Route added: $SUBNET dev $SHIM_INTERFACE"
    else
        # Check if route already exists
        if ip route show | grep -q "$SHIM_INTERFACE"; then
            print_success "Route already exists"
        else
            print_warning "Failed to add route"
        fi
    fi
    
    # Verify configuration
    print_info "Verifying shim configuration..."
    if ip link show "$SHIM_INTERFACE" | grep -q "state UP"; then
        print_success "Shim interface is operational"
    else
        print_warning "Shim interface exists but may not be fully operational"
    fi
    
    if ip route show | grep -q "$SHIM_INTERFACE"; then
        print_success "Route is configured correctly"
    else
        print_warning "Route configuration may need verification"
    fi
    
    return 0
}

# ===== Make Shim Persistent =====
make_shim_persistent() {
    if [[ ! "$CREATE_SHIM" =~ ^[Yy]$ ]]; then
        return 0
    fi
    
    print_header "Making Shim Persistent"
    
    local script_path="/usr/local/bin/setup-macvlan-shim-${VLAN_ID}.sh"
    local service_path="/etc/systemd/system/macvlan-shim-${VLAN_ID}.service"
    
    print_info "Creating startup script..."
    
    # Create the startup script
    sudo tee "$script_path" > /dev/null <<EOF
#!/bin/bash
# Macvlan shim setup script for VLAN ${VLAN_ID}
# Generated by vlan-docker.sh

# Wait for parent interface to be ready
timeout=30
count=0
while [ \$count -lt \$timeout ]; do
    if ip link show ${SHIM_PARENT} &> /dev/null; then
        # For VLAN interfaces, ensure they're UP
        if [[ "${SHIM_PARENT}" == *"."* ]]; then
            if ip link show ${SHIM_PARENT} | grep -q "state UP"; then
                break
            fi
        else
            break
        fi
    fi
    sleep 1
    count=\$((count + 1))
done

if [ \$count -eq \$timeout ]; then
    echo "Timeout waiting for ${SHIM_PARENT} to be ready" >&2
    exit 1
fi

# Check if shim interface already exists
if ! ip link show ${SHIM_INTERFACE} &> /dev/null; then
    # Create macvlan shim interface
    ip link add ${SHIM_INTERFACE} link ${SHIM_PARENT} type macvlan mode bridge
    ip link set ${SHIM_INTERFACE} up
fi

# Add route if it doesn't exist
if ! ip route show | grep -q "${SHIM_INTERFACE}"; then
    ip route add ${SUBNET} dev ${SHIM_INTERFACE}
fi

exit 0
EOF
    
    sudo chmod +x "$script_path"
    print_success "Startup script created: $script_path"
    
    # Create systemd service
    print_info "Creating systemd service..."
    
    # Determine dependencies based on shim parent
    local after_deps="network-online.target"
    local wants_deps="network-online.target"
    
    if [ "$SHIM_PARENT" = "$VLAN_INTERFACE" ]; then
        after_deps="network-online.target NetworkManager.service"
        wants_deps="network-online.target"
    fi
    
    sudo tee "$service_path" > /dev/null <<EOF
[Unit]
Description=Macvlan Shim Interface for VLAN ${VLAN_ID}
After=${after_deps}
Wants=${wants_deps}
Before=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${script_path}
ExecStop=/sbin/ip link delete ${SHIM_INTERFACE}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "Systemd service created: $service_path"
    
    # Enable and start the service
    print_info "Enabling systemd service..."
    if sudo systemctl daemon-reload && \
       sudo systemctl enable "macvlan-shim-${VLAN_ID}.service" &> /dev/null; then
        print_success "Service enabled and will start on boot"
    else
        print_warning "Failed to enable service, shim may not persist after reboot"
    fi
    
    return 0
}

# ===== Docker Network Setup =====
setup_docker_network() {
    print_header "Creating Docker Network"
    
    print_info "Checking for existing Docker network..."
    
    if sudo docker network inspect "$NETWORK_NAME" &> /dev/null; then
        print_warning "Docker network '$NETWORK_NAME' already exists"
        read -rp "$(echo -e "${YELLOW}${BOLD}Do you want to delete and recreate it? (y/N): ${NC}")" delete_network < /dev/tty
        delete_network=${delete_network:-N}
        
        if [[ "$delete_network" =~ ^[Yy]$ ]]; then
            print_info "Deleting existing Docker network..."
            if sudo docker network rm "$NETWORK_NAME" &> /dev/null; then
                print_success "Deleted existing Docker network"
            else
                print_error "Failed to delete Docker network (containers might be using it)"
                return 1
            fi
        else
            print_success "Using existing Docker network"
            return 0
        fi
    fi
    
    # Build Docker network create command
    print_info "Creating Docker macvlan network '$NETWORK_NAME'..."
    
    local create_cmd="sudo docker network create -d macvlan \
        --subnet=$SUBNET \
        --gateway=$GATEWAY"
    
    if [ -n "$IP_RANGE" ]; then
        create_cmd="$create_cmd \
        --ip-range=$IP_RANGE"
    fi
    
    create_cmd="$create_cmd \
        -o parent=$VLAN_INTERFACE \
        $NETWORK_NAME"
    
    if eval "$create_cmd" &> /dev/null; then
        print_success "Docker network created successfully"
        return 0
    else
        print_error "Failed to create Docker network"
        # Show error details
        eval "$create_cmd"
        return 1
    fi
}

# ===== Display Usage Information =====
display_usage_info() {
    print_header "Setup Complete!"
    
    echo -e "${GREEN}${BOLD}✓ VLAN connection '$CONNECTION_NAME' is configured${NC}"
    echo -e "${GREEN}${BOLD}✓ VLAN interface '$VLAN_INTERFACE' is UP${NC}"
    if [[ "$CREATE_SHIM" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}${BOLD}✓ Macvlan shim '$SHIM_INTERFACE' is created and persistent${NC}"
        echo -e "${GREEN}${BOLD}✓ Shim attached to '$SHIM_PARENT'${NC}"
    fi
    echo -e "${GREEN}${BOLD}✓ Docker network '$NETWORK_NAME' is ready${NC}"
    echo ""
    
    echo -e "${CYAN}${BOLD}Connection Details:${NC}"
    echo -e "  ${YELLOW}View VLAN connection: ${NC}nmcli connection show $CONNECTION_NAME"
    echo -e "  ${YELLOW}View VLAN device: ${NC}nmcli device show $VLAN_INTERFACE"
    if [[ "$CREATE_SHIM" =~ ^[Yy]$ ]]; then
        echo -e "  ${YELLOW}View shim interface: ${NC}ip -d link show $SHIM_INTERFACE"
        echo -e "  ${YELLOW}View shim route: ${NC}ip route show | grep $SHIM_INTERFACE"
        echo -e "  ${YELLOW}Check shim service: ${NC}sudo systemctl status macvlan-shim-${VLAN_ID}.service"
    fi
    echo -e "  ${YELLOW}View Docker network: ${NC}sudo docker network inspect $NETWORK_NAME"
    echo ""
    
    echo -e "${CYAN}${BOLD}Using the Network:${NC}"
    echo ""
    echo -e "${BOLD}1. Run container with automatic IP:${NC}"
    echo -e "   ${YELLOW}docker run --network $NETWORK_NAME <image>${NC}"
    echo ""
    echo -e "${BOLD}2. Run container with specific IP:${NC}"
    echo -e "   ${YELLOW}docker run --network $NETWORK_NAME --ip <IP> <image>${NC}"
    echo ""
    echo -e "${BOLD}3. Docker Compose example:${NC}"
    echo -e "${YELLOW}   services:"
    echo -e "     myapp:"
    echo -e "       image: nginx"
    echo -e "       networks:"
    echo -e "         $NETWORK_NAME:"
    echo -e "           ipv4_address: <IP>"
    echo -e ""
    echo -e "   networks:"
    echo -e "     $NETWORK_NAME:"
    echo -e "       external: true${NC}"
    echo ""
    
    if [[ "$CREATE_SHIM" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}${BOLD}Host-to-Container Communication:${NC}"
        echo -e "  ${GREEN}✓${NC} The host can now communicate with containers on this network"
        echo -e "  ${GREEN}✓${NC} The shim interface will persist across reboots"
        echo -e "  ${YELLOW}Test:${NC} ping <container-ip>"
        echo ""
    fi
    
    print_success "All done!"
}

# ===== Main =====
main() {
    clear
    print_header "Docker Macvlan Network Setup"
    
    echo -e "${BOLD}This script will help you create a Docker macvlan network${NC}"
    echo -e "${BOLD}with optional host-to-container communication via a macvlan shim${NC}"
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
    step_shim_config
    
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
    
    if ! create_macvlan_shim; then
        print_error "Failed to create macvlan shim"
        exit 1
    fi
    
    if ! make_shim_persistent; then
        print_warning "Failed to make shim persistent (manual configuration may be needed)"
    fi
    
    if ! setup_docker_network; then
        print_error "Failed to create Docker network"
        exit 1
    fi
    
    # Show usage information
    display_usage_info
}

# Run main function
main
