Complete DevOps Infrastructure Setup
A containerized microservices deployment platform with automated CI/CD, load balancing, and monitoring.
What This Project Includes
Multi-VM Setup: 3 VMs (wg1, wg2, wg3) with Vagrant
Containerized Services: Docker-based Go microservices
Load Balancing: HAProxy with SSL and health checks
CI/CD Pipeline: Drone CI with automated deployment
Monitoring: Prometheus + Grafana with alerting
How to Run Everything
Step 1: Start VMs

# Start all VMs

vagrant up

# Verify VMs are running

vagrant status

Step 2: Deploy Docker Services
cd into Approovia folder
#Set wg1 as registry and Deploy microservices to wg2 and wg3
./deploy.sh
Test via wg1 or wg2
curl http://192.168.253.135:8081
curl http://192.168.253.135:8082

Step 3: Setup Load Balancer

# Configure HAProxy on wg1

./haproxy.sh
Test via wg1
curl http://192.168.253.133:80/service-a
curl http://192.168.253.133:80/service-b

Step 4: Setup CI/CD Pipeline

# Install Drone CI

./setup-drone-ci.sh

Step 5: Setup Monitoring

# Install Prometheus & Grafana

./setup-monitoring-stack.sh

# Deploy monitoring dashboard

./deploy-grafana-dashboard.sh

Step 6: Test Everything

# Test services via load balancer

curl http://192.168.253.133/service-a
curl http://192.168.253.133/service-b

# Test monitoring

./test-monitoring-alerts.sh

Access Points
Service
URL
Login
Services
http://192.168.253.133/service-a<br>http://192.168.253.133/service-b
None
HAProxy Stats
http://192.168.253.133/stats
admin:admin123
Drone CI
http://192.168.253.133:8080
First user = admin
Prometheus
http://192.168.253.133:9090
None
Grafana
http://192.168.253.133:3000
admin:admin123

⚙️ Key Assumptions
Environment
Host OS: macOS or Linux
VM Provider: VMware or VirtualBox
Network: VMs use 192.168.253.x IP range
Resources: Each VM needs 1GB RAM minimum
Docker & Services
Registry: Insecure local registry (development only)
Architecture: x86_64 compatible
Ports: Services listen on 0.0.0.0:8080 inside containers
Health Checks: Services respond to GET / requests
Network & Security
SSL: Self-signed certificates (not production-ready)
Passwords: Default credentials (change for production)
Access: Vagrant user has sudo on all VMs
Basic Troubleshooting
VMs Won't Start

# Check status

vagrant status

# Restart VMs

vagrant halt
vagrant up

# If still issues, check resources

vagrant up --debug

Services Not Accessible

# Check if containers are running

vagrant ssh wg2
sudo docker ps

# If containers stopped, restart them

sudo docker restart service-a service-b

# Check container logs

sudo docker logs service-a

HAProxy Returns 503 Errors

# Check HAProxy status

vagrant ssh wg1
sudo systemctl status haproxy

# Check backend health

curl http://192.168.253.133/stats

# Restart HAProxy if needed

sudo systemctl restart haproxy

Monitoring Not Working

# Check monitoring stack

vagrant ssh wg1
cd /opt/monitoring
sudo docker-compose ps

# Restart if needed

sudo docker-compose down
sudo docker-compose up -d

# Test Grafana

curl http://192.168.253.133:3000/api/health

Docker Registry Issues

# Test registry access

curl http://192.168.253.133:5000/v2/_catalog

# If registry down, restart it

vagrant ssh wg1
sudo docker restart registry

Complete Reset (If Everything Breaks)

# Nuclear option - destroys everything

vagrant destroy -f
vagrant up

# Then re-run all setup scripts

./deploy.sh
./setup-haproxy.sh
./setup-monitoring-stack.sh

Quick Health Check
Run these commands to verify everything works:

# Test all services

curl http://192.168.253.133/service-a # Should return service response
curl http://192.168.253.133/service-b # Should return service response
curl http://192.168.253.133:9090 # Prometheus UI
curl http://192.168.253.133:3000/api/health # Grafana health

# Check VM connectivity

vagrant ssh wg1 "echo 'wg1 ok'"
vagrant ssh wg2 "echo 'wg2 ok'"
vagrant ssh wg3 "echo 'wg3 ok'"

Success Criteria
Everything is working when:
All 3 VMs are running
Services respond via HAProxy (192.168.253.133/service-a)
Grafana dashboard shows container metrics
Container restart alerts trigger when tested
