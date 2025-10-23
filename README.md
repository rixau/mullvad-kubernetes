# Mullvad Kubernetes WireGuard Sidecar

A secure, production-ready WireGuard sidecar container for Mullvad VPN integration with Kubernetes and Docker Compose environments.

## 🔒 Security Features

### Configurable Security (Environment Variables)
- **`ENABLE_KILL_SWITCH=false`** (default): Disable iptables kill-switch for compatibility
- **`ENABLE_DNS_CONFIG=false`** (default): Skip DNS modification to avoid conflicts
- **`ENABLE_BYPASS_ROUTES=true`** (default): Keep internal network bypass routes
- **`ENABLE_HEALTH_PROBE=true`** (default): Enable health monitoring on port 9999
- **`ENABLE_PROXY_MODE=true`**: Enable SOCKS5 and HTTP proxy servers
- **`SOCKS5_PORT=1080`**: SOCKS5 proxy port
- **`HTTP_PORT=3128`**: HTTP proxy port (tinyproxy)
- **`METRICS_PORT=9090`**: Prometheus metrics exporter port

### No-Leak Egress Policy (When Enabled)
- **Kill Switch**: If the VPN tunnel drops, the OUTPUT iptables policy drops all non-WireGuard traffic
- **Zero Leak Guarantee**: No traffic can escape the VPN tunnel, even during connection failures
- **Automatic Recovery**: VPN reconnection restores normal traffic flow

### Handshake Exception
- **Initial Connection**: Allows UDP traffic to Mullvad peer for WireGuard handshake
- **Smart Routing**: Prevents kill-switch from blocking the initial VPN connection
- **Dynamic Configuration**: Automatically extracts peer info from mounted config file

## 🩺 Health & Monitoring

### Health Probe Endpoint
- **Port 9999**: Simple HTTP endpoint for K8s/Compose health checks
- **Response**: `VPN is active` when tunnel is operational
- **Integration**: Perfect for Kubernetes `livenessProbe` and `readinessProbe`

### Prometheus Metrics
- **Port 9090**: Prometheus metrics exporter (when `METRICS_PORT` is set)
- **Metrics Exposed**:
  - `vpn_connection_status` - VPN connection status (1=up, 0=down)
  - `proxy_active_connections` - Current active proxy connections
  - `proxy_request_rate_permin` - Request rate per minute
  - `proxy_bytes_transferred_total` - Total bytes transferred
  - `proxy_requests_failed_total` - Failed requests counter
  - `proxy_info` - Proxy information gauge

### Graceful Exit Handling
- **Signal Handling**: Responds to SIGTERM, SIGINT, SIGQUIT
- **Clean Shutdown**: Properly tears down VPN and restores iptables
- **Fast Restart**: Enables quick Deployment restarts on failure

### Continuous Monitoring
- **Active Monitoring**: Checks VPN status every 30 seconds
- **Validation**: Periodic external IP verification every 5 minutes
- **Auto-Recovery**: Automatic reconnection on tunnel failure
- **Grafana Dashboard**: Pre-built dashboard for proxy pool monitoring (see [charts/dashboard/](charts/dashboard/))

## 🛠️ Configuration Management

### Deploy Multiple Mullvad Configs
Use the provided script to deploy all WireGuard configs as Kubernetes secrets:

```bash
# Deploy all configs in conf/ directory to specified namespace
./scripts/deploy-configs.sh burban-co-dev-pipeline

# Dry run to see what would be created
./scripts/deploy-configs.sh my-namespace --dry-run
```

This creates secrets like:
- `mullvad-config-free-salmon` (US server)
- `mullvad-config-mature-ibex` (Canada server)
- `mullvad-config-smart-dove` (Brazil server)
- `mullvad-config-mighty-bird` (Brazil server)

### Use Different Configs for Different Services
```yaml
# Service A uses US server
serviceA:
  vpn:
    config:
      secretName: "mullvad-config-free-salmon"

# Service B uses Canada server  
serviceB:
  vpn:
    config:
      secretName: "mullvad-config-mature-ibex"
```

## 🚀 Quick Start

### 1. Get Mullvad Configuration

