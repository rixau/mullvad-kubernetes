#!/bin/bash

# Proxy Configuration Script for Mullvad VPN
# Configures dante-server (SOCKS5) and tinyproxy (HTTP) over the VPN tunnel

set -e

echo "🔧 Configuring proxy servers for VPN proxy pool mode..."

# Configuration from environment variables
SOCKS5_PORT=${SOCKS5_PORT:-1080}
HTTP_PORT=${HTTP_PORT:-3128}
PROXY_AUTH=${PROXY_AUTH:-false}
PROXY_USERNAME=${PROXY_USERNAME:-proxy}
PROXY_PASSWORD=${PROXY_PASSWORD:-changeme}
DEBUG_LOGGING=${DEBUG_LOGGING:-false}

# Set log level based on debug mode
if [ "$DEBUG_LOGGING" = "true" ]; then
    DANTE_LOG_LEVEL="connect"  # Logs all connection attempts with URLs
    DANTE_LOG_OUTPUT="stderr"   # Output to container logs
    echo "🐛 DEBUG_LOGGING enabled - SOCKS5 requests will be logged to container output"
else
    DANTE_LOG_LEVEL="error"
    DANTE_LOG_OUTPUT="/var/log/danted.log"  # Only errors to file
fi

# ========================================
# Configure dante-server (SOCKS5)
# ========================================
echo "🔧 Configuring dante-server (SOCKS5) on port $SOCKS5_PORT..."

cat > /etc/danted.conf << EOF
# Dante SOCKS5 server configuration
# Generated: $(date)

logoutput: $DANTE_LOG_OUTPUT

# Listen on all interfaces
internal: 0.0.0.0 port = $SOCKS5_PORT

# Route traffic through wg0 VPN interface
external: wg0

# Authentication method
EOF

if [ "$PROXY_AUTH" = "true" ]; then
    echo "🔐 SOCKS5 authentication enabled"
    cat >> /etc/danted.conf << EOF
socksmethod: username

# Client rules
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: $DANTE_LOG_LEVEL
}

# SOCKS rules
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: $DANTE_LOG_LEVEL
    socksmethod: username
}
EOF
else
    echo "⚠️  SOCKS5 authentication disabled"
    cat >> /etc/danted.conf << EOF
socksmethod: none

# Client rules
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: $DANTE_LOG_LEVEL
}

# SOCKS rules
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: $DANTE_LOG_LEVEL
}
EOF
fi

# ========================================
# Configure tinyproxy (HTTP)
# ========================================
echo "🔧 Configuring tinyproxy (HTTP) on port $HTTP_PORT..."

cat > /etc/tinyproxy/tinyproxy.conf << EOF
# Tinyproxy HTTP proxy configuration
# Generated: $(date)

User tinyproxy
Group tinyproxy

Port $HTTP_PORT
Timeout 600

LogFile "/var/log/tinyproxy/tinyproxy.log"
LogLevel Info
PidFile "/run/tinyproxy/tinyproxy.pid"

MaxClients 100

# Allow all connections
Allow 0.0.0.0/0

# VIA Header
ViaProxyName "mullvad-vpn-proxy"

# Disable auth for HTTP proxy (tinyproxy doesn't support auth in free version)
# Use SOCKS5 with auth if you need authentication
DisableViaHeader No
EOF

# Create necessary directories and log files
mkdir -p /var/log/tinyproxy /run/tinyproxy
touch /var/log/danted.log /var/log/tinyproxy/tinyproxy.log
chown -R tinyproxy:tinyproxy /var/log/tinyproxy /run/tinyproxy 2>/dev/null || true

echo "✅ Proxy configuration complete"
echo "   SOCKS5 (dante): Port $SOCKS5_PORT, Auth: $PROXY_AUTH, Debug: $DEBUG_LOGGING"
echo "   HTTP (tinyproxy): Port $HTTP_PORT, Auth: disabled (not supported)"
if [ "$DEBUG_LOGGING" = "true" ]; then
    echo "   📝 Debug logging: SOCKS5 requests will be logged to /var/log/danted.log"
fi
