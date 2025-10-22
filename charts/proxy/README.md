# Mullvad Proxy Pool Helm Chart

A Helm chart for deploying Mullvad VPN Proxy Pool with SOCKS5 and HTTP proxy support on Kubernetes.

## Overview

This chart deploys multiple Mullvad WireGuard VPN proxy instances to your Kubernetes cluster. Each proxy can be configured with different Mullvad servers for geographic distribution.

## Features

- **Multiple Proxy Locations**: Deploy proxies using different Mullvad servers
- **SOCKS5 & HTTP Support**: Both SOCKS5 (port 1080) and HTTP (port 3128) proxies
- **Health Monitoring**: Built-in health probes on port 9999
- **Prometheus Metrics**: Optional metrics export on port 9090
- **Per-Proxy Configuration**: Individual resource limits and environment variables

## Prerequisites

- Kubernetes cluster (tested on 1.20+)
- Mullvad VPN account with WireGuard configurations
- Kubernetes secrets containing WireGuard configs

## Installation

### 1. Create Mullvad Config Secrets

Use the provided script to deploy all your Mullvad configs as secrets:

```bash
# Deploy configs to a namespace
./scripts/deploy-configs.sh burban-co-dev-pipeline

# Dry run to see what would be created
./scripts/deploy-configs.sh my-namespace --dry-run
```

This creates secrets like:
- `mullvad-config-golden-crab`
- `mullvad-config-free-salmon`
- etc.

### 2. Install the Chart

```bash
# Install with default values
helm install mullvad-proxy-pool ./chart

# Install with custom values
helm install mullvad-proxy-pool ./chart -f my-values.yaml

# Install to a specific namespace
helm install mullvad-proxy-pool ./chart --namespace vpn-proxy-pool
```

## Configuration

### Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Docker image repository | `ghcr.io/rixau/mullvad-kubernetes` |
| `image.tag` | Docker image tag | `0.6.2` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.ports.socks5` | SOCKS5 port | `1080` |
| `service.ports.http` | HTTP proxy port | `3128` |
| `service.ports.health` | Health check port | `9999` |
| `proxies.<name>.enabled` | Enable specific proxy | `true` |
| `proxies.<name>.replicaCount` | Number of replicas | `1` |
| `proxies.<name>.config.secretName` | Secret containing WireGuard config | Required |
| `proxies.<name>.config.configKey` | Key in secret for config file | `wg0.conf` |
| `proxies.<name>.resources` | Resource requests/limits | See values.yaml |
| `proxies.<name>.env` | Environment variables | See values.yaml |

### Example Custom Values

```yaml
proxies:
  us-proxy:
    enabled: true
    replicaCount: 2
    config:
      secretName: "mullvad-config-us-server"
      configKey: "wg0.conf"
    resources:
      requests:
        cpu: 200m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
    env:
      - name: ENABLE_PROXY_MODE
        value: "true"
      - name: PROXY_NAME
        value: "us-proxy"
      - name: DEBUG_LOGGING
        value: "true"
```

## Usage

### Connect via SOCKS5

```bash
# From within the cluster
curl --socks5 mullvad-proxy-pool:1080 http://httpbin.org/ip

# Port-forward for local testing
kubectl port-forward svc/mullvad-proxy-pool 1080:1080
curl --socks5 localhost:1080 http://httpbin.org/ip
```

### Connect via HTTP Proxy

```bash
# From within the cluster
curl --proxy mullvad-proxy-pool:3128 http://httpbin.org/ip

# Port-forward for local testing
kubectl port-forward svc/mullvad-proxy-pool 3128:3128
curl --proxy localhost:3128 http://httpbin.org/ip
```

### Health Checks

```bash
# Check health endpoint
kubectl port-forward svc/mullvad-proxy-pool 9999:9999
curl http://localhost:9999
```

### Prometheus Metrics

```bash
# Access metrics (if METRICS_PORT is set)
kubectl port-forward svc/mullvad-proxy-pool 9090:9090
curl http://localhost:9090/metrics
```

## Monitoring

For Grafana dashboards, install the companion dashboard chart:

```bash
helm install mullvad-dashboards ./chart-dashboards
```

See [chart-dashboards/README.md](../chart-dashboards/README.md) for details.

## Uninstallation

```bash
helm uninstall mullvad-proxy-pool
```

## Troubleshooting

### Pod Not Starting

Check pod logs:
```bash
kubectl logs <pod-name>
```

Common issues:
- Missing WireGuard config secret
- Invalid WireGuard configuration
- Insufficient privileges (needs NET_ADMIN capability)

### VPN Not Connecting

Check WireGuard status inside pod:
```bash
kubectl exec -it <pod-name> -- wg show
```

### Health Checks Failing

Verify VPN connection:
```bash
kubectl exec -it <pod-name> -- curl http://httpbin.org/ip
```

## Links

- [Dashboard Chart](../chart-dashboards/): Grafana dashboards for monitoring
- [Repository](https://github.com/rixau/mullvad-kubernetes)
- [Mullvad VPN](https://mullvad.net/)

