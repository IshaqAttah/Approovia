#!/bin/bash

# Deploy to GCP Script
# Run this on GCP server (34.88.69.228)

set -e  # Exit on any error

# Configuration
AWS_REGISTRY_IP="13.51.108.204"
REGISTRY_PORT="5000"
REGISTRY_URL="${AWS_REGISTRY_IP}:${REGISTRY_PORT}"
IMAGE_TAG="latest"

# Container configuration
SERVICE_A_PORT="8080"
SERVICE_B_PORT="8081"
NETWORK_NAME="services-network"

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

# Function to configure Docker daemon for insecure registry
configure_docker_daemon() {
    log_info "Configuring Docker daemon for insecure registry..."
    
    local daemon_config="/etc/docker/daemon.json"
    local temp_config="/tmp/daemon.json"
    
    # Create daemon.json with insecure registry configuration
    cat > "${temp_config}" <<EOF
{
    "insecure-registries": ["${REGISTRY_URL}"]
}
EOF
    
    # Backup existing config if it exists
    if [ -f "${daemon_config}" ]; then
        sudo cp "${daemon_config}" "${daemon_config}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Install new config
    sudo cp "${temp_config}" "${daemon_config}"
    
    # Restart Docker daemon
    sudo systemctl restart docker
    
    log_info "Docker daemon configured for insecure registry ${REGISTRY_URL}"
}

# Function to test registry connectivity
test_registry_connectivity() {
    log_info "Testing registry connectivity..."
    
    if curl -f -s "http://${REGISTRY_URL}/v2/" > /dev/null; then
        log_info "Registry is accessible at ${REGISTRY_URL}"
    else
        log_error "Cannot reach registry at ${REGISTRY_URL}"
        log_info "Make sure:"
        log_info "1. WireGuard tunnel is up"
        log_info "2. Registry is running on AWS server"
        log_info "3. Firewall allows port ${REGISTRY_PORT}"
        exit 1
    fi
}

# Function to create Docker network
create_network() {
    log_info "Creating Docker network..."
    
    if docker network ls | grep -q "${NETWORK_NAME}"; then
        log_info "Network ${NETWORK_NAME} already exists"
    else
        docker network create "${NETWORK_NAME}"
        log_info "Created network ${NETWORK_NAME}"
    fi
}

# Function to stop existing containers
stop_existing_containers() {
    log_info "Stopping existing containers..."
    
    docker stop service-a service-b 2>/dev/null || true
    docker rm service-a service-b 2>/dev/null || true
    
    log_info "Existing containers stopped and removed"
}

# Function to pull image from registry
pull_image() {
    local service_name=$1
    local image_url="${REGISTRY_URL}/${service_name}:${IMAGE_TAG}"
    
    log_info "Pulling ${service_name} from registry..."
    
    if docker pull "${image_url}"; then
        log_info "Successfully pulled ${image_url}"
    else
        log_error "Failed to pull ${image_url}"
        exit 1
    fi
}

# Function to run container
run_container() {
    local service_name=$1
    local port=$2
    local image_url="${REGISTRY_URL}/${service_name}:${IMAGE_TAG}"
    
    log_info "Running ${service_name} container..."
    
    docker run -d \
        --name "${service_name}" \
        --network "${NETWORK_NAME}" \
        --restart unless-stopped \
        -p "${port}:8080" \
        --health-cmd="wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1" \
        --health-interval=30s \
        --health-timeout=3s \
        --health-start-period=5s \
        --health-retries=3 \
        "${image_url}"
    
    log_info "${service_name} container started on port ${port}"
}

# Function to wait for containers to be healthy
wait_for_health() {
    local service_name=$1
    local max_attempts=30
    local attempt=1
    
    log_info "Waiting for ${service_name} to become healthy..."
    
    while [ $attempt -le $max_attempts ]; do
        local health_status=$(docker inspect --format='{{.State.Health.Status}}' "${service_name}" 2>/dev/null || echo "unknown")
        
        case $health_status in
            "healthy")
                log_info "${service_name} is healthy"
                return 0
                ;;
            "unhealthy")
                log_error "${service_name} is unhealthy"
                docker logs "${service_name}" --tail 10
                return 1
                ;;
            "starting"|"unknown")
                echo -n "."
                sleep 2
                ((attempt++))
                ;;
        esac
    done
    
    log_error "Timeout waiting for ${service_name} to become healthy"
    docker logs "${service_name}" --tail 10
    return 1
}

# Function to test deployed services
test_services() {
    log_info "Testing deployed services..."
    
    local gcp_ip=$(hostname -I | awk '{print $1}')
    
    # Test service-a
    log_info "Testing service-a..."
    if curl -f -s "http://localhost:${SERVICE_A_PORT}/health" > /dev/null; then
        local response_a=$(curl -s "http://localhost:${SERVICE_A_PORT}/")
        log_info "Service-A response: ${response_a}"
        log_info "Service-A accessible at: http://${gcp_ip}:${SERVICE_A_PORT}"
    else
        log_error "Service-A health check failed"
    fi
    
    # Test service-b
    log_info "Testing service-b..."
    if curl -f -s "http://localhost:${SERVICE_B_PORT}/health" > /dev/null; then
        local response_b=$(curl -s "http://localhost:${SERVICE_B_PORT}/")
        log_info "Service-B response: ${response_b}"
        log_info "Service-B accessible at: http://${gcp_ip}:${SERVICE_B_PORT}"
    else
        log_error "Service-B health check failed"
    fi
}

# Function to show deployment status
show_deployment_status() {
    echo
    log_info "Deployment Status:"
    echo "=================="
    
    docker ps --filter "name=service-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo
    log_info "Service URLs:"
    local gcp_ip=$(hostname -I | awk '{print $1}')
    echo "  Service-A: http://${gcp_ip}:${SERVICE_A_PORT}"
    echo "  Service-B: http://${gcp_ip}:${SERVICE_B_PORT}"
    
    echo
    log_info "Management Commands:"
    echo "  View logs:        docker logs <service-name>"
    echo "  Stop services:    docker stop service-a service-b"
    echo "  Start services:   docker start service-a service-b"
    echo "  Remove services:  docker stop service-a service-b && docker rm service-a service-b"
    echo
}

# Main execution
main() {
    log_info "Starting deployment to GCP server..."
    
    # Install Docker if needed
    install_docker
    
    # Configure Docker daemon
    configure_docker_daemon
    
    # Test registry connectivity
    test_registry_connectivity
    
    # Create network
    create_network
    
    # Stop existing containers
    stop_existing_containers
    
    # Pull and run service-a
    pull_image "service-a"
    run_container "service-a" "${SERVICE_A_PORT}"
    wait_for_health "service-a"
    
    # Pull and run service-b
    pull_image "service-b"
    run_container "service-b" "${SERVICE_B_PORT}"
    wait_for_health "service-b"
    
    # Test services
    test_services
    
    # Show deployment status
    show_deployment_status
    
    log_info "Deployment completed successfully!"
}

# Run main function
main "$@"
