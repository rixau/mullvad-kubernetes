#!/bin/bash
set -e

# Deploy Mullvad WireGuard configs to Kubernetes cluster
# Usage: ./scripts/deploy-configs.sh [namespace] [--dry-run]

NAMESPACE="${1:-default}"
DRY_RUN="${2}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CONF_DIR="$REPO_ROOT/conf"

echo -e "${BLUE}🚀 Mullvad Config Deployment Script${NC}"
echo -e "${BLUE}📁 Config directory: $CONF_DIR${NC}"
echo -e "${BLUE}🎯 Target namespace: $NAMESPACE${NC}"

# Check if conf directory exists
if [ ! -d "$CONF_DIR" ]; then
    echo -e "${RED}❌ Error: Config directory not found at $CONF_DIR${NC}"
    exit 1
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ Error: kubectl not found. Please install kubectl.${NC}"
    exit 1
fi

# Check cluster connectivity
echo -e "${YELLOW}🔍 Testing cluster connectivity...${NC}"
if ! timeout 10 kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Error: Cannot connect to Kubernetes cluster${NC}"
    echo -e "${YELLOW}💡 Try: source ~/.bashrc && kubectl cluster-info${NC}"
    exit 1
fi

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo -e "${YELLOW}⚠️  Namespace '$NAMESPACE' does not exist${NC}"
    if [ "$DRY_RUN" != "--dry-run" ]; then
        read -p "Create namespace '$NAMESPACE'? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kubectl create namespace "$NAMESPACE"
            echo -e "${GREEN}✅ Created namespace '$NAMESPACE'${NC}"
        else
            echo -e "${RED}❌ Aborted: Namespace required${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}🔍 [DRY RUN] Would create namespace '$NAMESPACE'${NC}"
    fi
fi

# Find all .conf files
CONF_FILES=($(find "$CONF_DIR" -name "*.conf" -type f))

if [ ${#CONF_FILES[@]} -eq 0 ]; then
    echo -e "${YELLOW}⚠️  No .conf files found in $CONF_DIR${NC}"
    exit 0
fi

echo -e "${GREEN}📋 Found ${#CONF_FILES[@]} WireGuard configuration files:${NC}"

# Process each config file
for conf_file in "${CONF_FILES[@]}"; do
    # Extract filename without extension
    filename=$(basename "$conf_file")
    config_name="${filename%.conf}"
    secret_name="mullvad-config-${config_name}"
    
    echo -e "${BLUE}🔧 Processing: $filename${NC}"
    
    # Extract server info from config for display
    if [ -f "$conf_file" ]; then
        device_name=$(grep "^# Device:" "$conf_file" | cut -d':' -f2 | xargs || echo "Unknown")
        vip_address=$(grep "^Address" "$conf_file" | cut -d'=' -f2 | cut -d',' -f1 | xargs || echo "Unknown")
        endpoint=$(grep "^Endpoint" "$conf_file" | cut -d'=' -f2 | xargs || echo "Unknown")
        
        echo -e "   📍 Device: $device_name"
        echo -e "   🌐 VPN IP: $vip_address"
        echo -e "   🖥️  Server: $endpoint"
    fi
    
    # Check if secret already exists
    if kubectl get secret "$secret_name" -n "$NAMESPACE" &> /dev/null; then
        echo -e "${YELLOW}   ⚠️  Secret '$secret_name' already exists${NC}"
        if [ "$DRY_RUN" != "--dry-run" ]; then
            read -p "   Replace existing secret? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                kubectl delete secret "$secret_name" -n "$NAMESPACE"
                echo -e "${GREEN}   🗑️  Deleted existing secret${NC}"
            else
                echo -e "${YELLOW}   ⏭️  Skipping $filename${NC}"
                continue
            fi
        else
            echo -e "${YELLOW}   🔍 [DRY RUN] Would replace existing secret${NC}"
            continue
        fi
    fi
    
    # Create the secret
    if [ "$DRY_RUN" = "--dry-run" ]; then
        echo -e "${YELLOW}   🔍 [DRY RUN] Would create secret: $secret_name${NC}"
    else
        if kubectl create secret generic "$secret_name" \
            --from-file=wg0.conf="$conf_file" \
            -n "$NAMESPACE" &> /dev/null; then
            echo -e "${GREEN}   ✅ Created secret: $secret_name${NC}"
        else
            echo -e "${RED}   ❌ Failed to create secret: $secret_name${NC}"
        fi
    fi
    echo
done

echo -e "${GREEN}🎉 Deployment Summary:${NC}"
echo -e "${GREEN}   📁 Processed: ${#CONF_FILES[@]} config files${NC}"
echo -e "${GREEN}   🎯 Namespace: $NAMESPACE${NC}"

if [ "$DRY_RUN" != "--dry-run" ]; then
    echo -e "${BLUE}📋 Created secrets:${NC}"
    kubectl get secrets -n "$NAMESPACE" | grep "mullvad-config-" || echo -e "${YELLOW}   No mullvad-config secrets found${NC}"
else
    echo -e "${YELLOW}🔍 This was a dry run. Use without --dry-run to actually create secrets.${NC}"
fi

echo
echo -e "${BLUE}💡 Usage in Helm values:${NC}"
echo -e "${BLUE}   vpn:${NC}"
echo -e "${BLUE}     config:${NC}"
echo -e "${BLUE}       secretName: \"mullvad-config-[config-name]\"${NC}"
echo -e "${BLUE}       configKey: \"wg0.conf\"${NC}"

echo
echo -e "${GREEN}✅ Mullvad config deployment complete!${NC}"
