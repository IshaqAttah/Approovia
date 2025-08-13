k#!/bin/bash
set -e

echo "📊 Setting up Prometheus & Grafana Monitoring Stack"
echo "=================================================="

# Get connection details
KEY_WG1=$(vagrant ssh-config wg1 | awk '/IdentityFile/ {print $2}')
KEY_WG2=$(vagrant ssh-config wg2 | awk '/IdentityFile/ {print $2}')
KEY_WG3=$(vagrant ssh-config wg3 | awk '/IdentityFile/ {print $2}')
IP_WG1=$(vagrant ssh-config wg1 | awk '/HostName/ {print $2}')
IP_WG2=$(vagrant ssh-config wg2 | awk '/HostName/ {print $2}')
IP_WG3=$(vagrant ssh-config wg3 | awk '/HostName/ {print $2}')
USER_WG1=$(vagrant ssh-config wg1 | awk '/User / {print $2}')
USER_WG2=$(vagrant ssh-config wg2 | awk '/User / {print $2}')
USER_WG3=$(vagrant ssh-config wg3 | awk '/User / {print $2}')

echo "📋 Monitoring Stack will be deployed on:"
echo "   Prometheus: $IP_WG1:9090"
echo "   Grafana: $IP_WG1:3000"
echo "   Monitoring targets: wg1, wg2, wg3"

# Step 1: Configure Docker daemon for metrics on all VMs
echo ""
echo "🐳 Step 1: Configuring Docker daemon metrics on all VMs..."

configure_docker_metrics() {
    local vm_key=$1
    local vm_ip=$2
    local vm_user=$3
    local vm_name=$4
    
    echo "Configuring Docker metrics on $vm_name ($vm_ip)..."
    
    ssh -i "$vm_key" -o StrictHostKeyChecking=no $vm_user@$vm_ip << EOF
    # Configure Docker daemon for metrics
    sudo mkdir -p /etc/docker
    
    # Create or update daemon.json with metrics configuration
    if [ -f /etc/docker/daemon.json ]; then
        # Backup existing config
        sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.backup
        
        # Merge with existing config (using dynamic IP)
        sudo tee /etc/docker/daemon.json > /dev/null << 'DOCKER_CONFIG'
{
  "insecure-registries": ["$IP_WG1:5000"],
  "metrics-addr": "0.0.0.0:9323",
  "experimental": true
}
DOCKER_CONFIG
    else
        # Create new config
        sudo tee /etc/docker/daemon.json > /dev/null << 'DOCKER_CONFIG'
{
  "insecure-registries": ["$IP_WG1:5000"],
  "metrics-addr": "0.0.0.0:9323",
  "experimental": true
}
DOCKER_CONFIG
    fi
    
    # Restart Docker daemon
    sudo systemctl restart docker
    
    # Wait for Docker to restart
    sleep 5
    
    # Verify metrics endpoint
    curl -s http://localhost:9323/metrics | head -5 || echo "Metrics endpoint not yet ready"
    
    echo "✅ Docker metrics configured on \$(hostname)"
EOF
}

# Configure Docker metrics on all VMs
configure_docker_metrics "$KEY_WG1" "$IP_WG1" "$USER_WG1" "wg1"
configure_docker_metrics "$KEY_WG2" "$IP_WG2" "$USER_WG2" "wg2"
configure_docker_metrics "$KEY_WG3" "$IP_WG3" "$USER_WG3" "wg3"

# Step 2: Install Node Exporter on all VMs for system metrics
echo ""
echo "📈 Step 2: Installing Node Exporter on all VMs..."

install_node_exporter() {
    local vm_key=$1
    local vm_ip=$2
    local vm_user=$3
    local vm_name=$4
    
    echo "Installing Node Exporter on $vm_name..."
    
    ssh -i "$vm_key" -o StrictHostKeyChecking=no $vm_user@$vm_ip << 'EOF'
    # Download and install Node Exporter
    NODE_EXPORTER_VERSION="1.6.1"
    
    # Download Node Exporter
    cd /tmp
    wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
    tar xf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
    
    # Install Node Exporter
    sudo mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
    sudo chmod +x /usr/local/bin/node_exporter
    
    # Create node_exporter user
    sudo useradd --no-create-home --shell /bin/false node_exporter || true
    
    # Create systemd service
    sudo tee /etc/systemd/system/node_exporter.service > /dev/null << 'SERVICE_EOF'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
SERVICE_EOF
    
    # Start and enable Node Exporter
    sudo systemctl daemon-reload
    sudo systemctl enable node_exporter
    sudo systemctl start node_exporter
    
    # Verify it's running
    sleep 3
    sudo systemctl status node_exporter --no-pager
    
    echo "✅ Node Exporter installed on $(hostname)"
EOF
}

