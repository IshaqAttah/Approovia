#!/bin/bash

# Monitoring Setup Script - Prometheus & Grafana
# Run this on AWS server (13.51.108.204)

set -e  # Exit on any error

# Configuration
GCP_SERVER_IP="34.88.69.228"
PROMETHEUS_PORT="9090"
GRAFANA_PORT="3000"
CONTAINER_RESTART_THRESHOLD="3"  # Alert if restarts > 3 per 10 minutes

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
    
    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        log_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    # Check if Docker Compose is available
    if command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    elif docker compose version &> /dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    else
        log_error "Docker Compose is not available. Installing docker-compose..."
        
        # Install docker-compose
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        
        # Verify installation
        if command -v docker-compose &> /dev/null; then
            COMPOSE_CMD="docker-compose"
            log_info "docker-compose installed successfully"
        else
            log_error "Failed to install docker-compose"
            exit 1
        fi
    fi
    
    log_info "All prerequisites met"
}

# Function to create monitoring directory structure
create_directories() {
    log_step "Creating monitoring directory structure..."
    
    mkdir -p monitoring/{prometheus/{config,data},grafana/{config,data,dashboards,provisioning/{dashboards,datasources}}}
    
    log_info "Directory structure created"
}

# Function to create Prometheus configuration
create_prometheus_config() {
    log_step "Creating Prometheus configuration..."
    
    cat > monitoring/prometheus/config/prometheus.yml <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "/etc/prometheus/rules/*.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: []

scrape_configs:
  # Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Docker daemon metrics on AWS (local)
  - job_name: 'docker-aws'
    static_configs:
      - targets: ['host.docker.internal:9323']
    scrape_interval: 10s
    metrics_path: /metrics

  # Docker daemon metrics on GCP (via WireGuard)
  - job_name: 'docker-gcp'
    static_configs:
      - targets: ['${GCP_SERVER_IP}:9323']
    scrape_interval: 10s
    metrics_path: /metrics

  # cAdvisor on GCP for container metrics
  - job_name: 'cadvisor-gcp'
    static_configs:
      - targets: ['${GCP_SERVER_IP}:8082']  # Updated to port 8082
    scrape_interval: 10s
    metrics_path: /metrics

  # HAProxy metrics (if HAProxy stats are enabled)
  - job_name: 'haproxy'
    static_configs:
      - targets: ['localhost:80']
    metrics_path: /stats
    params:
      stats: ['']
    scrape_interval: 15s

  # Service A health checks
  - job_name: 'service-a'
    static_configs:
      - targets: ['${GCP_SERVER_IP}:8080']
    metrics_path: /health
    scrape_interval: 30s

  # Service B health checks  
  - job_name: 'service-b'
    static_configs:
      - targets: ['${GCP_SERVER_IP}:8081']
    metrics_path: /health
    scrape_interval: 30s

  # Node Exporter on GCP (if installed)
  - job_name: 'node-exporter-gcp'
    static_configs:
      - targets: ['${GCP_SERVER_IP}:9100']
    scrape_interval: 15s
EOF

    log_info "Prometheus configuration created"
}

# Function to create Prometheus alert rules
create_alert_rules() {
    log_step "Creating Prometheus alert rules..."
    
    mkdir -p monitoring/prometheus/config/rules
    
    cat > monitoring/prometheus/config/rules/container_alerts.yml <<EOF
groups:
  - name: container_alerts
    rules:
      # Alert when container restarts exceed threshold
      - alert: HighContainerRestarts
        expr: increase(container_start_time_seconds[10m]) > ${CONTAINER_RESTART_THRESHOLD}
        for: 1m
        labels:
          severity: warning
          service: containers
        annotations:
          summary: "High container restart rate detected"
          description: "Container {{ \$labels.name }} has restarted {{ \$value }} times in the last 10 minutes (threshold: ${CONTAINER_RESTART_THRESHOLD})"

      # Alert when container is down
      - alert: ContainerDown
        expr: up{job=~"service-.*"} == 0
        for: 2m
        labels:
          severity: critical
          service: containers
        annotations:
          summary: "Container is down"
          description: "Container {{ \$labels.job }} is not responding to health checks"

      # Alert when Docker daemon is unreachable
      - alert: DockerDaemonDown
        expr: up{job=~"docker-.*"} == 0
        for: 5m
        labels:
          severity: critical
          service: docker
        annotations:
          summary: "Docker daemon unreachable"
          description: "Docker daemon on {{ \$labels.instance }} is not responding"

      # Alert when container memory usage is high
      - alert: HighContainerMemoryUsage
        expr: (container_memory_usage_bytes / container_spec_memory_limit_bytes) * 100 > 80
        for: 5m
        labels:
          severity: warning
          service: containers
        annotations:
          summary: "High container memory usage"
          description: "Container {{ \$labels.name }} memory usage is {{ \$value }}%"

      # Alert when container CPU usage is high
      - alert: HighContainerCPUUsage
        expr: rate(container_cpu_usage_seconds_total[5m]) * 100 > 80
        for: 5m
        labels:
          severity: warning
          service: containers
        annotations:
          summary: "High container CPU usage" 
          description: "Container {{ \$labels.name }} CPU usage is {{ \$value }}%"
EOF

    log_info "Alert rules created"
}

