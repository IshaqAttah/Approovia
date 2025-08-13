#!/bin/bash
set -e

echo " Deploying Custom Grafana Dashboard"
echo "====================================="

# Get connection details
KEY_WG1=$(vagrant ssh-config wg1 | awk '/IdentityFile/ {print $2}')
IP_WG1=$(vagrant ssh-config wg1 | awk '/HostName/ {print $2}')
USER_WG1=$(vagrant ssh-config wg1 | awk '/User / {print $2}')

echo "Deploying dashboard to Grafana on: $IP_WG1:3000"

# Deploy the dashboard via Grafana API
deploy_dashboard() {
    echo " Uploading dashboard via Grafana API..."
    
    # Dashboard JSON content
    DASHBOARD_JSON='{
  "dashboard": {
    "id": null,
    "uid": "container_monitoring",
    "title": "Container Monitoring Dashboard",
    "tags": ["docker", "monitoring", "containers"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Container Restarts (10min window)",
        "type": "timeseries",
        "targets": [
          {
            "expr": "increase(engine_daemon_container_states_containers{state=\"restarting\"}[10m])",
            "legendFormat": "Restarts - {{instance}}",
            "refId": "A"
          }
        ],
        "alert": {
          "conditions": [
            {
              "evaluator": {
                "params": [2],
                "type": "gt"
              },
              "operator": {
                "type": "and"
              },
              "query": {
                "params": ["A", "10m", "now"]
              },
              "reducer": {
                "params": [],
                "type": "last"
              },
              "type": "query"
            }
          ],
          "executionErrorState": "alerting",
          "for": "1m",
          "frequency": "10s",
          "handler": 1,
          "name": "High Container Restarts Alert",
          "noDataState": "no_data"
        },
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 0,
          "y": 0
        },
        "fieldConfig": {
          "defaults": {
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"color": "green", "value": null},
                {"color": "red", "value": 2}
              ]
            }
          }
        }
      },
      {
        "id": 2,
        "title": "Running Containers",
        "type": "timeseries",
        "targets": [
          {
            "expr": "engine_daemon_container_states_containers{state=\"running\"}",
            "legendFormat": "Running - {{instance}}",
            "refId": "A"
          }
        ],
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 12,
          "y": 0
        }
      },
      {
        "id": 3,
        "title": "Container States Overview",
        "type": "timeseries",
        "targets": [
          {
            "expr": "engine_daemon_container_states_containers",
            "legendFormat": "{{state}} - {{instance}}",
            "refId": "A"
          }
        ],
        "gridPos": {
          "h": 8,
          "w": 24,
          "x": 0,
          "y": 8
        }
      },
      {
        "id": 4,
        "title": "Docker Daemon Health",
        "type": "stat",
        "targets": [
          {
            "expr": "up{job=~\"docker-.*\"}",
            "legendFormat": "{{instance}}",
            "refId": "A"
          }
        ],
        "gridPos": {
          "h": 4,
          "w": 24,
          "x": 0,
          "y": 16
        },
        "fieldConfig": {
          "defaults": {
            "mappings": [
              {
                "options": {
                  "0": {"color": "red", "index": 1, "text": "DOWN"},
                  "1": {"color": "green", "index": 0, "text": "UP"}
                },
                "type": "value"
              }
            ]
          }
        }
      }
    ],
    "time": {
      "from": "now-30m",
      "to": "now"
    },
    "refresh": "5s"
  },
  "overwrite": true
}'
    
    # Deploy via Grafana API
    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -u "admin:admin123" \
        -d "$DASHBOARD_JSON" \
        http://$IP_WG1:3000/api/dashboards/db)
    
    if echo "$RESPONSE" | grep -q '"status":"success"'; then
        echo " Dashboard deployed successfully"
        DASHBOARD_URL=$(echo "$RESPONSE" | jq -r '.url' 2>/dev/null || echo "/d/container_monitoring")
        echo " Dashboard URL: http://$IP_WG1:3000$DASHBOARD_URL"
    else
        echo " Dashboard deployment failed"
        echo "Response: $RESPONSE"
        return 1
    fi
}

