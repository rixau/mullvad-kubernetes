#!/bin/bash

# Mullvad WireGuard Sidecar Entrypoint
# Sets up WireGuard VPN connection with no-leak security and health monitoring

set -e

# Graceful exit handling
cleanup() {
    echo "🧹 Cleaning up..."
    
    # Kill health probe server
    if [ -n "$HEALTH_PID" ]; then
        kill $HEALTH_PID 2>/dev/null || true
        echo "✅ Health probe server stopped"
    fi
    
    # Bring down WireGuard
    wg-quick down wg0 2>/dev/null || true
    
    # Restore original iptables OUTPUT policy
    iptables -P OUTPUT ACCEPT 2>/dev/null || true
    iptables -F OUTPUT 2>/dev/null || true
    
    echo "✅ Cleanup completed"
    exit 0
}

# Set up signal handlers for graceful exit
trap cleanup SIGTERM SIGINT SIGQUIT

echo "🚀 Starting Mullvad WireGuard Sidecar..."

# Check if WireGuard config file exists
if [ ! -f /etc/wireguard/wg0.conf ]; then
    echo "❌ ERROR: WireGuard config file not found at /etc/wireguard/wg0.conf"
    echo "📝 Please mount your Mullvad WireGuard config file to /etc/wireguard/wg0.conf"
    exit 1
fi

echo "✅ Found WireGuard config file"

# Get current network info before starting VPN
DEFAULT_GW=$(ip route | grep default | awk '{print $3}')
DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}')
echo "🌐 Current gateway: $DEFAULT_GW via interface: $DEFAULT_IFACE"

# Pre-configure bypass routes for internal networks
echo "🔧 Pre-configuring bypass routes for internal networks..."

# Detect environment and configure appropriate bypass routes
if [ -n "$KUBERNETES_SERVICE_HOST" ]; then
    # Running in Kubernetes - bypass cluster networks
    echo "🎯 Kubernetes environment detected"
    ip route add 10.42.0.0/16 via $DEFAULT_GW dev $DEFAULT_IFACE || true  # Pod network
    ip route add 10.0.0.0/8 via $DEFAULT_GW dev $DEFAULT_IFACE || true    # Service network
    ip route add 172.16.0.0/12 via $DEFAULT_GW dev $DEFAULT_IFACE || true # Private networks
    ip route add 192.168.0.0/16 via $DEFAULT_GW dev $DEFAULT_IFACE || true # Private networks
    echo "✅ Kubernetes cluster bypass routes configured"
else
    # Running in Docker Compose - bypass Docker networks
    echo "🐳 Docker Compose environment detected"
    # Get all current Docker networks and add bypass routes
    for network in $(ip route | grep -E "172\.(1[6-9]|2[0-9]|3[01])\." | awk '{print $1}' | sort -u); do
        ip route add $network via $DEFAULT_GW dev $DEFAULT_IFACE || true
    done
    # Add common Docker network ranges
    ip route add 172.17.0.0/16 via $DEFAULT_GW dev $DEFAULT_IFACE || true # Default bridge
    ip route add 172.18.0.0/16 via $DEFAULT_GW dev $DEFAULT_IFACE || true # Custom networks
    ip route add 172.19.0.0/16 via $DEFAULT_GW dev $DEFAULT_IFACE || true # Custom networks
    ip route add 172.20.0.0/16 via $DEFAULT_GW dev $DEFAULT_IFACE || true # Custom networks
    echo "✅ Docker Compose bypass routes configured"
fi

# Extract Mullvad peer info for handshake exception
MULLVAD_ENDPOINT=$(grep "^Endpoint" /etc/wireguard/wg0.conf | cut -d'=' -f2 | tr -d ' ')
MULLVAD_IP=$(echo $MULLVAD_ENDPOINT | cut -d':' -f1)
MULLVAD_PORT=$(echo $MULLVAD_ENDPOINT | cut -d':' -f2)

