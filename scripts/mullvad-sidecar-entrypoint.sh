#!/bin/bash

# Mullvad WireGuard Sidecar Entrypoint
# Sets up WireGuard VPN connection with no-leak security and health monitoring

set -e

# Graceful exit handling
cleanup() {
    echo "🧹 Cleaning up..."
    
    # Kill proxy servers
    if [ -n "$DANTE_PID" ]; then
        kill $DANTE_PID 2>/dev/null || true
        echo "✅ SOCKS5 proxy (dante) stopped"
    fi
    if [ -n "$TINYPROXY_PID" ]; then
        kill $TINYPROXY_PID 2>/dev/null || true
        echo "✅ HTTP proxy (tinyproxy) stopped"
    fi
    
    # Kill health probe server
    if [ -n "$HEALTH_PID" ]; then
        kill $HEALTH_PID 2>/dev/null || true
        echo "✅ Health probe server stopped"
    fi
    
    # Bring down WireGuard
    wg-quick down wg0 2>/dev/null || true
    
    # Restore original DNS configuration
    if [ -f /tmp/original-resolv.conf ]; then
        cp /tmp/original-resolv.conf /etc/resolv.conf
        echo "✅ Original DNS configuration restored"
    fi
    
    # Restore original iptables OUTPUT policy
    iptables -P OUTPUT ACCEPT 2>/dev/null || true
    iptables -F OUTPUT 2>/dev/null || true
    
    echo "✅ Cleanup completed"
    exit 0
}

# Set up signal handlers for graceful exit
trap cleanup SIGTERM SIGINT SIGQUIT

echo "🚀 Starting Mullvad WireGuard Sidecar..."

# Environment variable controls (defaults for maximum compatibility)
ENABLE_KILL_SWITCH=${ENABLE_KILL_SWITCH:-false}
ENABLE_DNS_CONFIG=${ENABLE_DNS_CONFIG:-false}
ENABLE_BYPASS_ROUTES=${ENABLE_BYPASS_ROUTES:-true}
ENABLE_HEALTH_PROBE=${ENABLE_HEALTH_PROBE:-true}
ENABLE_PROXY_MODE=${ENABLE_PROXY_MODE:-false}

echo "🔧 Configuration:"
echo "   Kill-switch: $ENABLE_KILL_SWITCH"
echo "   DNS config: $ENABLE_DNS_CONFIG"
echo "   Bypass routes: $ENABLE_BYPASS_ROUTES"
echo "   Health probe: $ENABLE_HEALTH_PROBE"
echo "   Proxy mode: $ENABLE_PROXY_MODE"

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

# Pre-configure bypass routes for internal networks (if enabled)
if [ "$ENABLE_BYPASS_ROUTES" = "true" ]; then
    echo "🔧 Pre-configuring bypass routes for internal networks..."

    # Detect environment and configure appropriate bypass routes
    if [ -n "$KUBERNETES_SERVICE_HOST" ]; then
    # Running in Kubernetes - bypass cluster networks
    echo "🎯 Kubernetes environment detected"
    echo "🔧 Attempting to configure bypass routes..."
    
    # Try to add bypass routes, but don't fail if permissions are insufficient
    ROUTES_ADDED=0
    if ip route add 10.42.0.0/16 via $DEFAULT_GW dev $DEFAULT_IFACE 2>/dev/null; then ROUTES_ADDED=$((ROUTES_ADDED+1)); fi
    if ip route add 10.0.0.0/8 via $DEFAULT_GW dev $DEFAULT_IFACE 2>/dev/null; then ROUTES_ADDED=$((ROUTES_ADDED+1)); fi
    if ip route add 172.16.0.0/12 via $DEFAULT_GW dev $DEFAULT_IFACE 2>/dev/null; then ROUTES_ADDED=$((ROUTES_ADDED+1)); fi
    if ip route add 192.168.0.0/16 via $DEFAULT_GW dev $DEFAULT_IFACE 2>/dev/null; then ROUTES_ADDED=$((ROUTES_ADDED+1)); fi
    
    if [ $ROUTES_ADDED -gt 0 ]; then
        echo "✅ Kubernetes cluster bypass routes configured ($ROUTES_ADDED/4 routes added)"
    else
        echo "⚠️  Could not configure bypass routes (insufficient permissions)"
        echo "🔄 Continuing with WireGuard setup - internal connectivity may be limited"
    fi