# Install Node Exporter on all VMs
install_node_exporter "$KEY_WG1" "$IP_WG1" "$USER_WG1" "wg1"
install_node_exporter "$KEY_WG2" "$IP_WG2" "$USER_WG2" "wg2"
install_node_exporter "$KEY_WG3" "$IP_WG3" "$USER_WG3" "wg3"

# Step 3: Set up Prometheus and Grafana on wg1
echo ""
echo "📊 Step 3: Setting up Prometheus and Grafana on wg1..."

ssh -i "$KEY_WG1" -o StrictHostKeyChecking=no $USER_WG1@$IP_WG1 << EOF

# Create monitoring directory structure
sudo mkdir -p /opt/monitoring/{prometheus,grafana,alertmanager}
sudo mkdir -p /opt/monitoring/prometheus/{data,config}
sudo mkdir -p /opt/monitoring/grafana/{data,dashboards,provisioning}
sudo mkdir -p /opt/monitoring/grafana/provisioning/{dashboards,datasources}

# Set proper permissions
sudo chown -R 472:472 /opt/monitoring/grafana
sudo chown -R 65534:65534 /opt/monitoring/prometheus

# Create Prometheus configuration
sudo tee /opt/monitoring/prometheus/config/prometheus.yml > /dev/null << 'PROM_CONFIG'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "/etc/prometheus/alert_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

scrape_configs:
  # Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Docker Engine metrics
  - job_name: 'docker-wg1'
    static_configs:
      - targets: ['$IP_WG1:9323']
    scrape_interval: 5s
    metrics_path: /metrics

  - job_name: 'docker-wg2'
    static_configs:
      - targets: ['$IP_WG2:9323']
    scrape_interval: 5s
    metrics_path: /metrics

  - job_name: 'docker-wg3'
    static_configs:
      - targets: ['$IP_WG3:9323']
    scrape_interval: 5s
    metrics_path: /metrics

  # Node Exporter for system metrics
  - job_name: 'node-exporter-wg1'
    static_configs:
      - targets: ['$IP_WG1:9100']

  - job_name: 'node-exporter-wg2'
    static_configs:
      - targets: ['$IP_WG2:9100']

  - job_name: 'node-exporter-wg3'
    static_configs:
      - targets: ['$IP_WG3:9100']

  # Application endpoints
  - job_name: 'service-a-wg2'
    static_configs:
      - targets: ['$IP_WG2:8081']
    metrics_path: /metrics
    scrape_interval: 10s

  - job_name: 'service-b-wg2'
    static_configs:
      - targets: ['$IP_WG2:8082']
    metrics_path: /metrics
    scrape_interval: 10s

  - job_name: 'service-a-wg3'
    static_configs:
      - targets: ['$IP_WG3:8081']
    metrics_path: /metrics
    scrape_interval: 10s

  - job_name: 'service-b-wg3'
    static_configs:
      - targets: ['$IP_WG3:8082']
    metrics_path: /metrics
    scrape_interval: 10s

  # HAProxy stats (if available)
  - job_name: 'haproxy'
    static_configs:
      - targets: ['localhost:80']
    metrics_path: /stats
    params:
      stats: ['']
PROM_CONFIG

