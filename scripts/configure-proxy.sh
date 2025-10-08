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

# ========================================
# Configure dante-server (SOCKS5)
# ========================================
echo "🔧 Configuring dante-server (SOCKS5) on port $SOCKS5_PORT..."

cat > /etc/danted.conf << EOF
# Dante SOCKS5 server configuration
# Generated: $(date)

logoutput: /var/log/danted.log

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
    log: error
}

# SOCKS rules
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: error
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
    log: error
}

# SOCKS rules
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: error
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
echo "   SOCKS5 (dante): Port $SOCKS5_PORT, Auth: $PROXY_AUTH"
echo "   HTTP (tinyproxy): Port $HTTP_PORT, Auth: disabled (not supported)"
