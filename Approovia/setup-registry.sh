#!/bin/bash


set -e  # Exit on any error

# Configuration
REGISTRY_PORT="5000"
REGISTRY_CONTAINER_NAME="local-registry"
REGISTRY_DATA_DIR="/opt/registry-data"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to install Docker if not present
install_docker() {
    if ! command -v docker &> /dev/null; then
        log_info "Installing Docker..."
        # Update package database
        sudo apt-get update
        
        # Install required packages
        sudo apt-get install -y \
            apt-transport-https \
            ca-certificates \
            curl \
            gnupg \
            lsb-release
        
        # Add Docker's official GPG key
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        
        # Set up stable repository
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker Engine
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io
        
        # Add current user to docker group
        sudo usermod -aG docker $USER
        
        log_info "Docker installed successfully"
        log_warn "Please logout and login again for docker group membership to take effect"
    else
        log_info "Docker is already installed"
    fi
}

# Function to setup registry data directory
setup_registry_directory() {
    log_info "Setting up registry data directory..."
    sudo mkdir -p "${REGISTRY_DATA_DIR}"
    sudo chown $USER:$USER "${REGISTRY_DATA_DIR}"
    log_info "Registry data directory created at ${REGISTRY_DATA_DIR}"
}

# Function to stop existing registry if running
stop_existing_registry() {
    if docker ps | grep -q "${REGISTRY_CONTAINER_NAME}"; then
        log_info "Stopping existing registry container..."
        docker stop "${REGISTRY_CONTAINER_NAME}"
        docker rm "${REGISTRY_CONTAINER_NAME}"
    fi
}

# Function to start Docker registry
start_registry() {
    log_info "Starting Docker registry on port ${REGISTRY_PORT}..."
    
    docker run -d \
        --name "${REGISTRY_CONTAINER_NAME}" \
        --restart=always \
        -p "0.0.0.0:${REGISTRY_PORT}:5000" \
        -v "${REGISTRY_DATA_DIR}:/var/lib/registry" \
        -e REGISTRY_STORAGE_DELETE_ENABLED=true \
        registry:2
    
    log_info "Docker registry started successfully"
}

# Function to configure firewall
configure_firewall() {
    log_info "Configuring firewall for registry access..."
    
    # Check if ufw is active
    if sudo ufw status | grep -q "Status: active"; then
        sudo ufw allow "${REGISTRY_PORT}/tcp"
        log_info "Firewall rule added for port ${REGISTRY_PORT}"
    else
        log_info "UFW is not active, skipping firewall configuration"
    fi
    
    # For systems using iptables directly
    if command -v iptables &> /dev/null; then
        sudo iptables -I INPUT -p tcp --dport "${REGISTRY_PORT}" -j ACCEPT
        log_info "iptables rule added for port ${REGISTRY_PORT}"
    fi
}

# Function to test registry
test_registry() {
    log_info "Testing registry connectivity..."
    sleep 5  # Give registry time to start
    
    local registry_url="localhost:${REGISTRY_PORT}"
    
    if curl -f -s "http://${registry_url}/v2/" > /dev/null; then
        log_info "Registry is running and accessible at ${registry_url}"
        
        # Show registry info
        echo "Registry catalog: http://${registry_url}/v2/_catalog"
    else
        log_error "Registry test failed"
        docker logs "${REGISTRY_CONTAINER_NAME}"
        exit 1
    fi
}

# Function to show registry management commands
show_management_commands() {
    echo
    log_info "Registry Management Commands:"
    echo "  View logs:           docker logs ${REGISTRY_CONTAINER_NAME}"
    echo "  Stop registry:       docker stop ${REGISTRY_CONTAINER_NAME}"
    echo "  Start registry:      docker start ${REGISTRY_CONTAINER_NAME}"
    echo "  Restart registry:    docker restart ${REGISTRY_CONTAINER_NAME}"
    echo "  Remove registry:     docker stop ${REGISTRY_CONTAINER_NAME} && docker rm ${REGISTRY_CONTAINER_NAME}"
    echo "  List images:         curl -X GET http://localhost:${REGISTRY_PORT}/v2/_catalog"
    echo "  Registry data:       ${REGISTRY_DATA_DIR}"
    echo
}

# Main execution
main() {
    log_info "Setting up Docker Registry on AWS server..."
    
    # Install Docker if needed
    install_docker
    
    # Setup registry directory
    setup_registry_directory
    
    # Stop existing registry
    stop_existing_registry
    
    # Start new registry
    start_registry
    
    # Configure firewall
    configure_firewall
    
    # Test registry
    test_registry
    
    # Show management commands
    show_management_commands
    
    log_info "Docker Registry setup completed successfully!"
    log_info "Registry is accessible at: $(hostname -I | awk '{print $1}'):${REGISTRY_PORT}"
}

# Run main function
main "$@"