echo "🔐 Using mounted Mullvad WireGuard configuration..."
echo "📄 Mullvad endpoint: $MULLVAD_ENDPOINT"

# Set up no-leak egress policy BEFORE starting VPN
echo "🛡️  Setting up no-leak security policy..."

# Allow handshake to Mullvad peer (exception before drop policy)
iptables -A OUTPUT -p udp --dport $MULLVAD_PORT -d $MULLVAD_IP -j ACCEPT

# Allow loopback traffic
iptables -A OUTPUT -o lo -j ACCEPT

# Allow established connections
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Set default OUTPUT policy to DROP (no-leak protection)
iptables -P OUTPUT DROP

echo "✅ No-leak security policy active - only WireGuard and established connections allowed"

# Start WireGuard (handle DNS gracefully)
echo "🔗 Starting Mullvad WireGuard connection..."

# Set environment to avoid resolvconf issues
export RESOLVCONF=no

# Try wg-quick, handle potential DNS errors gracefully
if wg-quick up wg0 2>&1 | tee /tmp/wg-output; then
    echo "✅ WireGuard started successfully"
elif grep -q "resolvconf: command not found" /tmp/wg-output; then
    echo "⚠️  DNS setup failed but WireGuard interface is up, continuing..."
    # WireGuard interface should still be up even if DNS failed
else
    echo "❌ ERROR: WireGuard failed to start"
    cat /tmp/wg-output
    exit 1
fi

# Wait for WireGuard to establish connection
echo "⏳ Waiting for WireGuard to connect..."
for i in {1..30}; do
    if ip addr show wg0 >/dev/null 2>&1; then
        echo "✅ WireGuard connected successfully"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ ERROR: WireGuard failed to connect after 30 attempts"
        exit 1
    fi
    sleep 2
done

# Allow WireGuard interface traffic (after interface is up)
iptables -A OUTPUT -o wg0 -j ACCEPT
echo "✅ WireGuard interface traffic allowed"

echo "✅ VPN connection established with bypass routes for internal connectivity"

# Validate VPN connection is working
echo "🔍 Validating VPN connection..."
if ! /usr/local/bin/validate-wireguard.sh; then
    echo "❌ ERROR: VPN validation failed - sidecar will exit"
    exit 1
fi

echo "✅ VPN setup completed successfully"

# Start health probe server on port 9999
echo "🩺 Starting health probe server on :9999..."
{
    while true; do
        {
            echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\n\r\nVPN is active"
        } | nc -l -p 9999 2>/dev/null || sleep 1
    done
} &
HEALTH_PID=$!

echo "✅ Health probe server started (PID: $HEALTH_PID)"

# Keep the VPN connection alive and monitor it
echo "👁️  Starting VPN monitoring loop..."
while true; do
    if ip addr show wg0 >/dev/null 2>&1; then
        # Periodically validate VPN is still working (every 5 minutes)
        if [ $(($(date +%s) % 300)) -eq 0 ]; then
            echo "🔍 Periodic VPN validation..."
            if ! /usr/local/bin/validate-wireguard.sh; then
                echo "❌ ERROR: VPN validation failed during monitoring - sidecar will exit"
                exit 1
            fi
            echo "✅ VPN connection healthy"
        fi
    else
        echo "⚠️  VPN connection lost, attempting to reconnect..."
        
        # Restart WireGuard
        wg-quick down wg0 || true
        sleep 5
        wg-quick up wg0
        
        # Wait for reconnection
        sleep 10
        if ip addr show wg0 >/dev/null 2>&1; then
            echo "✅ VPN reconnected successfully"
            # Validate reconnection worked
            if ! /usr/local/bin/validate-wireguard.sh; then
                echo "❌ ERROR: VPN reconnection failed validation - sidecar will exit"
                exit 1
            fi
        else
            echo "❌ ERROR: VPN reconnection failed - sidecar will exit"
            exit 1
        fi
    fi
    sleep 30
done
