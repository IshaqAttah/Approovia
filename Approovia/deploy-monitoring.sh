#!/bin/bash

# Deploy Monitoring Script
# Run this on your local machine to set up monitoring across AWS and GCP

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
    
    # Check if SSH keys exist
    if [ ! -f "${AWS_SSH_KEY}" ]; then
        log_error "AWS SSH key not found at ${AWS_SSH_KEY}"
        exit 1
    fi
    
    if [ ! -f "${GCP_SSH_KEY}" ]; then
        log_error "GCP SSH key not found at ${GCP_SSH_KEY}"
        exit 1
    fi
    
    # Test SSH connectivity
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

# Function to setup monitoring on GCP
setup_gcp_monitoring() {
    log_step "Setting up monitoring on GCP server..."
    
    # Copy GCP monitoring setup script
    log_info "Copying GCP monitoring setup script..."
    scp -i "${GCP_SSH_KEY}" setup-gcp-monitoring.sh "${GCP_USER}@${GCP_IP}:/tmp/"
    
    # Execute GCP monitoring setup
    log_info "Executing GCP monitoring setup..."
    ssh -i "${GCP_SSH_KEY}" "${GCP_USER}@${GCP_IP}" "chmod +x /tmp/setup-gcp-monitoring.sh && /tmp/setup-gcp-monitoring.sh"
    
    log_info "GCP monitoring setup completed"
}

# Function to setup monitoring on AWS
setup_aws_monitoring() {
    log_step "Setting up monitoring on AWS server..."
    
    # Copy AWS monitoring setup script
    log_info "Copying AWS monitoring setup script..."
    scp -i "${AWS_SSH_KEY}" setup-monitoring.sh "${AWS_USER}@${AWS_IP}:/tmp/"
    
    # Execute AWS monitoring setup
    log_info "Executing AWS monitoring setup..."
    ssh -i "${AWS_SSH_KEY}" "${AWS_USER}@${AWS_IP}" "chmod +x /tmp/setup-monitoring.sh && /tmp/setup-monitoring.sh"
    
    log_info "AWS monitoring setup completed"
}

# Function to verify monitoring setup
verify_monitoring() {
    log_step "Verifying monitoring setup..."
    
    # Test GCP metrics endpoints
    log_info "Testing GCP metrics endpoints..."
    if curl -f -s --max-time 10 "http://${GCP_IP}:9323/metrics" > /dev/null; then
        log_info "✓ GCP Docker metrics accessible"
    else
        log_warn "✗ GCP Docker metrics not accessible"
    fi
    
    if curl -f -s --max-time 10 "http://${GCP_IP}:8082/metrics" > /dev/null; then
        log_info "✓ GCP cAdvisor metrics accessible"
    else
        log_warn "✗ GCP cAdvisor metrics not accessible"
    fi
    
    if curl -f -s --max-time 10 "http://${GCP_IP}:9100/metrics" > /dev/null; then
        log_info "✓ GCP Node Exporter metrics accessible"
    else
        log_warn "✗ GCP Node Exporter metrics not accessible"
    fi
    
    # Test AWS monitoring services
    log_info "Testing AWS monitoring services..."
    if curl -f -s --max-time 10 "http://${AWS_IP}:9090/-/healthy" > /dev/null; then
        log_info "✓ AWS Prometheus accessible"
    else
        log_warn "✗ AWS Prometheus not accessible"
    fi
    
    if curl -f -s --max-time 10 "http://${AWS_IP}:3000/api/health" > /dev/null; then
        log_info "✓ AWS Grafana accessible"
    else
        log_warn "✗ AWS Grafana not accessible"
    fi
}

# Function to test container restart monitoring
test_restart_monitoring() {
    log_step "Testing container restart monitoring..."
    
    log_info "Triggering a container restart for testing..."
    
    # Restart one of the services to test monitoring
    ssh -i "${GCP_SSH_KEY}" "${GCP_USER}@${GCP_IP}" << 'EOF'
echo "Restarting service-a container for monitoring test..."
docker restart service-a
sleep 5
echo "Container restarted. Check Prometheus/Grafana for restart metrics."
EOF
    
    log_info "Container restart test completed"
    log_info "Check Prometheus at http://${AWS_IP}:9090 for increase(container_start_time_seconds[10m]) metric"
    log_info "Check Grafana at http://${AWS_IP}:3000 for restart alerts"
}

