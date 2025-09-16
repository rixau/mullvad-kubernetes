# Mullvad Kubernetes WireGuard Sidecar

A secure, production-ready WireGuard sidecar container for Mullvad VPN integration with Kubernetes and Docker Compose environments.

## 🔒 Security Features

### No-Leak Egress Policy
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

### Graceful Exit Handling
- **Signal Handling**: Responds to SIGTERM, SIGINT, SIGQUIT
- **Clean Shutdown**: Properly tears down VPN and restores iptables
- **Fast Restart**: Enables quick Deployment restarts on failure

### Continuous Monitoring
- **Active Monitoring**: Checks VPN status every 30 seconds
- **Validation**: Periodic external IP verification every 5 minutes
- **Auto-Recovery**: Automatic reconnection on tunnel failure

## 🚀 Quick Start

### 1. Get Mullvad Configuration

1. Go to [Mullvad WireGuard Config](https://mullvad.net/en/account/wireguard-config)
2. Download your WireGuard configuration file(s)
3. Place them in the `./conf/` directory

### 2. Test Locally

```bash
# Clone the repository
git clone https://github.com/rixau/mullvad-kubernetes.git
cd mullvad-kubernetes

# Place your Mullvad config in conf/
# Example: ./conf/br-sao-wg-001.conf

# Run the test
./test-mullvad.sh
```

### 3. Docker Compose Integration

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
    volumes:
      - ./conf/your-config.conf:/etc/wireguard/wg0.conf:ro
    ports:
      - "9999:9999"  # Health probe
```

### 4. Kubernetes Integration

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

The health probe integrates with popular monitoring systems:

- **Prometheus**: Scrape `:9999` endpoint
- **Kubernetes**: Native health checks
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
