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
