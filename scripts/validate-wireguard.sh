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

# Basic validation - just validate that wg0 interface exists and has an IP
# The actual external IP check will be done by your application
echo "🌐 Basic WireGuard validation - checking wg0 interface..."
if [ -n "$WG_INTERFACE_IP" ]; then
    echo "✅ WireGuard validation successful - wg0 interface active with IP: $WG_INTERFACE_IP"
    echo "📝 Note: External IP routing will be validated by your application"
    exit 0
else
    echo "❌ ERROR: wg0 interface has no IP address"
    exit 1
fi