else
    # Running in Docker Compose - bypass Docker networks
    echo "🐳 Docker Compose environment detected"
    # Get all current Docker networks and add bypass routes
    for network in $(ip route | grep -E "172\.(1[6-9]|2[0-9]|3[01])\." | awk '{print $1}' | sort -u); do
        ip route add $network via $DEFAULT_GW dev $DEFAULT_IFACE 2>/dev/null || true
    done
    # Add common Docker network ranges
    ip route add 172.17.0.0/16 via $DEFAULT_GW dev $DEFAULT_IFACE 2>/dev/null || true # Default bridge
    ip route add 172.18.0.0/16 via $DEFAULT_GW dev $DEFAULT_IFACE 2>/dev/null || true # Custom networks
    ip route add 172.19.0.0/16 via $DEFAULT_GW dev $DEFAULT_IFACE 2>/dev/null || true # Custom networks
    ip route add 172.20.0.0/16 via $DEFAULT_GW dev $DEFAULT_IFACE 2>/dev/null || true # Custom networks
    echo "✅ Docker Compose bypass routes configured"
    fi
else
    echo "⚠️  Bypass routes disabled via ENABLE_BYPASS_ROUTES=false"
fi

# Extract Mullvad peer info for handshake exception
MULLVAD_ENDPOINT=$(grep "^Endpoint" /etc/wireguard/wg0.conf | cut -d'=' -f2 | tr -d ' ')
MULLVAD_IP=$(echo $MULLVAD_ENDPOINT | cut -d':' -f1)
MULLVAD_PORT=$(echo $MULLVAD_ENDPOINT | cut -d':' -f2)

echo "🔐 Using mounted Mullvad WireGuard configuration..."
echo "📄 Mullvad endpoint: $MULLVAD_ENDPOINT"

# Set up no-leak egress policy BEFORE starting VPN (if enabled)
if [ "$ENABLE_KILL_SWITCH" = "true" ]; then
    echo "🛡️  Setting up no-leak security policy..."

    # Try to set up no-leak security policy (gracefully handle permission errors)
    if iptables -A OUTPUT -p udp --dport $MULLVAD_PORT -d $MULLVAD_IP -j ACCEPT 2>/dev/null && \
       iptables -A OUTPUT -o lo -j ACCEPT 2>/dev/null && \
       iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null && \
       iptables -P OUTPUT DROP 2>/dev/null; then
        echo "✅ No-leak security policy active - only WireGuard and established connections allowed"
    else
        echo "⚠️  Could not configure iptables kill-switch (insufficient permissions)"
        echo "🔄 Continuing with WireGuard setup - VPN will work but without kill-switch protection"
    fi
else
    echo "⚠️  Kill-switch disabled via ENABLE_KILL_SWITCH=false"
    echo "🔄 VPN will work without traffic leak protection"
fi

# Start WireGuard (handle DNS gracefully)
echo "🔗 Starting Mullvad WireGuard connection..."

# Preserve original DNS settings before starting WireGuard
echo "🔧 Preserving original DNS configuration..."
cp /etc/resolv.conf /tmp/original-resolv.conf

# Set environment to avoid resolvconf issues and prevent DNS override
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

# DNS configuration (conditional based on environment variable)
if [ "$ENABLE_DNS_CONFIG" = "true" ]; then
    echo "🔧 DNS configuration enabled"
    if [ -n "$KUBERNETES_SERVICE_HOST" ]; then
        echo "🔧 Kubernetes environment detected - skipping DNS modification"
        echo "⚠️  Using default cluster DNS configuration"
        echo "🔄 External traffic will route through WireGuard, internal through cluster DNS"
    else
    # Fix DNS configuration for internal service resolution (non-fatal)
    echo "🔧 Configuring hybrid DNS for internal and external resolution..."

    # Attempt DNS configuration in a way that never fails the script
    set +e  # Temporarily disable exit on error
    {
        cat > /etc/resolv.conf << EOF
# Hybrid DNS configuration for VPN + internal services
# Original DNS for internal services (Docker/Kubernetes)
$(grep "nameserver" /tmp/original-resolv.conf | head -1 2>/dev/null || echo "nameserver 8.8.8.8")
# Mullvad DNS for external resolution
nameserver 10.64.0.1
# Search domains from original config
$(grep "search" /tmp/original-resolv.conf 2>/dev/null || echo "")
EOF
    } >/dev/null 2>&1

    DNS_RESULT=$?
    set -e  # Re-enable exit on error

    if [ $DNS_RESULT -eq 0 ]; then
        echo "✅ Hybrid DNS configuration applied"
        echo "📄 DNS Configuration:"
        cat /etc/resolv.conf 2>/dev/null || echo "Could not read DNS config"
    else
        echo "⚠️  Could not modify /etc/resolv.conf (insufficient permissions)"
        echo "🔄 Using default DNS configuration - external resolution may use original DNS"
    fi
    fi