# Alternative: Deploy via file system
deploy_dashboard_file() {
    echo " Deploying dashboard via file system..."
    
    ssh -i "$KEY_WG1" -o StrictHostKeyChecking=no $USER_WG1@$IP_WG1 << 'EOF'
    
    # Ensure dashboard directory exists
    sudo mkdir -p /opt/monitoring/grafana/dashboards
    
    # Create the dashboard file
    sudo tee /opt/monitoring/grafana/dashboards/container-monitoring.json > /dev/null << 'DASHBOARD_EOF'
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": "-- Grafana --",
        "enable": true,
        "hide": true,
        "iconColor": "rgba(0, 211, 255, 1)",
        "name": "Annotations & Alerts",
        "type": "dashboard"
      }
    ]
  },
  "editable": true,
  "gnetId": null,
  "graphTooltip": 0,
  "id": null,
  "links": [],
  "panels": [
    {
      "alert": {
        "alertRuleTags": {},
        "conditions": [
          {
            "evaluator": {
              "params": [2],
              "type": "gt"
            },
            "operator": {
              "type": "and"
            },
            "query": {
              "params": ["A", "10m", "now"]
            },
            "reducer": {
              "params": [],
              "type": "last"
            },
            "type": "query"
          }
        ],
        "executionErrorState": "alerting",
        "for": "1m",
        "frequency": "10s",
        "handler": 1,
        "name": "Container Restart Alert",
        "noDataState": "no_data",
        "notifications": []
      },
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {"color": "green", "value": null},
              {"color": "red", "value": 2}
            ]
          },
          "unit": "short"
        }
      },
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
      "id": 1,
      "targets": [
        {
          "expr": "increase(engine_daemon_container_states_containers{state=\"restarting\"}[10m])",
          "legendFormat": "Container Restarts - {{instance}}",
          "refId": "A"
        }
      ],
      "title": "Container Restarts (10min)",
      "type": "timeseries"
    },
    {
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {"color": "green", "value": null},
              {"color": "yellow", "value": 1},
              {"color": "red", "value": 2}
            ]
          }
        }
      },
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
      "id": 2,
      "options": {
        "colorMode": "value",
        "graphMode": "area",
        "justifyMode": "auto",
        "orientation": "auto",
        "reduceOptions": {
          "calcs": ["lastNotNull"],
          "fields": "",
          "values": false
        }
      },
      "targets": [
        {
          "expr": "increase(engine_daemon_container_states_containers{state=\"restarting\"}[10m])",
          "legendFormat": "{{instance}}",
          "refId": "A"
        }
      ],
      "title": "Current Restart Count (10min window)",
      "type": "stat"
    },
    {
      "datasource": "Prometheus",
      "gridPos": {"h": 8, "w": 24, "x": 0, "y": 8},
      "id": 3,
      "targets": [
        {
          "expr": "engine_daemon_container_states_containers{state=\"running\"}",
          "legendFormat": "Running Containers - {{instance}}",
          "refId": "A"
        }
      ],
      "title": "Running Containers",
      "type": "timeseries"
    }
  ],
  "refresh": "5s",
  "schemaVersion": 27,
  "style": "dark",
  "tags": ["docker", "monitoring", "containers"],
  "templating": {"list": []},
  "time": {"from": "now-30m", "to": "now"},
  "timepicker": {},
  "timezone": "",
  "title": "Container Monitoring Dashboard",
  "uid": "container_monitoring",
  "version": 1
}
DASHBOARD_EOF
    
    # Set proper permissions
    sudo chown 472:472 /opt/monitoring/grafana/dashboards/container-monitoring.json
    
    # Restart Grafana to pick up the dashboard
    cd /opt/monitoring
    sudo docker-compose restart grafana
    
    echo " Dashboard file created and Grafana restarted"
    
EOF
}

# Main deployment function
main() {
    echo " Starting dashboard deployment..."
    
    # Wait for Grafana to be ready
    echo "⏱️  Waiting for Grafana to be ready..."
    for i in {1..30}; do
        if curl -s http://$IP_WG1:3000/api/health | grep -q '"status":"ok"'; then
            echo " Grafana is ready"
            break
        fi
        echo "Waiting... ($i/30)"
        sleep 2
    done
    
    # Try API deployment first, fallback to file deployment
    if deploy_dashboard; then
        echo " Dashboard deployed via API"
    else
        echo "️  API deployment failed, trying file deployment..."
        deploy_dashboard_file
    fi
    
    echo ""
    echo " Dashboard deployment completed!"
    echo ""
    echo " Access your dashboard:"
    echo "   Grafana: http://$IP_WG1:3000"
    echo "   Login: admin / admin123"
    echo "   Dashboard: Container Monitoring Dashboard"
    echo ""
    echo " Test the alerts:"
    echo "   Run: ./test-monitoring-alerts.sh"
    echo ""
    echo " Monitor these metrics:"
    echo "   • Container restarts (alert when >2 in 10min)"
    echo "   • Running container count"
    echo "   • Docker daemon health"
    echo "   • System resource usage"
}

# Run the deployment
main
