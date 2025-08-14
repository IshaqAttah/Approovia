#!/bin/bash

# GCP Monitoring Setup Script
# Run this on GCP server (34.88.69.228) to expose Docker metrics

set -e  # Exit on any error

# Configuration
DOCKER_METRICS_PORT="9323"
CADVISOR_PORT="8082"  # Changed to 8082 to avoid conflict with Service B on 8081
NODE_EXPORTER_PORT="9100"

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

# Function to enable Docker metrics
enable_docker_metrics() {
    log_step "Enabling Docker daemon metrics..."
    
    # Create or update Docker daemon configuration
    local daemon_config="/etc/docker/daemon.json"
    local temp_config="/tmp/daemon.json"
    
    # Check if daemon.json exists and backup
    if [ -f "${daemon_config}" ]; then
        sudo cp "${daemon_config}" "${daemon_config}.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backed up existing daemon.json"
    fi
    
    # Create new daemon configuration with metrics enabled
    cat > "${temp_config}" <<EOF
{
    "insecure-registries": ["13.51.108.204:5000"],
    "metrics-addr": "0.0.0.0:${DOCKER_METRICS_PORT}",
    "experimental": true
}
EOF
    
    # Install new configuration
    sudo cp "${temp_config}" "${daemon_config}"
    
    # Restart Docker daemon
    log_info "Restarting Docker daemon..."
    sudo systemctl restart docker
    
    # Wait for Docker to restart
    sleep 5
    
    # Verify Docker is running
    if docker info > /dev/null 2>&1; then
        log_info "✓ Docker daemon restarted successfully"
    else
        log_error "✗ Docker daemon failed to restart"
        exit 1
    fi
    
    log_info "Docker metrics enabled on port ${DOCKER_METRICS_PORT}"
}

# Function to deploy cAdvisor for container metrics
deploy_cadvisor() {
    log_step "Deploying cAdvisor for container metrics..."
    
    # Stop existing cAdvisor if running
    docker stop cadvisor 2>/dev/null || true
    docker rm cadvisor 2>/dev/null || true
    
    # Deploy cAdvisor
    docker run -d \
        --name=cadvisor \
        --restart=unless-stopped \
        --volume=/:/rootfs:ro \
        --volume=/var/run:/var/run:ro \
        --volume=/sys:/sys:ro \
        --volume=/var/lib/docker/:/var/lib/docker:ro \
        --volume=/dev/disk/:/dev/disk:ro \
        --publish=${CADVISOR_PORT}:8080 \
        --detach=true \
        --privileged \
        --device=/dev/kmsg \
        gcr.io/cadvisor/cadvisor:latest
    
    # Wait for cAdvisor to start
    sleep 10
    
    # Verify cAdvisor is running
    if curl -f -s "http://localhost:${CADVISOR_PORT}/metrics" > /dev/null; then
        log_info "✓ cAdvisor is running and exposing metrics"
    else
        log_warn "✗ cAdvisor metrics endpoint not accessible"
    fi
    
    log_info "cAdvisor deployed on port ${CADVISOR_PORT}"
}

# Function to deploy Node Exporter for system metrics
deploy_node_exporter() {
    log_step "Deploying Node Exporter for system metrics..."
    
    # Stop existing Node Exporter if running
    docker stop node-exporter 2>/dev/null || true
    docker rm node-exporter 2>/dev/null || true
    
    # Deploy Node Exporter
    docker run -d \
        --name=node-exporter \
        --restart=unless-stopped \
        --publish=${NODE_EXPORTER_PORT}:9100 \
        --volume="/proc:/host/proc:ro" \
        --volume="/sys:/host/sys:ro" \
        --volume="/:/rootfs:ro" \
        --volume="/etc/hostname:/etc/nodename:ro" \
        --volume="/etc/localtime:/etc/localtime:ro" \
        prom/node-exporter:latest \
        --path.procfs=/host/proc \
        --path.sysfs=/host/sys \
        --collector.filesystem.mount-points-exclude="^/(sys|proc|dev|host|etc)(\$|/)"
    
    # Wait for Node Exporter to start
    sleep 5
    
    # Verify Node Exporter is running
    if curl -f -s "http://localhost:${NODE_EXPORTER_PORT}/metrics" > /dev/null; then
        log_info "✓ Node Exporter is running and exposing metrics"
    else
        log_warn "✗ Node Exporter metrics endpoint not accessible"
    fi
    
    log_info "Node Exporter deployed on port ${NODE_EXPORTER_PORT}"
}

# Function to configure firewall
configure_firewall() {
    log_step "Configuring firewall for monitoring ports..."
    
    # Check if ufw is active
    if sudo ufw status | grep -q "Status: active"; then
        sudo ufw allow ${DOCKER_METRICS_PORT}/tcp
        sudo ufw allow ${CADVISOR_PORT}/tcp
        sudo ufw allow ${NODE_EXPORTER_PORT}/tcp
        log_info "UFW firewall rules added for monitoring ports"
    else
        log_info "UFW is not active, skipping UFW configuration"
    fi
    
    # For systems using iptables directly
    if command -v iptables &> /dev/null; then
        sudo iptables -I INPUT -p tcp --dport ${DOCKER_METRICS_PORT} -j ACCEPT
        sudo iptables -I INPUT -p tcp --dport ${CADVISOR_PORT} -j ACCEPT
        sudo iptables -I INPUT -p tcp --dport ${NODE_EXPORTER_PORT} -j ACCEPT
        log_info "iptables rules added for monitoring ports"
    fi
}

