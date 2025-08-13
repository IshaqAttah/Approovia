#!/bin/bash
set -e

echo " Testing Container Restart Monitoring & Alerts"
echo "==============================================="

# Get connection details
KEY_WG2=$(vagrant ssh-config wg2 | awk '/IdentityFile/ {print $2}')
KEY_WG3=$(vagrant ssh-config wg3 | awk '/IdentityFile/ {print $2}')
IP_WG1=$(vagrant ssh-config wg1 | awk '/HostName/ {print $2}')
IP_WG2=$(vagrant ssh-config wg2 | awk '/HostName/ {print $2}')
IP_WG3=$(vagrant ssh-config wg3 | awk '/HostName/ {print $2}')
USER_WG2=$(vagrant ssh-config wg2 | awk '/User / {print $2}')
USER_WG3=$(vagrant ssh-config wg3 | awk '/User / {print $2}')

echo " Monitoring endpoints:"
echo "   Prometheus: http://$IP_WG1:9090"
echo "   Grafana: http://$IP_WG1:3000"
echo "   Alertmanager: http://$IP_WG1:9093"

# Function to check if monitoring is working
check_monitoring() {
    echo ""
    echo "🔍 Checking monitoring stack health..."
    
    # Check Prometheus
    if curl -s http://$IP_WG1:9090/api/v1/query?query=up | grep -q '"status":"success"'; then
        echo " Prometheus is responding"
    else
        echo " Prometheus is not responding"
        return 1
    fi
    
    # Check Grafana
    if curl -s http://$IP_WG1:3000/api/health | grep -q '"status":"ok"'; then
        echo " Grafana is responding"
    else
        echo " Grafana is not responding"
        return 1
    fi
    
    # Check targets
    echo " Current monitoring targets:"
    curl -s http://$IP_WG1:9090/api/v1/targets | jq -r '.data.activeTargets[] | "\(.labels.job): \(.labels.instance) - \(.health)"' 2>/dev/null || echo "Target status will be available shortly"
}

# Function to trigger container restarts
trigger_restarts() {
    local vm_key=$1
    local vm_ip=$2
    local vm_user=$3
    local vm_name=$4
    local restart_count=${5:-3}
    
    echo ""
    echo " Triggering $restart_count container restarts on $vm_name..."
    
    ssh -i "$vm_key" -o StrictHostKeyChecking=no $vm_user@$vm_ip << EOF
    echo "Current containers on $vm_name:"
    sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo ""
    echo "Triggering container restarts..."
    
    for i in \$(seq 1 $restart_count); do
        echo "Restart \$i/$restart_count:"
        
        # Restart service-a
        echo "  Restarting service-a..."
        sudo docker restart service-a
        sleep 2
        
        # Restart service-b  
        echo "  Restarting service-b..."
        sudo docker restart service-b
        sleep 3
        
        echo "  Restart \$i completed"
    done
    
    echo ""
    echo "Final container status on $vm_name:"
    sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
EOF
}

# Function to check alerts
check_alerts() {
    echo ""
    echo " Checking for triggered alerts..."
    
    # Wait a moment for metrics to be scraped
    sleep 15
    
    # Check Prometheus alerts
    echo " Current Prometheus alerts:"
    curl -s http://$IP_WG1:9090/api/v1/alerts | jq -r '.data.alerts[] | "Alert: \(.labels.alertname) - State: \(.state) - Instance: \(.labels.instance)"' 2>/dev/null || echo "No alerts or alerts API not accessible"
    
    # Check container restart metrics
    echo ""
    echo " Container restart metrics (last 10 minutes):"
    curl -s "http://$IP_WG1:9090/api/v1/query?query=increase(engine_daemon_container_states_containers{state=\"restarting\"}[10m])" | jq -r '.data.result[] | "Instance: \(.metric.instance) - Restarts: \(.value[1])"' 2>/dev/null || echo "Restart metrics not yet available"
    
    # Check running containers
    echo ""
    echo "  Currently running containers:"
    curl -s "http://$IP_WG1:9090/api/v1/query?query=engine_daemon_container_states_containers{state=\"running\"}" | jq -r '.data.result[] | "Instance: \(.metric.instance) - Running: \(.value[1])"' 2>/dev/null || echo "Container metrics not yet available"
}

