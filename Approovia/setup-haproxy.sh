#!/bin/bash

# HAProxy Setup Script
# Run this on AWS server (13.51.108.204)

set -e  # Exit on any error

# Configuration
GCP_SERVER_IP="34.88.69.228"  # Your GCP server IP
SERVICE_A_PORT="8080"
SERVICE_B_PORT="8081"
HAPROXY_CONFIG_FILE="/etc/haproxy/haproxy.cfg"

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

# Function to install HAProxy
install_haproxy() {
    log_info "Installing HAProxy..."
    
    # Update package database
    sudo apt-get update
    
    # Install HAProxy
    sudo apt-get install -y haproxy
    
    # Enable HAProxy service
    sudo systemctl enable haproxy
    
    log_info "HAProxy installed successfully"
}

# Function to backup existing config
backup_existing_config() {
    if [ -f "${HAPROXY_CONFIG_FILE}" ]; then
        log_info "Backing up existing HAProxy configuration..."
        sudo cp "${HAPROXY_CONFIG_FILE}" "${HAPROXY_CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backup created: ${HAPROXY_CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
}

# Function to test connectivity to services
test_service_connectivity() {
    log_info "Testing connectivity to services on GCP..."
    
    # Test Service A
    if curl -f -s --max-time 5 "http://${GCP_SERVER_IP}:${SERVICE_A_PORT}/health" > /dev/null; then
        log_info "✓ Service A is reachable at ${GCP_SERVER_IP}:${SERVICE_A_PORT}"
    else
        log_error "✗ Cannot reach Service A at ${GCP_SERVER_IP}:${SERVICE_A_PORT}"
        log_warn "Make sure WireGuard tunnel is up and services are running"
    fi
    
    # Test Service B
    if curl -f -s --max-time 5 "http://${GCP_SERVER_IP}:${SERVICE_B_PORT}/health" > /dev/null; then
        log_info "✓ Service B is reachable at ${GCP_SERVER_IP}:${SERVICE_B_PORT}"
    else
        log_error "✗ Cannot reach Service B at ${GCP_SERVER_IP}:${SERVICE_B_PORT}"
        log_warn "Make sure WireGuard tunnel is up and services are running"
    fi
}

# Function to create HAProxy configuration
create_haproxy_config() {
    log_info "Creating HAProxy configuration..."
    
    # Create temporary config file
    local temp_config="/tmp/haproxy.cfg"
    
    cat > "${temp_config}" <<EOF
global
    log         127.0.0.1 local0
    chroot      /var/lib/haproxy
    stats       socket /run/haproxy/admin.sock mode 660 level admin
    stats       timeout 30s
    user        haproxy
    group       haproxy
    daemon

    # Default SSL material locations
    ca-base     /etc/ssl/certs
    crt-base    /etc/ssl/private

    # See: https://ssl-config.mozilla.org/#server=haproxy&server-version=2.0.3&config=intermediate
    ssl-default-bind-ciphers ECDHE+AESGCM:ECDHE+CHACHA20:RSA+AESGCM:RSA+CHACHA20:!aNULL:!MD5:!DSS
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
    mode                    http
    log                     global
    option                  httplog
    option                  dontlognull
    option                  http-server-close
    option                  forwardfor       except 127.0.0.0/8
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000

# Frontend - receives requests
frontend main
    bind *:80
    
    # Route requests based on path
    acl path_service_a path_beg /service-a
    acl path_service_b path_beg /service-b
    
    # Use backends based on path
    use_backend service_a_backend if path_service_a
    use_backend service_b_backend if path_service_b
    
    # Default backend for health checks
    default_backend stats_backend

# Backend for Service A
backend service_a_backend
    # Remove /service-a prefix when forwarding
    http-request replace-path /service-a/(.*) /\1
    http-request replace-path /service-a$ /
    
    # Health check
    option httpchk GET /health
    
    # Server definition
    server service_a_1 ${GCP_SERVER_IP}:${SERVICE_A_PORT} check

# Backend for Service B  
backend service_b_backend
    # Remove /service-b prefix when forwarding
    http-request replace-path /service-b/(.*) /\1
    http-request replace-path /service-b$ /
    
    # Health check
    option httpchk GET /health
    
    # Server definition
    server service_b_1 ${GCP_SERVER_IP}:${SERVICE_B_PORT} check

# Stats backend for monitoring
backend stats_backend
    stats enable
    stats uri /stats
    stats refresh 5s
    stats show-node
    stats show-legends
    
    # Default response for root path
    http-request return status 200 content-type text/html string "<html><body><h1>HAProxy Load Balancer</h1><p>Available services:</p><ul><li><a href='/service-a'>/service-a</a></li><li><a href='/service-b'>/service-b</a></li><li><a href='/stats'>/stats</a></li></ul></body></html>" if { path / }

EOF

    # Install the configuration
    sudo cp "${temp_config}" "${HAPROXY_CONFIG_FILE}"
    
    # Set proper permissions
    sudo chown root:root "${HAPROXY_CONFIG_FILE}"
    sudo chmod 644 "${HAPROXY_CONFIG_FILE}"
    
    log_info "HAProxy configuration created"
}

