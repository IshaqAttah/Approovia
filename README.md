Here’s a clean, well-structured **README.md** version of what you wrote.
I formatted it for clarity, added headings, fenced code blocks, and tables so it’s presentation-ready.

---

# **Complete DevOps Infrastructure Setup**

A containerized microservices deployment platform with automated CI/CD, load balancing, and monitoring.

---

## ** What This Project Includes**

- **Multi-VM Setup** – 3 VMs (`wg1`, `wg2`, `wg3`) with Vagrant
- **Containerized Services** – Docker-based Go microservices
- **Load Balancing** – HAProxy with SSL and health checks
- **CI/CD Pipeline** – Drone CI with automated deployment
- **Monitoring** – Prometheus + Grafana with alerting

---

## **🚀 How to Run Everything**

### **Step 1 – Start VMs**

```bash
# Start all VMs
vagrant up

# Verify VMs are running
vagrant status
```

---

### **Step 2 – Deploy Docker Services**

```bash
cd Approovia
# Set wg1 as registry and deploy microservices to wg2 and wg3
./deploy.sh
```

**Test Services**

```bash
curl http://192.168.253.135:8081
curl http://192.168.253.135:8082
```

---

### **Step 3 – Setup Load Balancer**

```bash
# Configure HAProxy on wg1
./haproxy.sh
```

**Test via wg1**

```bash
curl http://192.168.253.133:80/service-a
curl http://192.168.253.133:80/service-b
```

---

### **Step 4 – Setup CI/CD Pipeline**

```bash
# Install Drone CI
./setup-drone-ci.sh
```

---

### **Step 5 – Setup Monitoring**

```bash
# Install Prometheus & Grafana
./setup-monitoring-stack.sh

# Deploy monitoring dashboard
./deploy-grafana-dashboard.sh
```

---

### **Step 6 – Test Everything**

```bash
# Test services via load balancer
curl http://192.168.253.133/service-a
curl http://192.168.253.133/service-b

# Test monitoring
./test-monitoring-alerts.sh
```

---

## ** Access Points**

| Service           | URL                                                                                              | Login              |
| ----------------- | ------------------------------------------------------------------------------------------------ | ------------------ |
| **Services**      | [Service A](http://192.168.253.133/service-a) <br> [Service B](http://192.168.253.133/service-b) | None               |
| **HAProxy Stats** | [HAProxy](http://192.168.253.133/stats)                                                          | `admin:admin123`   |
| **Drone CI**      | [Drone](http://192.168.253.133:8080)                                                             | First user = admin |
| **Prometheus**    | [Prometheus](http://192.168.253.133:9090)                                                        | None               |
| **Grafana**       | [Grafana](http://192.168.253.133:3000)                                                           | `admin:admin123`   |

---

## ** Key Assumptions**

### **Environment**

- Host OS: **macOS** or **Linux**
- VM Provider: **VMware** or **VirtualBox**
- Network: **192.168.253.x** IP range
- Resources: **1GB RAM per VM**

### **Docker & Services**

- Registry: Insecure local registry (dev only)
- Architecture: **x86_64 compatible**
- Ports: Containers listen on `0.0.0.0:8080`
- Health Checks: Services respond to `GET /`

### **Network & Security**

- SSL: Self-signed certificates
- Passwords: Default credentials (change for prod)
- Access: `vagrant` user has `sudo` privileges

---

## ** Troubleshooting**

### **VMs Won't Start**

```bash
vagrant status
vagrant halt
vagrant up
vagrant up --debug
```

### **Services Not Accessible**

```bash
# Check containers
vagrant ssh wg2
sudo docker ps

# Restart if needed
sudo docker restart service-a service-b

# Logs
sudo docker logs service-a
```

### **HAProxy Returns 503**

```bash
vagrant ssh wg1
sudo systemctl status haproxy
curl http://192.168.253.133/stats
sudo systemctl restart haproxy
```

### **Monitoring Not Working**

```bash
vagrant ssh wg1
cd /opt/monitoring
sudo docker-compose ps
sudo docker-compose down && sudo docker-compose up -d
curl http://192.168.253.133:3000/api/health
```

### **Docker Registry Issues**

```bash
curl http://192.168.253.133:5000/v2/_catalog
vagrant ssh wg1
sudo docker restart registry
```

---

## ** Complete Reset**

```bash
vagrant destroy -f
vagrant up

./deploy.sh
./setup-haproxy.sh
./setup-monitoring-stack.sh
```

---

## ** Quick Health Check**

```bash
# Test services
curl http://192.168.253.133/service-a
curl http://192.168.253.133/service-b
curl http://192.168.253.133:9090
curl http://192.168.253.133:3000/api/health

# Test VM connectivity
vagrant ssh wg1 "echo 'wg1 ok'"
vagrant ssh wg2 "echo 'wg2 ok'"
vagrant ssh wg3 "echo 'wg3 ok'"
```

---

## ** Success Criteria**

All 3 VMs are running
Services respond via HAProxy
Grafana dashboard shows container metrics
Alerts trigger when containers restart
