#!/bin/bash
set -e

echo "🔧 Configuring proxy servers for VPN proxy pool mode..."

# Environment variables (with defaults)
SOCKS5_PORT=${SOCKS5_PORT:-1080}
HTTP_PORT=${HTTP_PORT:-3128}
PROXY_AUTH=${PROXY_AUTH:-false}
PROXY_USERNAME=${PROXY_USERNAME:-proxyuser}
PROXY_PASSWORD=${PROXY_PASSWORD:-proxypass}
DEBUG_LOGGING=${DEBUG_LOGGING:-false}

# Set log level based on debug mode
if [ "$DEBUG_LOGGING" = "true" ]; then
    DANTE_LOG_LEVEL="connect"  # Logs all connection attempts with URLs
    echo "🐛 DEBUG_LOGGING enabled - SOCKS5 requests will be logged to file and container output"
else
    DANTE_LOG_LEVEL="error"
fi

# Always log to file for metrics exporter
DANTE_LOG_OUTPUT="/var/log/danted.log"

# Create log file
touch $DANTE_LOG_OUTPUT
chmod 666 $DANTE_LOG_OUTPUT

# ========================================
# Configure dante-server (SOCKS5)
# ========================================
echo "🔧 Configuring dante-server (SOCKS5) on port $SOCKS5_PORT..."

cat > /etc/danted.conf << EOF_DANTE
# Dante SOCKS5 server configuration
# Generated: $(date)

logoutput: $DANTE_LOG_OUTPUT

# Listen on all interfaces
internal: 0.0.0.0 port = $SOCKS5_PORT
external: wg0

# Security methods
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

# Block everything else
socks block {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}
EOF_DANTE

echo "✅ Dante configuration created at /etc/danted.conf"

# ========================================
# Configure tinyproxy (HTTP)
# ========================================
echo "🔧 Configuring tinyproxy (HTTP) on port $HTTP_PORT..."

cat > /etc/tinyproxy/tinyproxy.conf << EOF_TINY
# Tinyproxy HTTP proxy configuration
# Generated: $(date)

# Proxy settings
Port $HTTP_PORT
Listen 0.0.0.0
Timeout 600
DefaultErrorFile "/usr/share/tinyproxy/default.html"
StatFile "/usr/share/tinyproxy/stats.html"
LogFile "/var/log/tinyproxy/tinyproxy.log"
LogLevel Info
PidFile "/var/run/tinyproxy/tinyproxy.pid"

# Performance
MaxClients 100
MinSpareServers 5
MaxSpareServers 20
StartServers 10
MaxRequestsPerChild 0

# Access control  
Allow 0.0.0.0/0

# Forwarding
Upstream none

# VIA header
ViaProxyName "VPN-Proxy-Pool"

# Disable URL filtering
FilterURLs Off
FilterExtended Off
EOF_TINY

echo "✅ Tinyproxy configuration created at /etc/tinyproxy/tinyproxy.conf"

# ========================================
# Summary
# ========================================
echo "✅ Proxy configuration complete"
echo "   SOCKS5 (dante): Port $SOCKS5_PORT, Auth: $PROXY_AUTH, Debug: $DEBUG_LOGGING"
echo "   HTTP (tinyproxy): Port $HTTP_PORT, Auth: disabled (not supported)"
if [ "$DEBUG_LOGGING" = "true" ]; then
    echo "   📝 Debug logging: SOCKS5 requests will be logged to $DANTE_LOG_OUTPUT"
fi
