#!/bin/bash

# Drone CI Setup Script
# Run this on your local machine

set -e  # Exit on any error

# Configuration
DRONE_VERSION="2.24.0"
DRONE_RUNNER_VERSION="1.8.3"
DRONE_SERVER_HOST="localhost"
DRONE_SERVER_PORT="3000"
DRONE_RPC_SECRET=$(openssl rand -hex 16)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    # Check if Docker is installed and running
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! docker info > /dev/null 2>&1; then
        log_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    # Check if Docker Compose is available
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null 2>&1; then
        log_error "Docker Compose is not available. Please install Docker Compose."
        exit 1
    fi
    
    log_info "All prerequisites met"
}

# Function to create drone directories
create_directories() {
    log_step "Creating Drone directories..."
    
    mkdir -p drone-ci/{data,logs}
    cd drone-ci
    
    log_info "Created drone-ci directory structure"
}

# Function to create docker-compose file for Drone
create_docker_compose() {
    log_step "Creating Docker Compose configuration..."
    
    cat > docker-compose.yml <<EOF
services:
  drone-server:
    image: drone/drone:${DRONE_VERSION}
    container_name: drone-server
    ports:
      - "${DRONE_SERVER_PORT}:80"
    volumes:
      - ./data:/data
      - ./logs:/var/log
      - ./secrets:/drone/secrets
    environment:
      - DRONE_RPC_SECRET=${DRONE_RPC_SECRET}
      - DRONE_SERVER_HOST=${DRONE_SERVER_HOST}:${DRONE_SERVER_PORT}
      - DRONE_SERVER_PROTO=http
      - DRONE_OPEN=true
      - DRONE_ADMIN=admin
      - DRONE_USER_CREATE=username:admin,admin:true
      - DRONE_LOGS_DEBUG=true
      - DRONE_REPOSITORY_FILTER=*
      - DRONE_GOGS=false
      - DRONE_GOGS_SERVER=
      - DRONE_GITHUB=false
      - DRONE_GITLAB=false
      - DRONE_BITBUCKET=false
      - DRONE_STASH=false
    restart: unless-stopped
    networks:
      - drone-network

  drone-runner:
    image: drone/drone-runner-docker:${DRONE_RUNNER_VERSION}
    container_name: drone-runner
    depends_on:
      - drone-server
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/data
      - ./secrets:/drone/secrets
    environment:
      - DRONE_RPC_PROTO=http
      - DRONE_RPC_HOST=drone-server
      - DRONE_RPC_SECRET=${DRONE_RPC_SECRET}
      - DRONE_RUNNER_CAPACITY=2
      - DRONE_RUNNER_NAME=local-runner
      - DRONE_LOGS_DEBUG=true
    restart: unless-stopped
    networks:
      - drone-network

networks:
  drone-network:
    driver: bridge

volumes:
  drone-data:
  drone-logs:
EOF

    log_info "Docker Compose configuration created"
}

# Function to create environment file
create_env_file() {
    log_step "Creating environment configuration..."
    
    cat > .env <<EOF
# Drone CI Configuration
DRONE_RPC_SECRET=${DRONE_RPC_SECRET}
DRONE_SERVER_HOST=${DRONE_SERVER_HOST}:${DRONE_SERVER_PORT}

# GitHub OAuth (Optional - for GitHub integration)
# Get these from: https://github.com/settings/applications/new
# DRONE_GITHUB_CLIENT_ID=your_github_client_id
# DRONE_GITHUB_CLIENT_SECRET=your_github_client_secret

# Registry Configuration
DOCKER_REGISTRY=13.51.108.204:5000
AWS_IP=13.51.108.204
GCP_IP=34.88.69.228

# SSH Configuration
AWS_SSH_KEY_PATH=/drone/secrets/aws-key
GCP_SSH_KEY_PATH=/drone/secrets/gcp-key
AWS_USER=ubuntu
GCP_USER=ishaq.musa
EOF

    log_info "Environment configuration created"
}

