#!/bin/bash
set -e

# Auto-detect host info from Vagrant
echo "=== Fetching VM connection details from Vagrant ==="
KEY_WG1=$(vagrant ssh-config wg1 | awk '/IdentityFile/ {print $2}')
KEY_WG2=$(vagrant ssh-config wg2 | awk '/IdentityFile/ {print $2}')
KEY_WG3=$(vagrant ssh-config wg3 | awk '/IdentityFile/ {print $2}')
IP_WG1=$(vagrant ssh-config wg1 | awk '/HostName/ {print $2}')
IP_WG2=$(vagrant ssh-config wg2 | awk '/HostName/ {print $2}')
IP_WG3=$(vagrant ssh-config wg3 | awk '/HostName/ {print $2}')
USER_WG1=$(vagrant ssh-config wg1 | awk '/User / {print $2}')
USER_WG2=$(vagrant ssh-config wg2 | awk '/User / {print $2}')
USER_WG3=$(vagrant ssh-config wg3 | awk '/User / {print $2}')

echo "Detected VMs:"
echo "  wg1 (registry): $USER_WG1@$IP_WG1"
echo "  wg2 (target):   $USER_WG2@$IP_WG2"
echo "  wg3 (target):   $USER_WG3@$IP_WG3"

# Start local Docker registry on wg1
echo "=== Step 1: Setting up Docker registry on wg1 ==="
ssh -i "$KEY_WG1" -o StrictHostKeyChecking=no $USER_WG1@$IP_WG1 \
  "sudo docker ps | grep registry || sudo docker run -d -p 5000:5000 --restart always --name registry registry:2"

# Copy service directories to wg1 for building
echo "=== Step 2: Copying service source code to wg1 ==="
scp -i "$KEY_WG1" -o StrictHostKeyChecking=no -r ./services/ $USER_WG1@$IP_WG1:~/

# Build and push images on wg1 (ensures correct architecture)
echo "=== Step 3: Building Docker images on wg1 ==="
ssh -i "$KEY_WG1" -o StrictHostKeyChecking=no $USER_WG1@$IP_WG1 "
  echo 'Building service-a...' &&
  sudo docker build -t localhost:5000/service-a:latest ~/services/service-a &&
  echo 'Building service-b...' &&
  sudo docker build -t localhost:5000/service-b:latest ~/services/service-b &&
  echo 'Pushing images to local registry...' &&
  sudo docker push localhost:5000/service-a:latest &&
  sudo docker push localhost:5000/service-b:latest &&
  echo 'Images built and pushed successfully!' &&
  echo 'Verifying images in registry:' &&
  sudo docker images | grep localhost:5000
"

# Function to deploy to a target VM
deploy_to_vm() {
  local vm_name=$1
  local vm_key=$2
  local vm_ip=$3
  local vm_user=$4
  
  echo "=== Step $5: Deploying to $vm_name ($vm_ip) ==="
  
  ssh -i "$vm_key" -o StrictHostKeyChecking=no $vm_user@$vm_ip "
    echo 'Configuring Docker for insecure registry...' &&
    echo '{\"insecure-registries\": [\"$IP_WG1:5000\"]}' | sudo tee /etc/docker/daemon.json &&
    sudo systemctl restart docker &&
    sleep 5 &&
    
    echo 'Pulling latest images...' &&
    sudo docker pull $IP_WG1:5000/service-a:latest &&
    sudo docker pull $IP_WG1:5000/service-b:latest &&
    
    echo 'Stopping and removing existing containers...' &&
    sudo docker stop service-a service-b 2>/dev/null || true &&
    sudo docker rm service-a service-b 2>/dev/null || true &&
    
    echo 'Starting new containers...' &&
    sudo docker run -d --name service-a --restart unless-stopped -p 8081:8080 $IP_WG1:5000/service-a:latest &&
    sudo docker run -d --name service-b --restart unless-stopped -p 8082:8080 $IP_WG1:5000/service-b:latest &&
    
    echo 'Verifying deployment...' &&
    sleep 3 &&
    sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' &&
    
    echo 'Testing service connectivity...' &&
    timeout 10 sh -c 'until nc -z localhost 8081; do sleep 1; done' && echo 'service-a: ✓ Port 8081 accessible' || echo 'service-a: ✗ Port 8081 not accessible' &&
    timeout 10 sh -c 'until nc -z localhost 8082; do sleep 1; done' && echo 'service-b: ✓ Port 8082 accessible' || echo 'service-b: ✗ Port 8082 not accessible'
  "
}

# Deploy to wg2
deploy_to_vm "wg2" "$KEY_WG2" "$IP_WG2" "$USER_WG2" "4"

# Deploy to wg3  
deploy_to_vm "wg3" "$KEY_WG3" "$IP_WG3" "$USER_WG3" "5"

echo ""
echo "  Deployment completed successfully!"
echo ""
echo "   Service endpoints:"
echo "   wg2 service-a: http://$IP_WG2:8081"
echo "   wg2 service-b: http://$IP_WG2:8082"
echo "   wg3 service-a: http://$IP_WG3:8081"
echo "   wg3 service-b: http://$IP_WG3:8082"
echo ""
echo "   Test your deployment:"
echo "   curl http://$IP_WG2:8081"
echo "   curl http://$IP_WG2:8082"
echo "   curl http://$IP_WG3:8081"
echo "   curl http://$IP_WG3:8082"
