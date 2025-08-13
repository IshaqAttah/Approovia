#!/bin/bash

# Get HAProxy IP
IP_WG1=$(vagrant ssh-config wg1 | awk '/HostName/ {print $2}')

echo " Testing HAProxy Load Balancer on $IP_WG1"
echo "=================================================="

# Test HTTP endpoints
echo ""
echo " Testing HTTP endpoints:"
echo "-------------------------"

echo " Health check:"
curl -s http://$IP_WG1/health
echo ""

echo " Service A (should load balance between wg2 and wg3):"
for i in {1..4}; do
    echo "Request $i:"
    curl -s http://$IP_WG1/service-a
    echo ""
done

echo " Service B (should load balance between wg2 and wg3):"
for i in {1..4}; do
    echo "Request $i:"
    curl -s http://$IP_WG1/service-b
    echo ""
done

# Test HTTPS endpoints
echo ""
echo " Testing HTTPS endpoints:"
echo "-------------------------"

echo " HTTPS Health check:"
curl -k -s https://$IP_WG1/health
echo ""

echo " HTTPS Service A:"
curl -k -s https://$IP_WG1/service-a
echo ""

echo " HTTPS Service B:"
curl -k -s https://$IP_WG1/service-b
echo ""

# Test 404 handling
echo ""
echo " Testing 404 handling:"
echo "------------------------"
curl -s http://$IP_WG1/nonexistent
echo ""

# Test stats page
echo ""
echo " HAProxy Stats available at:"
echo "   http://$IP_WG1/stats (username: admin, password: admin123)"
echo ""

echo " All tests completed!"
echo ""
echo " Tips:"
echo "   - Watch the container IDs in responses to see load balancing"
echo "   - Check /stats page for real-time backend health"
echo "   - Use 'curl -k' for HTTPS to ignore self-signed certificate warnings"
