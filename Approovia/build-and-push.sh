#!/bin/bash


set -e  # Exit on any error

# Configuration
AWS_REGISTRY_IP="13.51.108.204"
REGISTRY_PORT="5000"
REGISTRY_URL="${AWS_REGISTRY_IP}:${REGISTRY_PORT}"
IMAGE_TAG="latest"

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

# Function to check if registry is accessible
check_registry() {
    log_info "Checking registry connectivity..."
    if curl -f -s "http://${REGISTRY_URL}/v2/" > /dev/null; then
        log_info "Registry is accessible at ${REGISTRY_URL}"
    else
        log_error "Cannot reach registry at ${REGISTRY_URL}"
        log_info "Make sure Docker registry is running on AWS server"
        exit 1
    fi
}

# Function to build Docker image
build_image() {
    local service_name=$1
    local dockerfile_path=$2
    
    log_info "Building ${service_name} image..."
    
    if [ ! -f "${dockerfile_path}" ]; then
        log_error "Dockerfile not found at ${dockerfile_path}"
        exit 1
    fi
    
    # Get the directory containing the Dockerfile for build context
    local build_context=$(dirname "${dockerfile_path}")
    
    # Build the image for AMD64 architecture (for GCP server)
    docker build --platform linux/amd64 -t "${service_name}:${IMAGE_TAG}" -f "${dockerfile_path}" "${build_context}"
    
    # Tag for registry
    docker tag "${service_name}:${IMAGE_TAG}" "${REGISTRY_URL}/${service_name}:${IMAGE_TAG}"
    
    log_info "Successfully built and tagged ${service_name}"
}

# Function to push image to registry
push_image() {
    local service_name=$1
    
    log_info "Pushing ${service_name} to registry..."
    
    if docker push "${REGISTRY_URL}/${service_name}:${IMAGE_TAG}"; then
        log_info "Successfully pushed ${service_name}:${IMAGE_TAG}"
    else
        log_error "Failed to push ${service_name}:${IMAGE_TAG}"
        exit 1
    fi
}

# Function to cleanup local images (optional)
cleanup_local_images() {
    log_info "Cleaning up local images..."
    docker rmi "${REGISTRY_URL}/service-a:${IMAGE_TAG}" 2>/dev/null || true
    docker rmi "${REGISTRY_URL}/service-b:${IMAGE_TAG}" 2>/dev/null || true
    docker rmi "service-a:${IMAGE_TAG}" 2>/dev/null || true
    docker rmi "service-b:${IMAGE_TAG}" 2>/dev/null || true
}

# Main execution
main() {
    log_info "Starting build and push process..."
    
    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        log_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    # Check registry connectivity
    check_registry
    
    # Build and push service-a
    log_info "Processing service-a..."
    build_image "service-a" "services/service-a/Dockerfile"
    push_image "service-a"
    
    # Build and push service-b
    log_info "Processing service-b..."
    build_image "service-b" "services/service-b/Dockerfile"
    push_image "service-b"
    
    log_info "All images built and pushed successfully!"
    
    # Ask if user wants to cleanup local images
    read -p "Do you want to cleanup local images? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cleanup_local_images
        log_info "Local images cleaned up"
    fi
    
    log_info "Build and push process completed!"
    log_info "Images available at:"
    log_info "- ${REGISTRY_URL}/service-a:${IMAGE_TAG}"
    log_info "- ${REGISTRY_URL}/service-b:${IMAGE_TAG}"
}

# Run main function
main "$@"