# Function to create Grafana dashboard
create_dashboard() {
    echo ""
    echo " Creating Grafana dashboard..."
    
    # Create dashboard directory on wg1
    ssh -i "$(vagrant ssh-config wg1 | awk '/IdentityFile/ {print $2}')" -o StrictHostKeyChecking=no vagrant@$IP_WG1 << 'EOF'
    sudo mkdir -p /opt/monitoring/grafana/dashboards
    
    # Create container monitoring dashboard
    sudo tee /opt/monitoring/grafana/dashboards/container-monitoring.json > /dev/null << 'DASHBOARD_EOF'
{
  "dashboard": {
    "id": null,
    "title": "Container Monitoring Dashboard",
    "tags": ["docker", "monitoring"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Container Restarts (10min)",
        "type": "graph",
        "targets": [
          {
            "expr": "increase(engine_daemon_container_states_containers{state=\"restarting\"}[10m])",
            "legendFormat": "{{instance}}"
          }
        ],
        "yAxes": [
          {
            "label": "Restarts",
            "min": 0
          }
        ],
        "alert": {
          "conditions": [
            {
              "query": {
                "queryType": "",
                "refId": "A"
              },
              "reducer": {
                "type": "last",
                "params": []
              },
              "evaluator": {
                "params": [2],
                "type": "gt"
              }
            }
          ],
          "executionErrorState": "alerting",
          "for": "1m",
          "frequency": "10s",
          "handler": 1,
          "name": "High Container Restarts",
          "noDataState": "no_data"
        },
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 0,
          "y": 0
        }
      },
      {
        "id": 2,
        "title": "Running Containers",
        "type": "graph",
        "targets": [
          {
            "expr": "engine_daemon_container_states_containers{state=\"running\"}",
            "legendFormat": "{{instance}}"
          }
        ],
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 12,
          "y": 0
        }
      }
    ],
    "time": {
      "from": "now-30m",
      "to": "now"
    },
    "refresh": "5s"
  }
}
DASHBOARD_EOF

    echo " Dashboard configuration created"
EOF
}

# Main test sequence
main() {
    echo "Starting monitoring test sequence..."
    
    # Step 1: Check monitoring health
    check_monitoring
    
    # Step 2: Create dashboard
    create_dashboard
    
    # Step 3: Show current baseline
    echo ""
    echo " Current baseline metrics:"
    check_alerts
    
    # Step 4: Trigger restarts on wg2 (should trigger alert)
    trigger_restarts "$KEY_WG2" "$IP_WG2" "$USER_WG2" "wg2" 4
    
    # Step 5: Check for alerts
    echo ""
    echo "️  Waiting for metrics to be scraped and alerts to trigger..."
    sleep 30
    check_alerts
    
    # Step 6: Trigger more restarts on wg3 
    trigger_restarts "$KEY_WG3" "$IP_WG3" "$USER_WG3" "wg3" 3
    
    # Step 7: Final check
    echo ""
    echo "️  Final check after all restarts..."
    sleep 30
    check_alerts
    
    # Step 8: Test recovery
    echo ""
    echo " Testing recovery - ensuring all services are healthy..."
    
    # Wait for services to stabilize
    sleep 20
    
    # Test all services via HAProxy
    echo "Testing services via HAProxy:"
    if curl -f http://$IP_WG1/service-a; then
        echo " Service A accessible via HAProxy"
    else
        echo " Service A not accessible via HAProxy"
    fi
    
    if curl -f http://$IP_WG1/service-b; then
        echo " Service B accessible via HAProxy"
    else
        echo " Service B not accessible via HAProxy"
    fi
    
    echo ""
    echo " Monitoring test completed!"
    echo ""
    echo " View results in:"
    echo "   Prometheus: http://$IP_WG1:9090/alerts"
    echo "   Grafana: http://$IP_WG1:3000 (admin:admin123)"
    echo "   Alertmanager: http://$IP_WG1:9093"
    echo ""
    echo " To import the dashboard in Grafana:"
    echo "   1. Go to http://$IP_WG1:3000"
    echo "   2. Login with admin:admin123"
    echo "   3. Go to + > Import"
    echo "   4. Upload the container-monitoring-dashboard.json file"
}

# Check if monitoring stack is available first
if ! curl -s http://$IP_WG1:9090/api/v1/query?query=up >/dev/null 2>&1; then
    echo " Monitoring stack not available. Please run ./setup-monitoring-stack.sh first"
    exit 1
fi

# Run the test
main
