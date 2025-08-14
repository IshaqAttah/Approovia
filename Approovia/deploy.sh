#!/bin/bash


set -e  # Exit on any error

# Configuration
AWS_IP="13.51.108.204"
GCP_IP="34.88.69.228"
AWS_USER="ubuntu"
GCP_USER="ishaq.musa"
AWS_SSH_KEY="${HOME}/Downloads/app-key-pair.pem" 
GCP_SSH_KEY="${HOME}/.ssh/id_rsa"  

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
    
    # Check if Docker is installed locally
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed locally. Please install Docker first."
        exit 1
    fi
    
    # Check if SSH keys exist
    if [ ! -f "${AWS_SSH_KEY}" ]; then
        log_error "AWS SSH key not found at ${AWS_SSH_KEY}"
        exit 1
    fi
    
    if [ ! -f "${GCP_SSH_KEY}" ]; then
        log_error "GCP SSH key not found at ${GCP_SSH_KEY}"
        exit 1
    fi
    
    # Test SSH connectivity to both servers
    log_info "Testing SSH connectivity to AWS server..."
    if ! ssh -i "${AWS_SSH_KEY}" -o ConnectTimeout=5 "${AWS_USER}@${AWS_IP}" "echo 'AWS connection OK'" > /dev/null 2>&1; then
        log_error "Cannot connect to AWS server via SSH"
        exit 1
    fi
    
    log_info "Testing SSH connectivity to GCP server..."
    if ! ssh -i "${GCP_SSH_KEY}" -o ConnectTimeout=5 "${GCP_USER}@${GCP_IP}" "echo 'GCP connection OK'" > /dev/null 2>&1; then
        log_error "Cannot connect to GCP server via SSH"
        exit 1
    fi
    
    log_info "All prerequisites met"
}

# Function to setup registry on AWS
setup_aws_registry() {
    log_step "Setting up Docker registry on AWS server..."
    
    # Copy setup script to AWS server
    scp -i "${AWS_SSH_KEY}" setup-registry.sh "${AWS_USER}@${AWS_IP}:/tmp/"
    
    # Execute setup script on AWS server
    ssh -i "${AWS_SSH_KEY}" "${AWS_USER}@${AWS_IP}" "chmod +x /tmp/setup-registry.sh && /tmp/setup-registry.sh"
    
    log_info "Registry setup completed on AWS server"
}

# Function to build and push images
build_and_push() {
    log_step "Building and pushing Docker images..."
    
    # Make sure build script is executable
    chmod +x build-and-push.sh
    
    # Execute build and push script locally
    ./build-and-push.sh
    
    log_info "Images built and pushed successfully"
}

# Function to deploy to GCP
deploy_to_gcp() {
    log_step "Deploying services to GCP server..."
    
    # Copy deploy script to GCP server
    scp -i "${GCP_SSH_KEY}" deploy-to-gcp.sh "${GCP_USER}@${GCP_IP}:/tmp/"
    
    # Execute deploy script on GCP server
    ssh -i "${GCP_SSH_KEY}" "${GCP_USER}@${GCP_IP}" "chmod +x /tmp/deploy-to-gcp.sh && /tmp/deploy-to-gcp.sh"
    
    log_info "Deployment to GCP completed successfully"
}

# Function to verify deployment
verify_deployment() {
    log_step "Verifying deployment..."
    
    log_info "Testing service endpoints..."
    
    # Test service-a
    if curl -f -s "http://${GCP_IP}:8080/" > /dev/null; then
        local response_a=$(curl -s "http://${GCP_IP}:8080/")
        log_info "✓ Service-A is running: ${response_a}"
    else
        log_warn "✗ Service-A might not be accessible from external network"
    fi
    
    # Test service-b
    if curl -f -s "http://${GCP_IP}:8081/" > /dev/null; then
        local response_b=$(curl -s "http://${GCP_IP}:8081/")
        log_info "✓ Service-B is running: ${response_b}"
    else
        log_warn "✗ Service-B might not be accessible from external network"
    fi
    
    log_info "Verification completed"
}

# Function to show final status
show_final_status() {
    echo
    echo "================================"
    log_info "Deployment Summary"
    echo "================================"
    echo "AWS Registry:    http://${AWS_IP}:5000"
    echo "Service-A URL:   http://${GCP_IP}:8080"
    echo "Service-B URL:   http://${GCP_IP}:8081"
    echo
    log_info "Useful commands:"
    echo "  Check registry: curl -X GET http://${AWS_IP}:5000/v2/_catalog"
    echo "  SSH to AWS:     ssh -i ${AWS_SSH_KEY} ${AWS_USER}@${AWS_IP}"
    echo "  SSH to GCP:     ssh -i ${GCP_SSH_KEY} ${GCP_USER}@${GCP_IP}"
    echo
    log_info "To redeploy, just run this script again!"
    echo "================================"
}

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --skip-registry    Skip setting up the registry on AWS"
    echo "  --skip-build       Skip building and pushing images"
    echo "  --skip-deploy      Skip deploying to GCP"
    echo "  --verify-only      Only verify the deployment"
    echo "  --help            Show this help message"
    echo
    echo "Configuration (edit script to change):"
    echo "  AWS IP:           ${AWS_IP}"
    echo "  GCP IP:           ${GCP_IP}"
    echo "  AWS SSH Key:      ${AWS_SSH_KEY}"
    echo "  GCP SSH Key:      ${GCP_SSH_KEY}"
    echo
}

# Parse command line arguments
SKIP_REGISTRY=false
SKIP_BUILD=false
SKIP_DEPLOY=false
VERIFY_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-registry)
            SKIP_REGISTRY=true
            shift
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --skip-deploy)
            SKIP_DEPLOY=true
            shift
            ;;
        --verify-only)
            VERIFY_ONLY=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
main() {
    log_info "Starting multi-cloud deployment process..."
    
    if [ "$VERIFY_ONLY" = true ]; then
        verify_deployment
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Setup registry on AWS (if not skipped)
    if [ "$SKIP_REGISTRY" = false ]; then
        setup_aws_registry
    else
        log_warn "Skipping registry setup"
    fi
    
    # Build and push images (if not skipped)
    if [ "$SKIP_BUILD" = false ]; then
        build_and_push
    else
        log_warn "Skipping build and push"
    fi
    
    # Deploy to GCP (if not skipped)
    if [ "$SKIP_DEPLOY" = false ]; then
        deploy_to_gcp
    else
        log_warn "Skipping deployment to GCP"
    fi
    
    # Verify deployment
    verify_deployment
    
    # Show final status
    show_final_status
    
    log_info "Multi-cloud deployment completed successfully!"
}

# Run main function
main "$@"



