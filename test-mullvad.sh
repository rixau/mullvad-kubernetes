#!/bin/bash

# Mullvad Kubernetes Test Script
# Quick test to verify Mullvad WireGuard VPN functionality

set -e

echo "🔒 Mullvad Kubernetes Sidecar Test"
echo "=================================="

# Check if conf directory exists and list available configs
if [ ! -d "conf" ]; then
    mkdir -p conf
fi

echo "🔍 Checking for WireGuard configurations..."
CONF_FILES=$(find conf -name "*.conf" 2>/dev/null | wc -l)

if [ "$CONF_FILES" -eq 0 ]; then
    echo "❌ ERROR: No WireGuard configuration files found in ./conf/"
    echo ""
    echo "📋 To get started:"
    echo "   1. Go to: https://mullvad.net/en/account/wireguard-config"
    echo "   2. Download your WireGuard configuration file(s)"
    echo "   3. Place them in the ./conf/ directory"
    echo "   4. Update docker-compose.yml to mount your config:"
    echo "      volumes:"
    echo "        - ./conf/your-config.conf:/etc/wireguard/wg0.conf:ro"
    echo ""
    echo "📁 Example config files:"
    echo "   ./conf/br-sao-wg-001.conf  (Brazil - São Paulo)"
    echo "   ./conf/us-nyc-wg-001.conf  (US - New York)"
    echo "   ./conf/se-got-wg-001.conf  (Sweden - Gothenburg)"
    exit 1
fi

echo "📁 Found $CONF_FILES WireGuard configuration file(s) in ./conf/:"
find conf -name "*.conf" -exec basename {} \; | sort

# Check if WireGuard config is mounted in docker-compose
if ! grep -q "/etc/wireguard/wg0.conf" docker-compose.yml; then
    echo ""
    echo "❌ ERROR: No WireGuard config mounted in docker-compose.yml"
    echo "📝 Please update docker-compose.yml to mount a config file:"
    echo "   volumes:"
    echo "     - ./conf/$(find conf -name "*.conf" -exec basename {} \; | head -1):/etc/wireguard/wg0.conf:ro"
    exit 1
fi

echo "✅ Prerequisites check passed"
echo ""

# Get current real IP for comparison
echo "🔍 Getting your real IP address..."
REAL_IP=$(curl -s --max-time 10 http://httpbin.org/ip | grep -o '"origin": "[^"]*"' | cut -d'"' -f4 || echo "unknown")
echo "📍 Your real IP: $REAL_IP"
echo ""

# Start the test
echo "🚀 Starting Mullvad WireGuard sidecar test..."
echo "⏳ This will take about 30-60 seconds..."
echo ""

# Start in detached mode
docker compose up --build -d mullvad-sidecar

# Wait for VPN to connect
echo "⏳ Waiting for WireGuard connection..."
sleep 30

# Check VPN status
echo "🔍 Checking VPN connection..."
VPN_IP=$(docker exec mullvad-sidecar curl -s --max-time 10 http://httpbin.org/ip | grep -o '"origin": "[^"]*"' | cut -d'"' -f4 || echo "error")

echo ""
echo "📊 Results:"
echo "🏠 Real IP:    $REAL_IP"
echo "🔒 VPN IP:     $VPN_IP"
echo ""

if [ "$VPN_IP" != "$REAL_IP" ] && [ "$VPN_IP" != "error" ] && [ -n "$VPN_IP" ]; then
    echo "🎉 SUCCESS: Mullvad VPN is working!"
    echo "✅ Traffic is routing through Mullvad WireGuard"
    echo ""
    
    # Test health probe
    echo "🩺 Testing health probe endpoint..."
    HEALTH_CHECK=$(curl -s --max-time 5 http://localhost:9999 || echo "error")
    if [ "$HEALTH_CHECK" = "VPN is active" ]; then
        echo "✅ Health probe working: $HEALTH_CHECK"
    else
        echo "⚠️  Health probe issue: $HEALTH_CHECK"
    fi
    
    echo ""
    echo "🌐 Additional testing options:"
    echo "   Health check: curl http://localhost:9999"
    echo "   Web interface: docker compose up -d test-web && open http://localhost:8080"
else
    echo "❌ FAILURE: Mullvad VPN is not working properly"
    echo "🔍 Check the logs: docker logs mullvad-sidecar"
fi

echo ""
echo "🧹 To clean up: docker compose down"