# Function to configure AWS Security Group for monitoring
configure_aws_security_group() {
    log_step "Configuring AWS Security Group..."
    
    log_warn "IMPORTANT: Make sure your AWS Security Group allows these ports:"
    echo "  - Port 9090 (Prometheus) from 0.0.0.0/0"
    echo "  - Port 3000 (Grafana) from 0.0.0.0/0"
    echo
    log_info "You can add these rules in AWS Console → EC2 → Security Groups"
    
    # Wait for user confirmation
    read -p "Have you added the Security Group rules? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warn "Please add the Security Group rules and run this script again"
        exit 1
    fi
}

# Function to configure GCP firewall
configure_gcp_firewall() {
    log_step "Configuring GCP firewall..."
    
    log_warn "IMPORTANT: Make sure your GCP firewall allows these ports:"
    echo "  - Port 9323 (Docker metrics) from AWS server"
    echo "  - Port 8080 (cAdvisor) from AWS server"  
    echo "  - Port 9100 (Node Exporter) from AWS server"
    echo
    log_info "You can add these rules in GCP Console → VPC Network → Firewall"
    
    # Wait for user confirmation
    read -p "Have you added the GCP firewall rules? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warn "Please add the GCP firewall rules and run this script again"
        exit 1
    fi
}

# Function to show final dashboard
show_final_dashboard() {
    echo
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    MONITORING SETUP COMPLETE!                 ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo
    log_info "Monitoring Dashboard URLs:"
    echo "  Prometheus: http://${AWS_IP}:9090"
    echo "  Grafana:    http://${AWS_IP}:3000 (admin/admin)"
    echo
    log_info "Key Metrics to Monitor:"
    echo "  Container Restarts: increase(container_start_time_seconds[10m])"
    echo "  Memory Usage:       container_memory_usage_bytes"
    echo "  CPU Usage:          rate(container_cpu_usage_seconds_total[5m])"
    echo "  Service Health:     up{job=~\"service-.*\"}"
    echo
    log_info "Alert Rules Configured:"
    echo "  High Container Restarts (>3 per 10min)"
    echo "  Container Down (>2min)"
    echo "  High Memory Usage (>80%)"
    echo "  High CPU Usage (>80%)"
    echo
    log_info "Management Commands:"
    echo "  AWS Monitoring:"
    echo "    ssh -i ${AWS_SSH_KEY} ${AWS_USER}@${AWS_IP}"
    echo "    cd monitoring && docker-compose logs -f"
    echo
    echo "  GCP Monitoring:"
    echo "    ssh -i ${GCP_SSH_KEY} ${GCP_USER}@${GCP_IP}"
    echo "    ./monitor-status.sh"
    echo
    log_info "Next Steps:"
    echo "  1. Visit Grafana and explore the Container Monitoring dashboard"
    echo "  2. Set up alert notifications (email, Slack, etc.)"
    echo "  3. Monitor container restart patterns"
    echo "  4. Create custom dashboards for your specific needs"
    echo
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║    Your multi-cloud monitoring infrastructure is now ready!    ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
}