1. Go to [Mullvad WireGuard Config](https://mullvad.net/en/account/wireguard-config)
2. Download your WireGuard configuration file(s)
3. Place them in the `./conf/` directory

### 2. Build the Image (Optional)

The image is available on GHCR, but you can build it locally:

```bash
# Clone the repository
git clone https://github.com/rixau/mullvad-kubernetes.git
cd mullvad-kubernetes

# Build the Docker image
docker build -t mullvad-kubernetes:latest .
```

### 3. Test Locally

```bash
# Place your Mullvad config in conf/
# Example: ./conf/br-sao-wg-001.conf

# Run the test
./test-mullvad.sh
```

### 4. Docker Compose - Proxy Pool Mode

Run a pool of VPN proxies with different exit locations:

```bash
# Start proxy pool (US, Brazil, Canada)
docker compose up -d

# Check proxy status
docker compose ps

# View metrics
curl http://localhost:19090/metrics  # US proxy
curl http://localhost:19091/metrics  # Brazil proxy
curl http://localhost:19092/metrics  # Canada proxy

# Run test apps (optional)
docker compose -f docker-compose-test.yml up
```

The proxy pool provides:
- **SOCKS5 Proxy**: Ports 10800 (US), 1081 (BR), 1082 (CA)
- **HTTP Proxy**: Ports 13128 (US), 3129 (BR), 3130 (CA)
- **Health Checks**: Ports 9998 (US), 9991 (BR), 9992 (CA)
- **Metrics**: Ports 19090 (US), 19091 (BR), 19092 (CA)

### 5. Docker Compose - Sidecar Integration

Use VPN as a sidecar for your application:

```yaml
services:
  your-app:
    image: your-app:latest
    network_mode: "container:mullvad-sidecar"
    depends_on:
      - mullvad-sidecar

  mullvad-sidecar:
    image: ghcr.io/rixau/mullvad-kubernetes:latest
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    devices:
      - /dev/net/tun
    privileged: true
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
    environment:
      - ENABLE_PROXY_MODE=true
      - METRICS_PORT=9090
    volumes:
      - ./conf/your-config.conf:/etc/wireguard/wg0.conf:ro
    ports:
      - "1080:1080"  # SOCKS5
      - "9999:9999"  # Health probe
      - "9090:9090"  # Metrics
```

### 6. Helm Charts (Recommended)

The easiest way to deploy to Kubernetes is using the provided Helm charts:

```bash
# 1. Deploy Mullvad configs as secrets
./scripts/deploy-configs.sh my-namespace

# 2. Install proxy chart
helm install mullvad-proxy ./charts/proxy --namespace vpn-proxy-pool

# 3. Install dashboard chart (optional, requires Grafana)
helm install mullvad-dashboards ./charts/dashboard --namespace monitoring
```

See [charts/README.md](charts/README.md) for detailed Helm chart documentation.

### 7. Kubernetes Integration (Manual)

For manual deployment without Helm:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: your-app-with-vpn
spec:
  template:
    spec:
      shareProcessNamespace: true
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      containers:
      - name: your-app
        image: your-app:latest
        # Your app configuration

      - name: mullvad-sidecar
        image: ghcr.io/rixau/mullvad-kubernetes:latest
        securityContext:
          capabilities:
            add:
              - NET_ADMIN
              - SYS_MODULE
          privileged: true
        volumeMounts:
        - name: wireguard-config
          mountPath: /etc/wireguard/wg0.conf
          subPath: wg0.conf
          readOnly: true
        - name: tun-device
          mountPath: /dev/net/tun
        livenessProbe:
          httpGet:
            path: /
            port: 9999
          initialDelaySeconds: 60
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /
            port: 9999
          initialDelaySeconds: 30
          periodSeconds: 10

      volumes:
      - name: wireguard-config
        secret:
          secretName: mullvad-config
      - name: tun-device
        hostPath:
          path: /dev/net/tun
          type: CharDevice
```

## 🔧 Configuration

### Environment Variables

The sidecar automatically detects its environment:
- **Kubernetes**: Configures cluster network bypass routes
- **Docker Compose**: Configures Docker network bypass routes

### Bypass Routes

Internal networks are automatically bypassed to maintain connectivity:
- **Kubernetes**: Pod networks (10.42.0.0/16), Service networks (10.0.0.0/8)
- **Docker**: Bridge networks (172.17-20.0.0/16)
- **Private**: RFC1918 ranges (192.168.0.0/16, 172.16.0.0/12)

### Health Checks

```bash
# Test health probe
curl http://localhost:9999
# Response: "VPN is active"

# Check VPN status
docker exec mullvad-sidecar ip addr show wg0

# View logs
docker logs mullvad-sidecar
```

## 🛡️ Security Architecture

```
┌─────────────────────────────────────────┐
│              Application                 │
│         (shares network with)           │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│           Mullvad Sidecar               │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │        iptables Rules           │   │
│  │                                 │   │
│  │  OUTPUT Policy: DROP            │   │
│  │  ✅ Allow: wg0 interface        │   │
│  │  ✅ Allow: Mullvad UDP handshake│   │
│  │  ✅ Allow: Established conns    │   │
│  │  ✅ Allow: Loopback             │   │
│  │  ✅ Allow: Internal networks    │   │
│  │  ❌ Drop: Everything else       │   │
│  └─────────────────────────────────┘   │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │      WireGuard Interface        │   │
│  │                                 │   │
│  │  wg0: 10.x.x.x/32              │   │
│  │  Endpoint: Mullvad Server       │   │
│  │  Status: Health Check :9999     │   │
│  └─────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

## 🧪 Testing

The `test-mullvad.sh` script provides comprehensive testing:

1. **Config Validation**: Checks for WireGuard config files
2. **IP Verification**: Compares real vs VPN IP addresses
3. **Health Probe**: Tests the :9999 health endpoint
4. **Continuous Monitoring**: Shows ongoing IP checks

## 📝 Troubleshooting

### Common Issues

1. **No Config Files**
   ```bash
   # Error: No WireGuard configuration files found
   # Solution: Download from https://mullvad.net/en/account/wireguard-config
   ```

2. **Permission Denied**
   ```bash
   # Ensure privileged mode and NET_ADMIN capability
   privileged: true
   cap_add: [NET_ADMIN, SYS_MODULE]
   ```

3. **Health Check Fails**
   ```bash
   # Check if port 9999 is accessible
   curl http://localhost:9999
   ```

### Debug Commands

```bash
# Check WireGuard status
docker exec mullvad-sidecar wg show

# Check iptables rules
docker exec mullvad-sidecar iptables -L OUTPUT -v

# Check routes
docker exec mullvad-sidecar ip route

# Monitor logs
docker logs -f mullvad-sidecar
```

## 🔮 Advanced Usage

### Custom Health Checks

```yaml
# Kubernetes liveness probe with custom timeout
livenessProbe:
  httpGet:
    path: /
    port: 9999
  initialDelaySeconds: 60
  periodSeconds: 30
  timeoutSeconds: 5
  failureThreshold: 3
```

### Multiple Configs

```bash
# Test different server locations
./conf/us-nyc-wg-001.conf    # US - New York
./conf/se-got-wg-001.conf    # Sweden - Gothenburg  
./conf/br-sao-wg-001.conf    # Brazil - São Paulo
```

### Production Deployment

For production use, consider:
- Using Kubernetes Secrets for WireGuard configs
- Implementing resource limits and requests
- Setting up monitoring and alerting on health checks
- Using Pod Disruption Budgets for availability

## 📊 Monitoring Integration

### Prometheus & Grafana

The proxy pool includes full Prometheus metrics and a pre-built Grafana dashboard.

#### Automatic Prometheus Discovery

The Helm chart includes Prometheus service annotations for automatic discovery:

```yaml
# Service annotations (automatically added by Helm chart)
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "9090"
  prometheus.io/path: "/metrics"
```

Prometheus will automatically discover and scrape metrics via its `kubernetes-service-endpoints` job.

#### Manual Prometheus Configuration

For manual setup, add a scrape job:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'mullvad-proxy'
    static_configs:
      - targets: 
          - 'mullvad-proxy-us:9090'
          - 'mullvad-proxy-br:9090'
          - 'mullvad-proxy-ca:9090'
```

#### Grafana Dashboard

**Pre-built Dashboard** (`charts/dashboard/dashboards/proxy-pool-dashboard.json`):
- VPN connection status per location
- Request rates and failures
- Active connections over time
- Data transfer statistics
- Multi-location comparison

Install the dashboard via Helm:
```bash
helm install mullvad-dashboards ./charts/dashboard --namespace monitoring
```

#### Available Metrics

- `vpn_connection_status` - VPN tunnel status (1=up, 0=down)
- `proxy_info` - Proxy identification and metadata
- `proxy_bytes_transferred_total` - Total bytes transferred
- `proxy_requests_successful_total` - Successful requests counter
- `proxy_requests_failed_total` - Failed requests counter
- `proxy_success_rate_percent` - Success rate percentage
- `proxy_active_connections` - Current active connections
- `proxy_request_rate_permin` - Request rate per minute
- `proxy_latency_ms` - Connection latency
- `proxy_download_speed_mbps` - Download speed

### Health Check Integration

The health probe integrates with popular monitoring systems:

- **Prometheus**: Scrape `:9090` metrics endpoint
- **Health Checks**: Basic health on `:9999` endpoint
- **Kubernetes**: Native liveness/readiness probes
- **Docker**: Container health status
- **Custom**: HTTP monitoring tools

## 🤝 Contributing

Contributions welcome! Please ensure:
- Security features are maintained
- Health checks continue working
- Documentation is updated
- Tests pass locally

## 📄 License

MIT License - see LICENSE file for details.
