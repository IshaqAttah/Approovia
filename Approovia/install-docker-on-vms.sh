#!/bin/bash
set -e

echo "🐳 Installing Docker on All VMs"
echo "==============================="

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

echo "📋 Installing Docker on:"
echo "   wg1: $USER_WG1@$IP_WG1"
echo "   wg2: $USER_WG2@$IP_WG2"
echo "   wg3: $USER_WG3@$IP_WG3"

# Function to install Docker on a VM
install_docker() {
    local vm_key=$1
    local vm_ip=$2
    local vm_user=$3
    local vm_name=$4
    
    echo ""
    echo "🔧 Installing Docker on $vm_name ($vm_ip)..."
    
    ssh -i "$vm_key" -o StrictHostKeyChecking=no $vm_user@$vm_ip << 'EOF'
    # Update system packages
    echo "📦 Updating package lists..."
    sudo apt update
    
    # Install required packages
    echo "📋 Installing prerequisites..."
    sudo apt install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common
    
    # Add Docker's official GPG key
    echo "🔑 Adding Docker GPG key..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo "📚 Adding Docker repository..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package lists again
    echo "🔄 Updating package lists with Docker repo..."
    sudo apt update
    
    # Install Docker
    echo "🐳 Installing Docker Engine..."
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker service
    echo "🚀 Starting Docker service..."
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Add current user to docker group
    echo "👥 Adding user to docker group..."
    sudo usermod -aG docker $USER
    
    # Install Docker Compose (standalone)
    echo "🔧 Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    
    # Verify installation
    echo "✅ Verifying Docker installation..."
    sudo docker --version
    sudo docker-compose --version
    
    # Test Docker (run as sudo since user session needs refresh for group membership)
    echo "🧪 Testing Docker..."
    sudo docker run --rm hello-world
    
    echo "✅ Docker successfully installed on $(hostname)!"
EOF
    
    if [ $? -eq 0 ]; then
        echo "✅ Docker installation completed on $vm_name"
    else
        echo "❌ Docker installation failed on $vm_name"
        exit 1
    fi
}

# Install Docker on all VMs
install_docker "$KEY_WG1" "$IP_WG1" "$USER_WG1" "wg1"
install_docker "$KEY_WG2" "$IP_WG2" "$USER_WG2" "wg2"
install_docker "$KEY_WG3" "$IP_WG3" "$USER_WG3" "wg3"

echo ""
echo "🎉 Docker Installation Completed on All VMs!"
echo "============================================"
echo ""
echo "📋 Next Steps:"
echo "   1. VMs may need a reboot for group changes to take effect"
echo "   2. Run: vagrant reload (optional but recommended)"
echo "   3. Then run: ./deploy.sh"
echo ""
echo "🔍 Verify Docker is working:"
echo "   vagrant ssh wg1 'sudo docker ps'"
echo "   vagrant ssh wg2 'sudo docker ps'" 
echo "   vagrant ssh wg3 'sudo docker ps'"
echo ""
echo "⚠️  Note: You may need to use 'sudo docker' until you log out/in again"
echo "   or run 'vagrant reload' to refresh group membership"