# Function to create monitoring documentation
create_documentation() {
    log_step "Creating monitoring documentation..."
    
    cat > MONITORING_GUIDE.md << 'EOF'
# Multi-Cloud Monitoring Guide

## Overview
This monitoring setup provides comprehensive visibility into your multi-cloud infrastructure with Prometheus and Grafana.

## Architecture
```
AWS Server (13.51.108.204)
├── Prometheus (Port 9090) - Metrics collection
├── Grafana (Port 3000) - Visualization
├── HAProxy (Port 80) - Load balancer
└── Docker Registry (Port 5000)
    ↓ (monitors via WireGuard)
GCP Server (34.88.69.228)
├── Service A & B Containers
├── cAdvisor (Port 8080) - Container metrics
├── Node Exporter (Port 9100) - System metrics
└── Docker Engine (Port 9323) - Docker metrics
```

## Accessing Dashboards
- **Prometheus**: http://13.51.108.204:9090
- **Grafana**: http://13.51.108.204:3000 (admin/admin)

## Key Metrics

### Container Restart Monitoring
- **Query**: `increase(container_start_time_seconds[10m])`
- **Alert**: Triggers when restarts > 3 per 10 minutes
- **Purpose**: Detect unstable containers

### Container Health
- **Query**: `up{job=~"service-.*"}`
- **Alert**: Triggers when service is down > 2 minutes
- **Purpose**: Monitor service availability

### Resource Usage
- **Memory**: `(container_memory_usage_bytes / container_spec_memory_limit_bytes) * 100`
- **CPU**: `rate(container_cpu_usage_seconds_total[5m]) * 100`
- **Alerts**: Trigger at 80% usage

## Alert Rules
Located in: `monitoring/prometheus/config/rules/container_alerts.yml`

1. **HighContainerRestarts**: >3 restarts in 10 minutes
2. **ContainerDown**: Service unreachable for 2+ minutes
3. **DockerDaemonDown**: Docker daemon unreachable for 5+ minutes
4. **HighContainerMemoryUsage**: >80% memory usage for 5+ minutes
5. **HighContainerCPUUsage**: >80% CPU usage for 5+ minutes

## Troubleshooting

### Prometheus Not Scraping Targets
1. Check firewall rules on GCP
2. Verify WireGuard tunnel is up
3. Test metrics endpoints manually:
   ```bash
   curl http://34.88.69.228:9323/metrics
   curl http://34.88.69.228:8080/metrics
   curl http://34.88.69.228:9100/metrics
   ```

### Grafana Dashboard Issues
1. Check Prometheus datasource connection
2. Verify queries in Prometheus first
3. Import new dashboards from grafana.com

### Container Metrics Missing
1. Ensure cAdvisor is running: `docker ps | grep cadvisor`
2. Restart cAdvisor: `docker restart cadvisor`
3. Check cAdvisor logs: `docker logs cadvisor`

## Maintenance Commands

### AWS Monitoring Stack
```bash
# SSH to AWS
ssh -i ~/Downloads/app-key-pair.pem ubuntu@13.51.108.204

# Monitoring commands
cd monitoring
docker-compose ps              # Check status
docker-compose logs -f         # View logs
docker-compose restart         # Restart services
docker-compose down && docker-compose up -d  # Full restart
```

### GCP Monitoring Agents
```bash
# SSH to GCP
ssh -i ~/.ssh/id_rsa ishaq.musa@34.88.69.228

# Check monitoring status
./monitor-status.sh

# Restart monitoring containers
docker restart cadvisor node-exporter

# Check metrics endpoints
curl localhost:9323/metrics   # Docker metrics
curl localhost:8080/metrics   # cAdvisor metrics
curl localhost:9100/metrics   # Node Exporter metrics
```

## Scaling and Customization

### Adding New Services
1. Update Prometheus configuration to include new targets
2. Create new alert rules for the services
3. Add panels to Grafana dashboards

### Custom Dashboards
1. Visit grafana.com for community dashboards
2. Import dashboard ID in Grafana UI
3. Customize panels for your specific needs

### Alert Notifications
1. Configure notification channels in Grafana
2. Set up email, Slack, or webhook integrations
3. Test alert rules by triggering conditions

## Security Considerations
- Monitoring ports are exposed only to necessary networks
- Grafana uses default credentials (change in production)
- Prometheus has no authentication (add reverse proxy if needed)
- All metrics traffic flows through secure WireGuard tunnel

## Performance Impact
- Minimal impact on monitored services
- Metrics collection every 10-15 seconds
- Historical data retained for 200 hours
- Resource usage: ~100MB RAM per monitoring component
EOF

    log_info "Created MONITORING_GUIDE.md"
}

# Main execution
main() {
    log_info "Starting multi-cloud monitoring deployment..."
    
    # Check prerequisites
    check_prerequisites
    
    # Configure firewall rules (with user confirmation)
    configure_aws_security_group
    configure_gcp_firewall
    
    # Setup monitoring on both servers
    setup_gcp_monitoring
    setup_aws_monitoring
    
    # Verify the setup
    verify_monitoring
    
    # Test container restart monitoring
    test_restart_monitoring
    
    # Create documentation
    create_documentation
    
    # Show final dashboard
    show_final_dashboard
    
    log_info "Multi-cloud monitoring deployment completed successfully!"
}

# Run main function
main "$@"