# Function to create Grafana configuration
create_grafana_config() {
    log_step "Creating Grafana configuration..."
    
    # Datasource configuration
    cat > monitoring/grafana/provisioning/datasources/prometheus.yml <<EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
EOF

    # Dashboard provisioning
    cat > monitoring/grafana/provisioning/dashboards/dashboard.yml <<EOF
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF

    log_info "Grafana configuration created"
}

# Function to create Grafana dashboard
create_grafana_dashboard() {
    log_step "Creating Grafana dashboard..."
    
    cat > monitoring/grafana/dashboards/container_monitoring.json <<'EOF'
{
  "dashboard": {
    "id": null,
    "title": "Container Monitoring Dashboard",
    "tags": ["docker", "containers"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Container Restart Rate",
        "type": "stat",
        "targets": [
          {
            "expr": "increase(container_start_time_seconds[10m])",
            "legendFormat": "{{ name }}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {
              "mode": "thresholds"
            },
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 2},
                {"color": "red", "value": 3}
              ]
            }
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "Container Status",
        "type": "stat",
        "targets": [
          {
            "expr": "up{job=~\"service-.*\"}",
            "legendFormat": "{{ job }}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {
              "mode": "thresholds"
            },
            "thresholds": {
              "steps": [
                {"color": "red", "value": null},
                {"color": "green", "value": 1}
              ]
            }
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      },
      {
        "id": 3,
        "title": "Container Memory Usage",
        "type": "timeseries",
        "targets": [
          {
            "expr": "(container_memory_usage_bytes / container_spec_memory_limit_bytes) * 100",
            "legendFormat": "{{ name }}"
          }
        ],
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 8}
      },
      {
        "id": 4,
        "title": "Container CPU Usage",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rate(container_cpu_usage_seconds_total[5m]) * 100",
            "legendFormat": "{{ name }}"
          }
        ],
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 16}
      }
    ],
    "time": {
      "from": "now-1h",
      "to": "now"
    },
    "refresh": "5s"
  }
}
EOF

    log_info "Grafana dashboard created"
}

# Function to create Docker Compose for monitoring stack
create_monitoring_compose() {
    log_step "Creating monitoring Docker Compose..."
    
    cat > monitoring/docker-compose.yml <<EOF
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "${PROMETHEUS_PORT}:9090"
    volumes:
      - ./prometheus/config:/etc/prometheus
      - ./prometheus/data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
      - '--web.enable-admin-api'
    restart: unless-stopped
    networks:
      - monitoring
    extra_hosts:
      - "host.docker.internal:host-gateway"

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "${GRAFANA_PORT}:3000"
    volumes:
      - ./grafana/data:/var/lib/grafana
      - ./grafana/dashboards:/var/lib/grafana/dashboards
      - ./grafana/provisioning:/etc/grafana/provisioning
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource
    restart: unless-stopped
    networks:
      - monitoring
    depends_on:
      - prometheus

networks:
  monitoring:
    driver: bridge

volumes:
  prometheus-data:
  grafana-data:
EOF

    log_info "Monitoring Docker Compose created"
}