else
    echo "⚠️  DNS configuration disabled via ENABLE_DNS_CONFIG=false"
    echo "🔄 Using default DNS configuration"
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

# Allow WireGuard interface traffic (after interface is up) - only if kill-switch is enabled
if [ "$ENABLE_KILL_SWITCH" = "true" ]; then
    if iptables -A OUTPUT -o wg0 -j ACCEPT 2>/dev/null; then
        echo "✅ WireGuard interface traffic allowed"
    else
        echo "⚠️  Could not configure WireGuard interface iptables rules (insufficient permissions)"
        echo "🔄 VPN connection established - traffic routing may not be fully controlled"
    fi
else
    echo "⚠️  Skipping WireGuard iptables rules (kill-switch disabled)"
fi

# Fix routing priority for external traffic in hostNetwork mode
if [ -n "$KUBERNETES_SERVICE_HOST" ] && ip route show | grep -q "hostNetwork\|ens160"; then
    echo "🔧 Fixing external traffic routing priority..."
    
    # Add higher priority rule to route external traffic through VPN
    if ip rule add from all to 0.0.0.0/0 lookup 51820 priority 100 2>/dev/null; then
        echo "✅ Added high-priority VPN routing rule"
    else
        echo "⚠️  Could not add VPN routing rule (insufficient permissions)"
    fi
    
    # Ensure external traffic uses VPN by modifying default route priority
    if ip route add default dev wg0 metric 50 2>/dev/null; then
        echo "✅ Added high-priority VPN default route"
    else
        echo "⚠️  Could not modify default route priority"
    fi
fi

echo "✅ VPN connection established with bypass routes for internal connectivity"

# Validate VPN connection is working
echo "🔍 Validating VPN connection..."
if ! /usr/local/bin/validate-wireguard.sh; then
    echo "❌ ERROR: VPN validation failed - sidecar will exit"
    exit 1
fi

echo "✅ VPN setup completed successfully"

# Start proxy servers if proxy mode is enabled
if [ "$ENABLE_PROXY_MODE" = "true" ]; then
    echo "🌐 Starting proxy servers (proxy pool mode)..."
    
    # Configure proxies
    /usr/local/bin/configure-proxy.sh
    
    # Start dante SOCKS5 server
    echo "🚀 Starting dante SOCKS5 server..."
    danted -f /etc/danted.conf &
    DANTE_PID=$!
    
    # Start tinyproxy HTTP server (optional - SOCKS5 is primary)
    echo "🚀 Starting tinyproxy HTTP server..."
    tinyproxy -c /etc/tinyproxy/tinyproxy.conf 2>/dev/null &
    TINYPROXY_PID=$!
    
    # Wait for proxies to start
    sleep 3
    
    # Verify SOCKS5 proxy is running (required)
    if ps -p $DANTE_PID > /dev/null; then
        echo "✅ SOCKS5 proxy (dante) started (PID: $DANTE_PID)"
        echo "   Listening on: 0.0.0.0:${SOCKS5_PORT:-1080}"
    else
        echo "❌ ERROR: SOCKS5 proxy (dante) failed to start"
        echo "❌ CRITICAL: Proxy pool mode requires SOCKS5 proxy"
        exit 1
    fi
    
    # Check HTTP proxy (optional - warn if failed)
    if ps -p $TINYPROXY_PID > /dev/null; then
        echo "✅ HTTP proxy (tinyproxy) started (PID: $TINYPROXY_PID)"
        echo "   Listening on: 0.0.0.0:${HTTP_PORT:-3128}"
    else
        echo "⚠️  WARNING: HTTP proxy (tinyproxy) failed to start - SOCKS5 proxy still available"
        TINYPROXY_PID=""
    fi
    
    echo "✅ Proxy pool mode active (SOCKS5 ready)"
else
    echo "⚠️  Proxy mode disabled (sidecar mode)"
fi

# Start health probe server on port 9999 (if enabled)
if [ "$ENABLE_HEALTH_PROBE" = "true" ]; then
    echo "🩺 Starting health probe server on :9999..."
    {
        while true; do
            {
                echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\n\r\nVPN is active"
            } | nc -l -p 9999 >/dev/null 2>&1 || sleep 1
        done
    } &
    HEALTH_PID=$!
    echo "✅ Health probe server started (PID: $HEALTH_PID)"
else
    echo "⚠️  Health probe disabled via ENABLE_HEALTH_PROBE=false"
fi

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