# Function to validate HAProxy configuration
validate_config() {
    log_info "Validating HAProxy configuration..."
    
    if sudo haproxy -f "${HAPROXY_CONFIG_FILE}" -c; then
        log_info "✓ HAProxy configuration is valid"
    else
        log_error "✗ HAProxy configuration is invalid"
        exit 1
    fi
}

# Function to configure firewall
configure_firewall() {
    log_info "Configuring firewall for HAProxy..."
    
    # Check if ufw is active
    if sudo ufw status | grep -q "Status: active"; then
        sudo ufw allow 80/tcp
        log_info "UFW firewall rule added for port 80"
    else
        log_info "UFW is not active, skipping UFW configuration"
    fi
    
    # For systems using iptables directly
    if command -v iptables &> /dev/null; then
        sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
        log_info "iptables rule added for port 80"
    fi
}

# Function to start HAProxy
start_haproxy() {
    log_info "Starting HAProxy service..."
    
    # Restart HAProxy service
    sudo systemctl restart haproxy
    
    # Check if HAProxy is running
    if sudo systemctl is-active --quiet haproxy; then
        log_info "✓ HAProxy is running"
    else
        log_error "✗ HAProxy failed to start"
        sudo systemctl status haproxy
        exit 1
    fi
    
    # Enable HAProxy to start on boot
    sudo systemctl enable haproxy
}

# Function to test HAProxy
test_haproxy() {
    log_info "Testing HAProxy configuration..."
    
    # Wait a moment for HAProxy to fully start
    sleep 3
    
    local aws_ip=$(hostname -I | awk '{print $1}')
    
    # Test root endpoint
    log_info "Testing root endpoint..."
    if curl -f -s "http://localhost/" > /dev/null; then
        log_info "✓ Root endpoint is working"
    else
        log_warn "✗ Root endpoint test failed"
    fi
    
    # Test service-a endpoint
    log_info "Testing /service-a endpoint..."
    if curl -f -s --max-time 10 "http://localhost/service-a" > /dev/null; then
        local response_a=$(curl -s "http://localhost/service-a")
        log_info "✓ Service A response: ${response_a}"
    else
        log_warn "✗ Service A endpoint test failed"
    fi
    
    # Test service-b endpoint
    log_info "Testing /service-b endpoint..."
    if curl -f -s --max-time 10 "http://localhost/service-b" > /dev/null; then
        local response_b=$(curl -s "http://localhost/service-b")
        log_info "✓ Service B response: ${response_b}"
    else
        log_warn "✗ Service B endpoint test failed"
    fi
    
    log_info "HAProxy is accessible at: http://${aws_ip}"
}

# Function to show final status
show_final_status() {
    local aws_ip=$(hostname -I | awk '{print $1}')
    
    echo
    echo "================================"
    log_info "HAProxy Setup Complete!"
    echo "================================"
    echo "HAProxy Endpoints:"
    echo "  Root:          http://${aws_ip}/"
    echo "  Service A:     http://${aws_ip}/service-a"
    echo "  Service B:     http://${aws_ip}/service-b"
    echo "  Stats:         http://${aws_ip}/stats"
    echo
    echo "Test Commands:"
    echo "  curl http://${aws_ip}/service-a"
    echo "  curl http://${aws_ip}/service-b"
    echo
    echo "Management Commands:"
    echo "  Status:        sudo systemctl status haproxy"
    echo "  Restart:       sudo systemctl restart haproxy"
    echo "  Logs:          sudo journalctl -u haproxy -f"
    echo "  Config:        ${HAPROXY_CONFIG_FILE}"
    echo "================================"
}

# Main execution
main() {
    log_info "Setting up HAProxy on AWS server..."
    
    # Install HAProxy
    install_haproxy
    
    # Backup existing config
    backup_existing_config
    
    # Test connectivity to services
    test_service_connectivity
    
    # Create HAProxy configuration
    create_haproxy_config
    
    # Validate configuration
    validate_config
    
    # Configure firewall
    configure_firewall
    
    # Start HAProxy
    start_haproxy
    
    # Test HAProxy
    test_haproxy
    
    # Show final status
    show_final_status
    
    log_info "HAProxy setup completed successfully!"
}

# Run main function
main "$@"