# Function to verify metrics endpoints
verify_metrics() {
    log_step "Verifying metrics endpoints..."
    
    local gcp_ip=$(hostname -I | awk '{print $1}')
    
    # Test Docker metrics
    if curl -f -s "http://localhost:${DOCKER_METRICS_PORT}/metrics" > /dev/null; then
        log_info "✓ Docker metrics available at :${DOCKER_METRICS_PORT}/metrics"
    else
        log_warn "✗ Docker metrics not accessible"
    fi
    
    # Test cAdvisor metrics
    if curl -f -s "http://localhost:${CADVISOR_PORT}/metrics" > /dev/null; then
        log_info "✓ cAdvisor metrics available at :${CADVISOR_PORT}/metrics"
    else
        log_warn "✗ cAdvisor metrics not accessible"
    fi
    
    # Test Node Exporter metrics
    if curl -f -s "http://localhost:${NODE_EXPORTER_PORT}/metrics" > /dev/null; then
        log_info "✓ Node Exporter metrics available at :${NODE_EXPORTER_PORT}/metrics"
    else
        log_warn "✗ Node Exporter metrics not accessible"
    fi
    
    echo
    log_info "Metrics endpoints accessible from AWS Prometheus:"
    echo "  Docker metrics:    ${gcp_ip}:${DOCKER_METRICS_PORT}/metrics"
    echo "  Container metrics: ${gcp_ip}:${CADVISOR_PORT}/metrics"
    echo "  System metrics:    ${gcp_ip}:${NODE_EXPORTER_PORT}/metrics"
}

# Function to create monitoring status script
create_status_script() {
    log_step "Creating monitoring status script..."
    
    cat > monitor-status.sh <<'EOF'
#!/bin/bash

echo "=== GCP Monitoring Status ==="
echo

echo "Docker Daemon:"
if curl -f -s http://localhost:9323/metrics > /dev/null; then
    echo "  ✓ Docker metrics: http://localhost:9323/metrics"
else
    echo "  ✗ Docker metrics: FAILED"
fi

echo
echo "cAdvisor:"
if docker ps | grep -q cadvisor; then
    echo "  ✓ cAdvisor container: RUNNING"
    if curl -f -s http://localhost:8080/metrics > /dev/null; then
        echo "  ✓ cAdvisor metrics: http://localhost:8080/metrics"
    else
        echo "  ✗ cAdvisor metrics: FAILED"
    fi
else
    echo "  ✗ cAdvisor container: NOT RUNNING"
fi

echo
echo "Node Exporter:"
if docker ps | grep -q node-exporter; then
    echo "  ✓ Node Exporter container: RUNNING"
    if curl -f -s http://localhost:9100/metrics > /dev/null; then
        echo "  ✓ Node Exporter metrics: http://localhost:9100/metrics"
    else
        echo "  ✗ Node Exporter metrics: FAILED"
    fi
else
    echo "  ✗ Node Exporter container: NOT RUNNING"
fi

echo
echo "Service Containers:"
docker ps --filter "name=service-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo
echo "=== End Status ==="
EOF

    chmod +x monitor-status.sh
    log_info "Created monitor-status.sh script"
}

# Function to show final status
show_final_status() {
    local gcp_ip=$(hostname -I | awk '{print $1}')
    
    echo
    echo "================================"
    log_info "GCP Monitoring Setup Complete!"
    echo "================================"
    echo "Monitoring Services:"
    echo "  Docker Metrics:    :${DOCKER_METRICS_PORT}/metrics"
    echo "  cAdvisor:          :${CADVISOR_PORT}"
    echo "  Node Exporter:     :${NODE_EXPORTER_PORT}"
    echo
    echo "External Access (from AWS Prometheus):"
    echo "  ${gcp_ip}:${DOCKER_METRICS_PORT}/metrics"
    echo "  ${gcp_ip}:${CADVISOR_PORT}/metrics" 
    echo "  ${gcp_ip}:${NODE_EXPORTER_PORT}/metrics"
    echo
    echo "Management Commands:"
    echo "  Status:           ./monitor-status.sh"
    echo "  Restart cAdvisor: docker restart cadvisor"
    echo "  Restart NodeExp:  docker restart node-exporter"
    echo "  View containers:  docker ps"
    echo
    echo "Container Monitoring:"
    echo "  - Container restarts will be tracked"
    echo "  - Memory and CPU usage monitored"
    echo "  - Health checks monitored"
    echo "  - Alert threshold: ${CONTAINER_RESTART_THRESHOLD} restarts/10min"
    echo "================================"
}

# Main execution
main() {
    log_info "Setting up monitoring on GCP server..."
    
    # Enable Docker metrics
    enable_docker_metrics
    
    # Deploy monitoring containers
    deploy_cadvisor
    deploy_node_exporter
    
    # Configure firewall
    configure_firewall
    
    # Verify metrics endpoints
    verify_metrics
    
    # Create status script
    create_status_script
    
    # Show final status
    show_final_status
    
    log_info "GCP monitoring setup completed successfully!"
    log_info "You can now run Prometheus setup on AWS to start monitoring."
}

# Run main function
main "$@"
