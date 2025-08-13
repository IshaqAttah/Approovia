#!/bin/bash
set -e

# Auto-detect host info from Vagrant
echo "=== Setting up HAProxy on wg1 ==="
KEY_WG1=$(vagrant ssh-config wg1 | awk '/IdentityFile/ {print $2}')
IP_WG1=$(vagrant ssh-config wg1 | awk '/HostName/ {print $2}')
IP_WG2=$(vagrant ssh-config wg2 | awk '/HostName/ {print $2}')
IP_WG3=$(vagrant ssh-config wg3 | awk '/HostName/ {print $2}')
USER_WG1=$(vagrant ssh-config wg1 | awk '/User / {print $2}')

echo "HAProxy will be installed on: $USER_WG1@$IP_WG1"
echo "Backend servers: $IP_WG2:8081/8082, $IP_WG3:8081/8082"

# Install and configure HAProxy on wg1
ssh -i "$KEY_WG1" -o StrictHostKeyChecking=no $USER_WG1@$IP_WG1 << 'EOF'
# Update system and install HAProxy
sudo apt update
sudo apt install -y haproxy openssl

# Backup original config
sudo cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup

# Create SSL directory and generate self-signed certificate
sudo mkdir -p /etc/ssl/private
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/haproxy.key \
    -out /etc/ssl/certs/haproxy.crt \
    -subj "/C=US/ST=Lab/L=Lab/O=Lab/CN=haproxy.local"

# Combine cert and key for HAProxy
sudo cat /etc/ssl/certs/haproxy.crt /etc/ssl/private/haproxy.key | sudo tee /etc/ssl/private/haproxy.pem
sudo chmod 600 /etc/ssl/private/haproxy.pem

echo " HAProxy installed and SSL certificate generated"
EOF

# Create HAProxy configuration
echo "=== Creating HAProxy configuration ==="
ssh -i "$KEY_WG1" -o StrictHostKeyChecking=no $USER_WG1@$IP_WG1 << EOF
sudo tee /etc/haproxy/haproxy.cfg > /dev/null << 'HAPROXY_CONFIG'
#---------------------------------------------------------------------
# HAProxy Configuration for Microservices Load Balancing
#---------------------------------------------------------------------

global
    log         127.0.0.1:514 local0
    chroot      /var/lib/haproxy
    stats       socket /run/haproxy/admin.sock mode 660 level admin
    stats       timeout 30s
    user        haproxy
    group       haproxy
    daemon

    # SSL/TLS Configuration
    ssl-default-bind-ciphers ECDHE+AESGCM:ECDHE+CHACHA20:!aNULL:!SHA1:!AEAD
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
    mode                    http
    log                     global
    option                  httplog
    option                  dontlognull
    option                  log-health-checks
    option                  forwardfor
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000

#---------------------------------------------------------------------
# Frontend Configuration - HTTP (Port 80)
#---------------------------------------------------------------------
frontend http_frontend
    bind *:80
    
    # Security headers
    http-response set-header X-Frame-Options DENY
    http-response set-header X-Content-Type-Options nosniff
    http-response set-header X-XSS-Protection "1; mode=block"
    
    # ACLs for path-based routing
    acl is_service_a path_beg /service-a
    acl is_service_b path_beg /service-b
    acl is_stats path_beg /stats
    
    # Health check endpoint
    acl is_health path /health
    
    # Route to backends based on ACLs
    use_backend service_a_backend if is_service_a
    use_backend service_b_backend if is_service_b
    use_backend stats_backend if is_stats
    
    # Health check response
    http-request return status 200 content-type text/plain string "HAProxy OK" if is_health
    
    # Default response for unmatched paths
    default_backend default_backend

#---------------------------------------------------------------------
# Frontend Configuration - HTTPS (Port 443)
#---------------------------------------------------------------------
frontend https_frontend
    bind *:443 ssl crt /etc/ssl/private/haproxy.pem
    
    # Security headers for HTTPS
    http-response set-header Strict-Transport-Security "max-age=31536000; includeSubDomains"
    http-response set-header X-Frame-Options DENY
    http-response set-header X-Content-Type-Options nosniff
    http-response set-header X-XSS-Protection "1; mode=block"
    
    # ACLs for path-based routing (same as HTTP)
    acl is_service_a path_beg /service-a
    acl is_service_b path_beg /service-b
    acl is_stats path_beg /stats
    acl is_health path /health
    
    # Route to backends
    use_backend service_a_backend if is_service_a
    use_backend service_b_backend if is_service_b
    use_backend stats_backend if is_stats
    
    # Health check response
    http-request return status 200 content-type text/plain string "HAProxy OK (HTTPS)" if is_health
    
    # Default backend
    default_backend default_backend

#---------------------------------------------------------------------
# Backend Configuration - Service A
#---------------------------------------------------------------------
backend service_a_backend
    balance roundrobin
    option httpchk GET /
    http-check expect status 200
    
    # Rewrite path to remove /service-a prefix
    http-request set-path /
    
    # Backend servers
    server wg2-service-a $IP_WG2:8081 check inter 5s fall 3 rise 2
    server wg3-service-a $IP_WG3:8081 check inter 5s fall 3 rise 2

#---------------------------------------------------------------------
# Backend Configuration - Service B  
#---------------------------------------------------------------------
backend service_b_backend
    balance roundrobin
    option httpchk GET /
    http-check expect status 200
    
    # Rewrite path to remove /service-b prefix
    http-request set-path /
    
    # Backend servers
    server wg2-service-b $IP_WG2:8082 check inter 5s fall 3 rise 2
    server wg3-service-b $IP_WG3:8082 check inter 5s fall 3 rise 2

#---------------------------------------------------------------------
# Backend Configuration - HAProxy Stats
#---------------------------------------------------------------------
backend stats_backend
    stats enable
    stats uri /stats
    stats refresh 30s
    stats admin if TRUE
    stats auth admin:admin123

#---------------------------------------------------------------------
# Default Backend - For unmatched requests
#---------------------------------------------------------------------
backend default_backend
    http-request return status 404 content-type text/plain string "404 - Service Not Found\\nAvailable endpoints:\\n/service-a\\n/service-b\\n/stats\\n/health"

HAPROXY_CONFIG

echo " HAProxy configuration created"
EOF

# Enable and start HAProxy
echo "=== Starting HAProxy service ==="
ssh -i "$KEY_WG1" -o StrictHostKeyChecking=no $USER_WG1@$IP_WG1 << 'EOF'
# Test configuration
sudo haproxy -c -f /etc/haproxy/haproxy.cfg

# Enable and start HAProxy
sudo systemctl enable haproxy
sudo systemctl restart haproxy

# Check status
sudo systemctl status haproxy --no-pager

echo " HAProxy is running"
EOF

echo ""
echo " HAProxy setup completed successfully!"
echo ""
echo " Access your services:"
echo "   HTTP:"
echo "     http://$IP_WG1/service-a"
echo "     http://$IP_WG1/service-b" 
echo "     http://$IP_WG1/health"
echo "     http://$IP_WG1/stats (admin:admin123)"
echo ""
echo "   HTTPS:"
echo "     https://$IP_WG1/service-a"
echo "     https://$IP_WG1/service-b"
echo "     https://$IP_WG1/health"
echo "     https://$IP_WG1/stats (admin:admin123)"
echo ""
echo "  Test commands:"
echo "   curl http://$IP_WG1/service-a"
echo "   curl http://$IP_WG1/service-b"
echo "   curl http://$IP_WG1/health"
echo "   curl -k https://$IP_WG1/service-a"
echo "   curl -k https://$IP_WG1/service-b"