# Create alert rules for container restarts
sudo tee /opt/monitoring/prometheus/config/alert_rules.yml > /dev/null << 'ALERT_RULES'
groups:
  - name: container_alerts
    rules:
      - alert: HighContainerRestarts
        expr: increase(engine_daemon_container_states_containers{state="restarting"}[10m]) > 2
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "High container restart rate detected"
          description: "Container restart rate has exceeded 2 restarts in 10 minutes on instance {{ \$labels.instance }}"

      - alert: ContainerDown
        expr: engine_daemon_container_states_containers{state="running"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Container is down"
          description: "No running containers detected on {{ \$labels.instance }}"

      - alert: DockerDaemonDown
        expr: up{job=~"docker-.*"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Docker daemon is down"
          description: "Docker daemon on {{ \$labels.instance }} is not responding"

  - name: application_alerts
    rules:
      - alert: ServiceDown
        expr: up{job=~"service-.*"} == 0
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Application service is down"
          description: "Service {{ \$labels.job }} on {{ \$labels.instance }} is not responding"

  - name: system_alerts
    rules:
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"
          description: "CPU usage is above 80% on {{ \$labels.instance }}"

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage detected"
          description: "Memory usage is above 90% on {{ \$labels.instance }}"
ALERT_RULES

# Create Grafana datasource configuration
sudo tee /opt/monitoring/grafana/provisioning/datasources/prometheus.yml > /dev/null << 'DATASOURCE_CONFIG'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
DATASOURCE_CONFIG

# Create Grafana dashboard provisioning configuration
sudo tee /opt/monitoring/grafana/provisioning/dashboards/dashboard.yml > /dev/null << 'DASHBOARD_CONFIG'
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
DASHBOARD_CONFIG

# Create Docker Compose file for monitoring stack
sudo tee /opt/monitoring/docker-compose.yml > /dev/null << 'COMPOSE_CONFIG'
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - /opt/monitoring/prometheus/config:/etc/prometheus
      - /opt/monitoring/prometheus/data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
      - '--web.enable-admin-api'
    networks:
      - monitoring

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - /opt/monitoring/grafana/data:/var/lib/grafana
      - /opt/monitoring/grafana/provisioning:/etc/grafana/provisioning
      - /opt/monitoring/grafana/dashboards:/var/lib/grafana/dashboards
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin123
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource
    networks:
      - monitoring

  alertmanager:
    image: prom/alertmanager:latest
    container_name: alertmanager
    restart: unless-stopped
    ports:
      - "9093:9093"
    volumes:
      - /opt/monitoring/alertmanager:/etc/alertmanager
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--storage.path=/alertmanager'
      - '--web.external-url=http://localhost:9093'
    networks:
      - monitoring

networks:
  monitoring:
    driver: bridge
COMPOSE_CONFIG

# Create Alertmanager configuration
sudo tee /opt/monitoring/alertmanager/alertmanager.yml > /dev/null << 'ALERTMANAGER_CONFIG'
global:
  smtp_smarthost: 'localhost:587'
  smtp_from: 'alertmanager@example.org'

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'web.hook'

receivers:
  - name: 'web.hook'
    webhook_configs:
      - url: 'http://127.0.0.1:5001/'
        send_resolved: true

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'dev', 'instance']
ALERTMANAGER_CONFIG

echo "✅ Monitoring configuration created"

EOF

# Step 4: Start the monitoring stack
echo ""
echo "🚀 Step 4: Starting Prometheus and Grafana..."

ssh -i "$KEY_WG1" -o StrictHostKeyChecking=no $USER_WG1@$IP_WG1 << 'EOF'

# Set proper permissions
sudo chown -R 472:472 /opt/monitoring/grafana
sudo chown -R 65534:65534 /opt/monitoring/prometheus
sudo chown -R 65534:65534 /opt/monitoring/alertmanager

# Start the monitoring stack
cd /opt/monitoring
sudo docker-compose up -d

# Wait for services to start
echo "Waiting for services to start..."
sleep 20

# Check if services are running
sudo docker-compose ps

# Verify Prometheus is scraping targets
echo "Checking Prometheus targets..."
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}' 2>/dev/null || echo "Prometheus targets check will be available shortly"

echo "✅ Monitoring stack started successfully"

EOF

echo ""
echo "🎉 Monitoring Stack Setup Completed!"
echo "===================================="
echo ""
echo "📊 Access Points:"
echo "   Prometheus: http://$IP_WG1:9090"
echo "   Grafana: http://$IP_WG1:3000 (admin:admin123)"
echo "   Alertmanager: http://$IP_WG1:9093"
echo ""
echo "📈 Metrics Available:"
echo "   ✅ Docker Engine metrics from all VMs"
echo "   ✅ Node Exporter system metrics"
echo "   ✅ Container restart alerts configured"
echo "   ✅ Application health monitoring"
echo ""
echo "🔔 Alert Rules Configured:"
echo "   • High container restarts (>2 in 10 minutes)"
echo "   • Container down detection"
echo "   • Docker daemon down detection"
echo "   • Service down detection"
echo "   • High CPU usage (>80%)"
echo "   • High memory usage (>90%)"
echo ""
echo "📝 Next Steps:"
echo "   1. Access Grafana at http://$IP_WG1:3000"
echo "   2. Login with admin:admin123"
echo "   3. Import Docker and system dashboards"
echo "   4. Test alerts by restarting containers"
