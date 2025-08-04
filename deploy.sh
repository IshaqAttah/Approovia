#!/bin/bash

# Local Docker registry
REGISTRY=192.168.56.11:5000

# Extract SSH details from Vagrant config dynamically
KEY_WG2=$(vagrant ssh-config wg2 | grep IdentityFile | awk '{print $2}')
KEY_WG3=$(vagrant ssh-config wg3 | grep IdentityFile | awk '{print $2}')
IP_WG2=$(vagrant ssh-config wg2 | grep HostName | awk '{print $2}')
IP_WG3=$(vagrant ssh-config wg3 | grep HostName | awk '{print $2}')

echo "==> Building AppA..."
cd AppA
docker build -t $REGISTRY/app-a:latest .
docker push $REGISTRY/app-a:latest
cd ..

echo "==> Building AppB..."
cd AppB
docker build -t $REGISTRY/app-b:latest .
docker push $REGISTRY/app-b:latest
cd ..

# Deploy to wg2
echo "==> Deploying to wg2 ($IP_WG2)..."
ssh -tt -i "$KEY_WG2" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null vagrant@$IP_WG2 <<EOF
  echo '{ "insecure-registries": ["$REGISTRY"] }' | sudo tee /etc/docker/daemon.json
  sudo systemctl restart docker

  docker pull $REGISTRY/app-a:latest
  docker pull $REGISTRY/app-b:latest

  docker rm -f app-a app-b || true

  docker run -d --name app-a -p 8081:8080 $REGISTRY/app-a:latest
  docker run -d --name app-b -p 8082:8080 $REGISTRY/app-b:latest

  echo "Deployment complete on wg2"
EOF

# Deploy to wg3
echo "==> Deploying to wg3 ($IP_WG3)..."
ssh -tt -i "$KEY_WG3" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null vagrant@$IP_WG3 <<EOF
  echo '{ "insecure-registries": ["$REGISTRY"] }' | sudo tee /etc/docker/daemon.json
  sudo systemctl restart docker

  docker pull $REGISTRY/app-a:latest
  docker pull $REGISTRY/app-b:latest

  docker rm -f app-a app-b || true

  docker run -d --name app-a -p 8081:8080 $REGISTRY/app-a:latest
  docker run -d --name app-b -p 8082:8080 $REGISTRY/app-b:latest

  echo "Deployment complete on wg3"
EOF

