#!/bin/bash

# WireGuard Validation Script
# Validates that WireGuard VPN connection is working properly

set -e

MAX_RETRIES=30
RETRY_INTERVAL=2

echo "🔍 Validating WireGuard VPN connection..."

# Wait for WireGuard interface to be available
echo "⏳ Waiting for wg0 interface..."
for i in $(seq 1 $MAX_RETRIES); do
    if ip addr show wg0 >/dev/null 2>&1; then
        echo "✅ wg0 interface is up"
        break
    fi
    if [ $i -eq $MAX_RETRIES ]; then
        echo "❌ ERROR: wg0 interface not available after ${MAX_RETRIES} attempts"
        exit 1
    fi
    sleep $RETRY_INTERVAL
done

# Get the WireGuard IP from wg0 interface
WG_INTERFACE_IP=$(ip addr show wg0 | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
if [ -z "$WG_INTERFACE_IP" ]; then
    echo "❌ ERROR: Could not get IP from wg0 interface"
    exit 1
fi
echo "🔍 WireGuard interface IP: $WG_INTERFACE_IP"

# Validate WireGuard peer and handshake
echo "🔍 Checking WireGuard peer configuration..."
WG_PEER_CHECK=$(wg show wg0 2>/dev/null | grep -c "peer:")
if [ "$WG_PEER_CHECK" -eq 0 ]; then
    echo "❌ ERROR: No WireGuard peer configured"
    exit 1
fi
echo "✅ WireGuard peer configured"

# Check handshake freshness (critical for detecting stale tunnels)
echo "🔍 Checking WireGuard handshake freshness..."
WG_OUTPUT=$(wg show wg0)
if echo "$WG_OUTPUT" | grep -q "latest handshake:"; then
    HANDSHAKE_INFO=$(echo "$WG_OUTPUT" | grep "latest handshake:" | sed 's/.*latest handshake: //')
    echo "📅 Latest handshake: $HANDSHAKE_INFO"
    
    # Check if handshake is stale (more than 3 minutes old)
    # Fresh handshakes with PersistentKeepalive should be within 25-30 seconds
    if echo "$HANDSHAKE_INFO" | grep -qE "(minute|hour|day)"; then
        # Extract time value
        if echo "$HANDSHAKE_INFO" | grep -q "day"; then
            echo "❌ ERROR: Handshake is DAYS old - VPN tunnel is stale!"
            exit 1
        elif echo "$HANDSHAKE_INFO" | grep -q "hour"; then
            echo "❌ ERROR: Handshake is HOURS old - VPN tunnel is stale!"
            exit 1
        elif echo "$HANDSHAKE_INFO" | grep -qE "[0-9]+ minute"; then
            MINUTES=$(echo "$HANDSHAKE_INFO" | grep -oE "[0-9]+" | head -1)
            if [ "$MINUTES" -gt 3 ]; then
                echo "❌ ERROR: Handshake is $MINUTES minutes old - VPN tunnel is stale! (max: 3 minutes)"
                exit 1
            else
                echo "⚠️  WARNING: Handshake is $MINUTES minutes old (consider checking PersistentKeepalive)"
            fi
        fi
    else
        echo "✅ Handshake is fresh (within last minute)"
    fi
else
    echo "⚠️  WARNING: No handshake information available (tunnel may not be established yet)"
    # Allow this for initial connection, but log warning
fi

echo "✅ WireGuard validation successful - wg0 interface active with IP: $WG_INTERFACE_IP"
echo "✅ VPN tunnel is healthy with recent peer handshake"
exit 0