# Function to create secrets directory
create_secrets_directory() {
    log_step "Setting up secrets directory..."
    
    mkdir -p secrets
    
    # Copy SSH keys to secrets directory
    if [ -f "${HOME}/Downloads/app-key-pair.pem" ]; then
        cp "${HOME}/Downloads/app-key-pair.pem" secrets/aws-key
        chmod 600 secrets/aws-key
        log_info "AWS SSH key copied to secrets directory"
    else
        log_warn "AWS SSH key not found at ${HOME}/Downloads/app-key-pair.pem"
    fi
    
    if [ -f "${HOME}/.ssh/id_rsa" ]; then
        cp "${HOME}/.ssh/id_rsa" secrets/gcp-key
        chmod 600 secrets/gcp-key
        log_info "GCP SSH key copied to secrets directory"
    else
        log_warn "GCP SSH key not found at ${HOME}/.ssh/id_rsa"
    fi
    
    log_info "Secrets directory configured"
}

# Function to start Drone CI
start_drone() {
    log_step "Starting Drone CI..."
    
    # Start Drone services
    docker-compose up -d
    
    # Wait for services to start
    log_info "Waiting for Drone server to start..."
    sleep 10
    
    # Check if services are running
    if docker-compose ps | grep -q "Up"; then
        log_info "✓ Drone CI services are running"
    else
        log_error "✗ Failed to start Drone CI services"
        docker-compose logs
        exit 1
    fi
}

# Function to verify installation
verify_installation() {
    log_step "Verifying Drone CI installation..."
    
    # Test Drone server endpoint
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -f -s "http://localhost:${DRONE_SERVER_PORT}/healthz" > /dev/null; then
            log_info "✓ Drone server is healthy"
            break
        else
            echo -n "."
            sleep 2
            ((attempt++))
        fi
    done
    
    if [ $attempt -gt $max_attempts ]; then
        log_error "✗ Drone server health check failed"
        return 1
    fi
    
    # Show running containers
    echo
    log_info "Running containers:"
    docker-compose ps
}

# Function to install Drone CLI
install_drone_cli() {
    log_step "Installing Drone CLI..."
    
    # Detect OS and architecture
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch=$(uname -m)
    
    case $arch in
        x86_64) arch="amd64" ;;
        arm64|aarch64) arch="arm64" ;;
        *) log_error "Unsupported architecture: $arch"; return 1 ;;
    esac
    
    # Download Drone CLI
    local drone_cli_url="https://github.com/harness/drone-cli/releases/latest/download/drone_${os}_${arch}.tar.gz"
    
    log_info "Downloading Drone CLI from: $drone_cli_url"
    curl -L "$drone_cli_url" | tar zx
    
    # Make executable and move to PATH
    chmod +x drone
    sudo mv drone /usr/local/bin/
    
    log_info "Drone CLI installed successfully"
}

# Function to show final status
show_final_status() {
    echo
    echo "================================"
    log_info "Drone CI Setup Complete!"
    echo "================================"
    echo "Drone Server:     http://localhost:${DRONE_SERVER_PORT}"
    echo "RPC Secret:       ${DRONE_RPC_SECRET}"
    echo
    echo "Next Steps:"
    echo "1. Visit http://localhost:${DRONE_SERVER_PORT}"
    echo "2. Login with username: admin"
    echo "3. Create your repository and pipeline"
    echo
    echo "Configuration Files:"
    echo "  Docker Compose:   $(pwd)/docker-compose.yml"
    echo "  Environment:      $(pwd)/.env"
    echo "  Secrets:          $(pwd)/secrets/"
    echo
    echo "Management Commands:"
    echo "  Start:            docker-compose up -d"
    echo "  Stop:             docker-compose down"
    echo "  Logs:             docker-compose logs -f"
    echo "  Status:           docker-compose ps"
    echo
    echo "Drone CLI Commands:"
    echo "  drone server         # Show server info"
    echo "  drone repo ls        # List repositories"
    echo "  drone build ls       # List builds"
    echo "================================"
}

# Main execution
main() {
    log_info "Starting Drone CI setup..."
    
    # Check prerequisites
    check_prerequisites
    
    # Create directories
    create_directories
    
    # Create configuration files
    create_docker_compose
    create_env_file
    create_secrets_directory
    
    # Install Drone CLI
    install_drone_cli
    
    # Start Drone CI
    start_drone
    
    # Verify installation
    verify_installation
    
    # Show final status
    show_final_status
    
    log_info "Drone CI setup completed successfully!"
}

# Run main function
main "$@"
