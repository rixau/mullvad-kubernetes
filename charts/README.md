# Mullvad Kubernetes Helm Charts

This directory contains two version-locked Helm charts for the Mullvad VPN Proxy Pool:

## Charts

### 1. Proxy Chart (`charts/proxy/`)

The main chart that deploys Mullvad WireGuard VPN proxy instances with SOCKS5 and HTTP proxy support.

**Features:**
- Multiple proxy locations (different Mullvad servers)
- SOCKS5 (port 1080) and HTTP (port 3128) proxies
- Health monitoring (port 9999)
- Prometheus metrics (port 9090)
- Per-proxy configuration

**Installation:**
```bash
# Deploy proxy pool
helm install mullvad-proxy ./charts/proxy -f my-values.yaml
```

See [proxy/README.md](proxy/README.md) for detailed documentation.

### 2. Dashboard Chart (`charts/dashboard/`)

Grafana dashboards for monitoring the Mullvad VPN Proxy Pool.

**Features:**
- Proxy pool performance dashboard
- VPN status monitoring
- Request rate and latency tracking
- Data transfer metrics
- Per-client request distribution

**Installation:**
```bash
# Deploy dashboards (requires Grafana)
helm install mullvad-dashboards ./charts/dashboard
```

See [dashboard/README.md](dashboard/README.md) for detailed documentation.

## Version Locking

Both charts are **version-locked** and always have the same version numbers:
- **Chart Version**: The Helm chart template version
- **App Version**: The Docker image version

### Updating Versions

Use the provided version script to update both charts simultaneously:

```bash
# Bump app version (creates new Docker image)
./scripts/version.sh app patch

# Bump chart version (for Helm template changes only)
./scripts/version.sh chart patch
```

**Version Types:**
- `patch`: Bug fixes and minor changes (0.5.0 → 0.5.1)
- `minor`: New features, backward compatible (0.5.0 → 0.6.0)
- `major`: Breaking changes (0.5.0 → 1.0.0)

### Current Versions

| Component | Chart Version | App Version |
|-----------|---------------|-------------|
| Proxy     | 0.5.0         | 0.6.2       |
| Dashboard | 0.5.0         | 0.6.2       |

## Directory Structure

```
charts/
├── README.md              # This file
├── proxy/                 # Main proxy deployment chart
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── templates/
│   └── README.md
└── dashboard/             # Grafana dashboards chart
    ├── Chart.yaml
    ├── values.yaml
    ├── templates/
    ├── dashboards/
    └── README.md
```

## Quick Start

### 1. Create Mullvad Config Secrets

```bash
# Deploy all configs from conf/ directory
./scripts/deploy-configs.sh my-namespace
```

### 2. Install Proxy Chart

```bash
# Install with default values
helm install mullvad-proxy ./charts/proxy --namespace vpn-proxy-pool

# Or with custom values
helm install mullvad-proxy ./charts/proxy -f my-values.yaml --namespace vpn-proxy-pool
```

### 3. Install Dashboard Chart (Optional)

```bash
# Install dashboards to monitoring namespace
helm install mullvad-dashboards ./charts/dashboard --set grafana.namespace=monitoring
```

### 4. Verify Deployment

```bash
# Check proxy pods
kubectl get pods -n vpn-proxy-pool

# Test SOCKS5 proxy
kubectl port-forward svc/mullvad-proxy-pool 1080:1080 -n vpn-proxy-pool
curl --socks5 localhost:1080 http://httpbin.org/ip

# Check health
kubectl port-forward svc/mullvad-proxy-pool 9999:9999 -n vpn-proxy-pool
curl http://localhost:9999
```

## Upgrading

```bash
# Update proxy chart
helm upgrade mullvad-proxy ./charts/proxy -f my-values.yaml

# Update dashboard chart
helm upgrade mullvad-dashboards ./charts/dashboard
```

## Uninstalling

```bash
# Uninstall proxy chart
helm uninstall mullvad-proxy

# Uninstall dashboard chart
helm uninstall mullvad-dashboards
```

## Development

### Version Bump Workflow

1. Make changes to proxy chart templates or dashboard definitions
2. Test changes locally with `helm install --dry-run --debug`
3. Bump version: `./scripts/version.sh chart patch`
4. Script automatically:
   - Updates both Chart.yaml files
   - Commits changes
   - Creates git tag
   - Pushes to remote

### Adding New Proxy Locations

Edit `charts/proxy/values.yaml`:

```yaml
proxies:
  new-location:
    enabled: true
    replicaCount: 1
    config:
      secretName: "mullvad-config-new-location"
      configKey: "wg0.conf"
    env:
      - name: PROXY_NAME
        value: "new-location"
```

## Links

- [Main Repository](https://github.com/rixau/mullvad-kubernetes)
- [Mullvad VPN](https://mullvad.net/)
- [Docker Image](https://github.com/rixau/mullvad-kubernetes/pkgs/container/mullvad-kubernetes)

