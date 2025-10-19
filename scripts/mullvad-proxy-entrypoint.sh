#!/bin/bash

# Mullvad WireGuard SOCKS5 Proxy Pool Entrypoint
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
    
    # Kill metrics exporter
    if [ -n "$METRICS_PID" ]; then
        kill $METRICS_PID 2>/dev/null || true
        echo "✅ Metrics exporter stopped"
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

echo "🚀 Starting Mullvad WireGuard SOCKS5 Proxy..."

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
echo "📦 SOCKS5 Proxy Pool Mode - No internal routing needed"

# Extract Mullvad peer info for handshake exception
MULLVAD_ENDPOINT=$(grep "^Endpoint" /etc/wireguard/wg0.conf | cut -d'=' -f2 | tr -d ' ')
MULLVAD_IP=$(echo $MULLVAD_ENDPOINT | cut -d':' -f1)
MULLVAD_PORT=$(echo $MULLVAD_ENDPOINT | cut -d':' -f2)

echo "🔐 Using mounted Mullvad WireGuard configuration..."
echo "📄 Mullvad endpoint: $MULLVAD_ENDPOINT"

# CRITICAL: Add bypass route for Mullvad endpoint BEFORE starting WireGuard
# This prevents routing loop where handshake packets try to go through the VPN that doesn't exist yet
echo "🔧 Adding bypass route for Mullvad endpoint..."
if ip route add $MULLVAD_IP via $DEFAULT_GW dev $DEFAULT_IFACE 2>/dev/null; then
    echo "✅ Mullvad endpoint bypass route added: $MULLVAD_IP via $DEFAULT_GW"
else
    echo "⚠️  Could not add bypass route for Mullvad endpoint (may already exist)"
    echo "   This is critical for handshake establishment!"
fi

# Kill-switch not needed for SOCKS5 proxy pool mode

# Start WireGuard
echo "🔗 Starting Mullvad WireGuard connection..."

# Disable resolvconf to avoid DNS issues
export RESOLVCONF=no

# Start WireGuard
if wg-quick up wg0 2>&1 | tee /tmp/wg-output; then
    echo "✅ WireGuard started successfully"
elif grep -q "resolvconf: command not found" /tmp/wg-output; then
    echo "⚠️  DNS setup warning (interface still up)"
else
    echo "❌ ERROR: WireGuard failed to start"
    cat /tmp/wg-output
    exit 1
fi

echo "⚠️  Using default DNS (SOCKS5 proxy pool mode - no DNS override needed)"

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

echo "✅ VPN connection established"

# Validate VPN connection is working
echo "🔍 Validating VPN connection..."
if ! /usr/local/bin/validate-wireguard.sh; then
    echo "❌ ERROR: VPN validation failed - proxy will exit"
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
    
    # Start metrics exporter if available
    if [ -f /usr/local/bin/metrics-exporter.py ]; then
        echo "📊 Starting metrics exporter..."
        python3 /usr/local/bin/metrics-exporter.py &
        METRICS_PID=$!
        echo "✅ Metrics exporter started (PID: $METRICS_PID)"
        echo "   Metrics endpoint: http://0.0.0.0:${METRICS_PORT:-9090}/metrics"
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
    echo "⚠️  Proxy mode disabled (standalone mode)"
fi

# Start health probe server on port 9999 (if enabled)
if [ "$ENABLE_HEALTH_PROBE" = "true" ]; then
    echo "🩺 Starting health probe server on :9999..."
    python3 -c '
import socket
import signal
import sys
import subprocess
import re

def signal_handler(sig, frame):
    sys.exit(0)

signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

def check_vpn_health():
    """Check VPN health by validating WireGuard handshake freshness"""
    try:
        # Run wg show to get handshake info
        result = subprocess.run(
            ["wg", "show", "wg0"],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode != 0:
            return False, "wg0 interface not found"
        
        output = result.stdout
        
        # Check if peer is configured
        if "peer:" not in output:
            return False, "no peer configured"
        
        # Check handshake freshness
        if "latest handshake:" in output:
            handshake_line = [line for line in output.split("\n") if "latest handshake:" in line]
            if handshake_line:
                handshake_info = handshake_line[0].split("latest handshake:")[-1].strip()
                
                # Fail if handshake is too old (days, hours, or >3 minutes)
                if "day" in handshake_info or "hour" in handshake_info:
                    return False, f"stale handshake: {handshake_info}"
                
                # Check minutes
                minutes_match = re.search(r"(\d+)\s+minute", handshake_info)
                if minutes_match:
                    minutes = int(minutes_match.group(1))
                    if minutes > 3:
                        return False, f"handshake {minutes}min old (max 3min)"
                
                # Fresh handshake (seconds or <3 minutes)
                return True, f"healthy: {handshake_info}"
        else:
            # No handshake yet - check if we have been sending data without response
            # If transfer shows more than 1KB sent but 0 received, credentials are invalid
            transfer_lines = [line for line in output.split("\n") if "transfer:" in line]
            if transfer_lines:
                transfer_info = transfer_lines[0]
                # Extract sent bytes - look for pattern like 1.45 KiB sent or 244 B sent
                if "sent" in transfer_info:
                    sent_match = re.search(r"(\d+\.?\d*)\s+(B|KiB|MiB)\s+sent", transfer_info)
                    if sent_match:
                        sent_value = float(sent_match.group(1))
                        sent_unit = sent_match.group(2)
                        
                        # Convert to bytes
                        sent_bytes = sent_value
                        if sent_unit == "KiB":
                            sent_bytes = sent_value * 1024
                        elif sent_unit == "MiB":
                            sent_bytes = sent_value * 1024 * 1024
                        
                        # If we have sent more than 1KB but received nothing and no handshake, credentials are bad
                        if sent_bytes > 1024 and "0 B received" in transfer_info:
                            return False, "invalid credentials: sending packets but no handshake"
            
            # Still in grace period (first 60 seconds)
            return True, "establishing: waiting for first handshake"
        
        return True, "vpn active"
        
    except Exception as e:
        return False, f"health check error: {str(e)}"

server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server_socket.bind(("0.0.0.0", 9999))
server_socket.listen(5)

while True:
    try:
        client_socket, address = server_socket.accept()
        try:
            client_socket.recv(1024)  # Read the request
            
            # Actually check VPN health
            is_healthy, status_msg = check_vpn_health()
            
            if is_healthy:
                response = f"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {len(status_msg)}\r\n\r\n{status_msg}".encode()
            else:
                error_msg = f"VPN unhealthy: {status_msg}"
                response = f"HTTP/1.1 503 Service Unavailable\r\nContent-Type: text/plain\r\nContent-Length: {len(error_msg)}\r\n\r\n{error_msg}".encode()
            
            client_socket.sendall(response)
        finally:
            client_socket.close()
    except Exception:
        pass
' &
    HEALTH_PID=$!
    echo "✅ Health probe server started (PID: $HEALTH_PID)"
    echo "   Health checks now validate WireGuard handshake freshness"
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
                echo "❌ ERROR: VPN validation failed during monitoring - proxy will exit"
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
                echo "❌ ERROR: VPN reconnection failed validation - proxy will exit"
                exit 1
            fi
        else
            echo "❌ ERROR: VPN reconnection failed - proxy will exit"
            exit 1
        fi
    fi
    sleep 30
done
