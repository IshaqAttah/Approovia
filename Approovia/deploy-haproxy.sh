#!/bin/bash

set -e  # Exit on any error

# Configuration
AWS_IP="13.51.108.204"
AWS_USER="ubuntu"
AWS_SSH_KEY="${HOME}/Downloads/app-key-pair.pem"

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
    
    # Check if SSH key exists
    if [ ! -f "${AWS_SSH_KEY}" ]; then
        log_error "AWS SSH key not found at ${AWS_SSH_KEY}"
        exit 1
    fi
    
    # Test SSH connectivity to AWS server
    log_info "Testing SSH connectivity to AWS server..."
    if ! ssh -i "${AWS_SSH_KEY}" -o ConnectTimeout=5 "${AWS_USER}@${AWS_IP}" "echo 'AWS connection OK'" > /dev/null 2>&1; then
        log_error "Cannot connect to AWS server via SSH"
        exit 1
    fi
    
    log_info "All prerequisites met"
}

# Function to deploy HAProxy setup script
deploy_haproxy_setup() {
    log_step "Deploying HAProxy setup to AWS server..."
    
    # Copy setup script to AWS server
    log_info "Copying HAProxy setup script to AWS server..."
    scp -i "${AWS_SSH_KEY}" setup-haproxy.sh "${AWS_USER}@${AWS_IP}:/tmp/"
    
    # Execute setup script on AWS server
    log_info "Executing HAProxy setup script on AWS server..."
    ssh -i "${AWS_SSH_KEY}" "${AWS_USER}@${AWS_IP}" "chmod +x /tmp/setup-haproxy.sh && /tmp/setup-haproxy.sh"
    
    log_info "HAProxy setup completed on AWS server"
}

# Function to verify HAProxy deployment
verify_haproxy() {
    log_step "Verifying HAProxy deployment..."
    
    log_info "Testing HAProxy endpoints from local machine..."
    
    # Test service-a
    if curl -f -s --max-time 10 "http://${AWS_IP}/service-a" > /dev/null; then
        local response_a=$(curl -s "http://${AWS_IP}/service-a")
        log_info "✓ Service A via HAProxy: ${response_a}"
    else
        log_warn "✗ Service A might not be accessible via HAProxy"
    fi
    
    # Test service-b
    if curl -f -s --max-time 10 "http://${AWS_IP}/service-b" > /dev/null; then
        local response_b=$(curl -s "http://${AWS_IP}/service-b")
        log_info "✓ Service B via HAProxy: ${response_b}"
    else
        log_warn "✗ Service B might not be accessible via HAProxy"
    fi
    
    # Test stats endpoint
    if curl -f -s "http://${AWS_IP}/stats" > /dev/null; then
        log_info "✓ HAProxy stats page is accessible"
    else
        log_warn "✗ HAProxy stats page might not be accessible"
    fi
}

# Function to show deployment summary
show_deployment_summary() {
    echo
    echo "================================"
    log_info "HAProxy Deployment Summary"
    echo "================================"
    echo "HAProxy Load Balancer: http://${AWS_IP}"
    echo
    echo "Service Endpoints:"
    echo "  Service A:         http://${AWS_IP}/service-a"
    echo "  Service B:         http://${AWS_IP}/service-b"
    echo "  HAProxy Stats:     http://${AWS_IP}/stats"
    echo "  Root Page:         http://${AWS_IP}/"
    echo
    echo "Test Commands:"
    echo "  curl http://${AWS_IP}/service-a"
    echo "  curl http://${AWS_IP}/service-b"
    echo
    echo "Architecture:"
    echo "  Local Machine → AWS HAProxy → GCP Services"
    echo "  Request Flow: Client → HAProxy (AWS) → WireGuard → Services (GCP)"
    echo
    echo "Management:"
    echo "  SSH to HAProxy:    ssh -i ${AWS_SSH_KEY} ${AWS_USER}@${AWS_IP}"
    echo "  HAProxy Config:    /etc/haproxy/haproxy.cfg"
    echo "  HAProxy Logs:      sudo journalctl -u haproxy -f"
    echo "================================"
}

# Function to run demonstration
run_demonstration() {
    log_step "Running demonstration..."
    
    echo
    log_info "Demonstrating HAProxy routing:"
    echo "==============================="
    
    echo
    log_info "Testing Service A route:"
    echo "Command: curl http://${AWS_IP}/service-a"
    if curl -f -s "http://${AWS_IP}/service-a"; then
        echo
        log_info "✓ Service A is reachable via HAProxy"
    else
        echo
        log_error "✗ Service A test failed"
    fi
    
    echo
    echo
    log_info "Testing Service B route:"
    echo "Command: curl http://${AWS_IP}/service-b"
    if curl -f -s "http://${AWS_IP}/service-b"; then
        echo
        log_info "✓ Service B is reachable via HAProxy"
    else
        echo
        log_error "✗ Service B test failed"
    fi
    
    echo
    echo
    log_info "Testing root page:"
    echo "Command: curl http://${AWS_IP}/"
    curl -s "http://${AWS_IP}/" || log_warn "Root page test failed"
    
    echo
    echo "==============================="
}

# Main execution
main() {
    log_info "Starting HAProxy deployment process..."
    
    # Check prerequisites
    check_prerequisites
    
    # Deploy HAProxy setup
    deploy_haproxy_setup
    
    # Verify deployment
    verify_haproxy
    
    # Show deployment summary
    show_deployment_summary
    
    # Run demonstration
    run_demonstration
    
    log_info "HAProxy deployment and demonstration completed!"
}

# Run main function
main "$@"



