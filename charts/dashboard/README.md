# Mullvad Proxy Pool Dashboards Helm Chart

This Helm chart deploys Grafana dashboards for monitoring the Mullvad VPN Proxy Pool.

## Overview

This chart creates Kubernetes ConfigMaps containing Grafana dashboard definitions. When deployed to a cluster with Grafana, the dashboards will be automatically discovered and imported.

## Prerequisites

- Kubernetes cluster with Grafana installed
- Grafana configured to auto-discover dashboards via ConfigMap labels
- Prometheus as a data source in Grafana

## Installation

```bash
# Install to the monitoring namespace (default)
helm install mullvad-dashboards ./chart-dashboards

# Install to a custom namespace
helm install mullvad-dashboards ./chart-dashboards \
  --set grafana.namespace=custom-namespace
```

## Configuration

### Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `grafana.namespace` | Namespace where Grafana is deployed | `monitoring` |
| `grafana.labels` | Labels for dashboard ConfigMaps | `{"grafana_dashboard": "1"}` |
| `grafana.annotations` | Annotations for dashboard ConfigMaps | `{}` |
| `dashboards.proxyPoolPerformance.enabled` | Enable proxy pool performance dashboard | `true` |

## Dashboards

### Proxy Pool Performance Dashboard

Monitors:
- **VPN Status Table**: Per-proxy VPN connection status, request rates, and data transfer
- **Connection Latency**: Latency measurements for each proxy location
- **Download Speed**: Download speed metrics per proxy
- **Failed Requests**: Failed request tracking over time
- **Data Transfer Rate**: Bytes transferred per second per proxy
- **Requests by Client**: Request distribution across client containers

## Uninstallation

```bash
helm uninstall mullvad-dashboards
```

## Development

To update dashboards:

1. Export the dashboard JSON from Grafana
2. Place it in `chart-dashboards/dashboards/`
3. Update the chart version in `Chart.yaml`
4. Redeploy the chart

## Links

- [Main Chart](../proxy/): Mullvad Proxy Pool deployment chart
- [Repository](https://github.com/rixau/mullvad-kubernetes)

