# Multi-Cloud DevOps Infrastructure

A complete containerized microservices deployment across AWS and GCP with automated CI/CD, load balancing, and monitoring.

## What This Project Includes

- **Multi-Cloud Setup** – AWS server (HAProxy + Monitoring) and GCP server (Services)
- **Containerized Services** – Two Go microservices (Service A & Service B)
- **Load Balancing** – HAProxy with path-based routing
- **CI/CD Pipeline** – Drone CI configuration for automated deployment
- **Monitoring** – Prometheus + Grafana with container restart alerting
- **Secure Networking** – WireGuard VPN tunnel connecting AWS and GCP

## Infrastructure Overview

```
Internet → AWS Server (Load Balancer + Monitoring) → WireGuard → GCP Server (Services)
          ├── HAProxy (:80)                                    ├── Service A (:8080)
          ├── Docker Registry (:5000)                          ├── Service B (:8081)
          ├── Prometheus (:9090)                               ├── cAdvisor (:8082)
          └── Grafana (:3000)                                  └── Node Exporter (:9100)
```

## How to Deploy Everything

### Step 1 – Deploy Docker Services

```bash
# Build and deploy microservices to GCP
./deploy.sh
```

**Test Services Directly:**

```bash
curl http://34.88.69.228:8080  # Service A
curl http://34.88.69.228:8081  # Service B
```

### Step 2 – Setup Load Balancer

```bash
# Configure HAProxy on AWS server
./deploy-haproxy.sh
```

**Test via Load Balancer:**

```bash
curl http://13.51.108.204/service-a
curl http://13.51.108.204/service-b
```

### Step 3 – Setup CI/CD Pipeline

```bash
# Install Drone CI locally
./setup-drone.sh

# Access Drone at http://localhost:3000
```

### Step 4 – Setup Monitoring

```bash
# Deploy monitoring across both servers
./deploy-monitoring.sh
```

**This will:**

- Install cAdvisor, Node Exporter on GCP
- Install Prometheus, Grafana on AWS
- Configure container restart alerts (>3 restarts per 10 minutes)

## Access Your Infrastructure

| Service           | URL                            | Login       |
| ----------------- | ------------------------------ | ----------- |
| **Service A**     | http://13.51.108.204/service-a | None        |
| **Service B**     | http://13.51.108.204/service-b | None        |
| **HAProxy Stats** | http://13.51.108.204/stats     | None        |
| **Prometheus**    | http://13.51.108.204:9090      | None        |
| **Grafana**       | http://13.51.108.204:3000      | admin/admin |
| **Drone CI**      | http://localhost:3000          | admin       |

## Key Features

### Load Balancing

- **Path-based routing**: `/service-a` and `/service-b`
- **Health checks**: Automatic backend monitoring
- **High availability**: Multiple service instances

### Monitoring & Alerting

- **Container metrics**: Memory, CPU, restart counts
- **System metrics**: Host resources and performance
- **Alerting**: Email/Slack notifications when containers restart frequently
- **Dashboards**: Real-time visualization in Grafana

### CI/CD Pipeline

- **Automated testing**: Unit tests for both services
- **Docker builds**: Cross-platform image creation
- **Automated deployment**: Push-to-deploy workflow
- **Multi-cloud**: Deploys across AWS and GCP automatically

## Quick Health Check

```bash
# Test load balancer
curl http://13.51.108.204/service-a
curl http://13.51.108.204/service-b

# Test monitoring
curl http://13.51.108.204:9090/-/healthy  # Prometheus
curl http://13.51.108.204:3000/api/health # Grafana

# Test direct services
curl http://34.88.69.228:8080  # Service A
curl http://34.88.69.228:8081  # Service B
```

## Testing Container Restart Monitoring

```bash
# SSH to GCP and restart containers to test alerts
ssh -i ~/.ssh/id_rsa ishaq.musa@34.88.69.228
docker restart service-a
docker restart service-b
docker restart service-a
docker restart service-b

# Check Prometheus for restart metrics
# Query: increase(container_start_time_seconds[10m])
```

## Troubleshooting

### Services Not Accessible

```bash
# Check containers on GCP
ssh -i ~/.ssh/id_rsa ishaq.musa@34.88.69.228
docker ps
docker logs service-a
docker logs service-b
```

### HAProxy Returns 503

```bash
# Check HAProxy on AWS
ssh -i ~/Downloads/app-key-pair.pem ubuntu@13.51.108.204
sudo systemctl status haproxy
sudo systemctl restart haproxy
```

### Monitoring Not Working

```bash
# Check monitoring services on AWS
ssh -i ~/Downloads/app-key-pair.pem ubuntu@13.51.108.204
cd monitoring
docker compose ps
docker compose logs prometheus
docker compose logs grafana
```

### Docker Registry Issues

```bash
# Check registry on AWS
curl http://13.51.108.204:5000/v2/_catalog
ssh -i ~/Downloads/app-key-pair.pem ubuntu@13.51.108.204
docker ps | grep registry
```

## Server Information

### AWS Server (13.51.108.204)

- **SSH**:
- **Services**: HAProxy, Docker Registry, Prometheus, Grafana
- **Security Group**: Ports 22, 80, 3000, 5000, 9090 open

### GCP Server (34.88.69.228)

- **SSH**:
- **Services**: Service A, Service B, cAdvisor, Node Exporter
- **Firewall**: Ports 8080, 8081, 8082, 9100, 9323 open

## Complete Reset

```bash
# Redeploy everything from scratch
./deploy.sh                 # Deploy services
./deploy-haproxy.sh        # Setup load balancer
./deploy-monitoring.sh     # Setup monitoring
```

## Success Criteria

Both servers are accessible via SSH  
Services respond through load balancer  
Grafana shows container metrics  
Alerts trigger when containers restart >3 times in 10 minutes  
Docker registry stores and serves images  
WireGuard tunnel connects AWS and GCP securely