# Function to configure firewall
configure_firewall() {
    log_step "Configuring firewall for monitoring..."
    
    # Check if ufw is active
    if sudo ufw status | grep -q "Status: active"; then
        sudo ufw allow ${PROMETHEUS_PORT}/tcp
        sudo ufw allow ${GRAFANA_PORT}/tcp
        log_info "UFW firewall rules added for Prometheus (${PROMETHEUS_PORT}) and Grafana (${GRAFANA_PORT})"
    else
        log_info "UFW is not active, skipping UFW configuration"
    fi
    
    # For systems using iptables directly
    if command -v iptables &> /dev/null; then
        sudo iptables -I INPUT -p tcp --dport ${PROMETHEUS_PORT} -j ACCEPT
        sudo iptables -I INPUT -p tcp --dport ${GRAFANA_PORT} -j ACCEPT
        log_info "iptables rules added for monitoring ports"
    fi
}

# Function to start monitoring stack
start_monitoring() {
    log_step "Starting monitoring stack..."
    
    cd monitoring
    
    # Set proper permissions for data directories
    sudo chown -R 472:472 grafana/data  # Grafana user ID
    sudo chown -R 65534:65534 prometheus/data  # Prometheus user ID
    
    # Start the monitoring stack
    ${COMPOSE_CMD} up -d
    
    # Wait for services to start
    log_info "Waiting for services to start..."
    sleep 15
    
    # Check if services are running
    if ${COMPOSE_CMD} ps | grep -q "Up"; then
        log_info "✓ Monitoring services are running"
    else
        log_error "✗ Failed to start monitoring services"
        ${COMPOSE_CMD} logs
        exit 1
    fi
    
    cd ..
}

# Function to verify monitoring setup
verify_monitoring() {
    log_step "Verifying monitoring setup..."
    
    local aws_ip=$(hostname -I | awk '{print $1}')
    
    # Test Prometheus
    if curl -f -s "http://localhost:${PROMETHEUS_PORT}/-/healthy" > /dev/null; then
        log_info "✓ Prometheus is healthy"
    else
        log_warn "✗ Prometheus health check failed"
    fi
    
    # Test Grafana
    if curl -f -s "http://localhost:${GRAFANA_PORT}/api/health" > /dev/null; then
        log_info "✓ Grafana is healthy"
    else
        log_warn "✗ Grafana health check failed"
    fi
    
    # Show access URLs
    echo
    log_info "Monitoring services are accessible at:"
    echo "  Prometheus: http://${aws_ip}:${PROMETHEUS_PORT}"
    echo "  Grafana:    http://${aws_ip}:${GRAFANA_PORT} (admin/admin)"
}

# Function to show final status
show_final_status() {
    local aws_ip=$(hostname -I | awk '{print $1}')
    
    echo
    echo "================================"
    log_info "Monitoring Setup Complete!"
    echo "================================"
    echo "Services:"
    echo "  Prometheus: http://${aws_ip}:${PROMETHEUS_PORT}"
    echo "  Grafana:    http://${aws_ip}:${GRAFANA_PORT}"
    echo
    echo "Default Credentials:"
    echo "  Grafana: admin / admin"
    echo
    echo "Configuration:"
    echo "  Container restart threshold: ${CONTAINER_RESTART_THRESHOLD} per 10 minutes"
    echo "  Monitoring targets:"
    echo "    - Docker engines (AWS + GCP)"
    echo "    - Container metrics (cAdvisor)"
    echo "    - Service health checks"
    echo "    - HAProxy metrics"
    echo
    echo "Next Steps:"
    echo "1. Visit Grafana dashboard"
    echo "2. Import the Container Monitoring dashboard"
    echo "3. Configure additional alert channels (email, Slack, etc.)"
    echo "4. Set up GCP Docker metrics (see setup-gcp-monitoring.sh)"
    echo
    echo "Management Commands:"
    echo "  Start:    cd monitoring && ${COMPOSE_CMD} up -d"
    echo "  Stop:     cd monitoring && ${COMPOSE_CMD} down"
    echo "  Logs:     cd monitoring && ${COMPOSE_CMD} logs -f"
    echo "  Restart:  cd monitoring && ${COMPOSE_CMD} restart"
    echo "================================"
}

# Main execution
main() {
    log_info "Setting up Prometheus and Grafana monitoring..."
    
    # Check prerequisites
    check_prerequisites
    
    # Create directory structure
    create_directories
    
    # Create configuration files
    create_prometheus_config
    create_alert_rules
    create_grafana_config
    create_grafana_dashboard
    create_monitoring_compose
    
    # Configure firewall
    configure_firewall
    
    # Start monitoring stack
    start_monitoring
    
    # Verify setup
    verify_monitoring
    
    # Show final status
    show_final_status
    
    log_info "Monitoring setup completed successfully!"
}

# Run main function
main "$@"
