#!/bin/bash
set -e

echo "=== Setting up Drone CI on wg1 ==="

# Get connection details
KEY_WG1=$(vagrant ssh-config wg1 | awk '/IdentityFile/ {print $2}')
IP_WG1=$(vagrant ssh-config wg1 | awk '/HostName/ {print $2}')
USER_WG1=$(vagrant ssh-config wg1 | awk '/User / {print $2}')

echo "Installing Drone CI on: $USER_WG1@$IP_WG1"

# Install and configure Drone CI
ssh -i "$KEY_WG1" -o StrictHostKeyChecking=no $USER_WG1@$IP_WG1 << 'EOF'

# Create directories for Drone
sudo mkdir -p /etc/drone
sudo mkdir -p /var/lib/drone

# Generate a shared secret for Drone
DRONE_RPC_SECRET=$(openssl rand -hex 16)
echo "Generated Drone RPC Secret: $DRONE_RPC_SECRET"

# Create Drone server configuration
sudo tee /etc/drone/drone-server.env > /dev/null << DRONE_ENV
# Drone server configuration
DRONE_GITEA_SERVER=http://localhost:3000
DRONE_GITEA_CLIENT_ID=drone
DRONE_GITEA_CLIENT_SECRET=drone_secret
DRONE_RPC_SECRET=$DRONE_RPC_SECRET
DRONE_SERVER_HOST=localhost:8080
DRONE_SERVER_PROTO=http
DRONE_USER_CREATE=username:admin,admin:true
DRONE_LOGS_PRETTY=true
DRONE_LOGS_COLOR=true
DRONE_DATABASE_DRIVER=sqlite3
DRONE_DATABASE_DATASOURCE=/data/database.sqlite
DRONE_CLEANUP_INTERVAL=24h
DRONE_CLEANUP_DISABLED=false
DRONE_REPOSITORY_FILTER=*
DRONE_OPEN=true
DRONE_ENV

# Create Drone runner configuration  
sudo tee /etc/drone/drone-runner.env > /dev/null << RUNNER_ENV
# Drone runner configuration
DRONE_RPC_PROTO=http
DRONE_RPC_HOST=localhost:8080
DRONE_RPC_SECRET=$DRONE_RPC_SECRET
DRONE_RUNNER_CAPACITY=2
DRONE_RUNNER_NAME=runner-1
DRONE_LOGS_PRETTY=true
DRONE_LOGS_COLOR=true
RUNNER_ENV

# Create docker-compose file for Drone
sudo tee /etc/drone/docker-compose.yml > /dev/null << 'COMPOSE_EOF'
version: '3.8'

services:
  drone-server:
    image: drone/drone:2
    container_name: drone-server
    restart: unless-stopped
    ports:
      - "8080:80"
    volumes:
      - /var/lib/drone:/data
      - /var/run/docker.sock:/var/run/docker.sock
    env_file:
      - /etc/drone/drone-server.env
    networks:
      - drone

  drone-runner:
    image: drone/drone-runner-docker:1
    container_name: drone-runner
    restart: unless-stopped
    depends_on:
      - drone-server
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    env_file:
      - /etc/drone/drone-runner.env
    networks:
      - drone

networks:
  drone:
    driver: bridge
COMPOSE_EOF

# Install Docker Compose if not present
if ! command -v docker-compose &> /dev/null; then
    echo "Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

# Start Drone CI
echo "Starting Drone CI services..."
cd /etc/drone
sudo docker-compose up -d

# Wait for services to start
echo "Waiting for Drone to start..."
sleep 10

# Check if services are running
sudo docker-compose ps

echo "✅ Drone CI installation completed!"
echo ""
echo "🔗 Drone CI URLs:"
echo "   Drone Server: http://localhost:8080"
echo "   External access: http://$IP_WG1:8080"
echo ""
echo "📋 Default login (if using open mode):"
echo "   First user to register becomes admin"

EOF

echo ""
echo "🎉 Drone CI setup completed!"
echo ""
echo "🔗 Access Drone CI:"
echo "   From wg1: http://localhost:8080"
echo "   From your Mac: http://$IP_WG1:8080"
echo ""
echo "📝 Next steps:"
echo "   1. Access Drone UI and register as admin"
echo "   2. Create/connect your Git repository"
echo "   3. Add the .drone.yml file to your project"
