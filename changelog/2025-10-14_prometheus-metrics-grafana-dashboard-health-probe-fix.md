# Prometheus Metrics Exporter, Grafana Dashboard, and Health Probe Reliability Fix

**Date:** 2025-10-14  
**Version:** v0.5.6 (from v0.5.3)  
**Type:** Feature Addition + Critical Bug Fix  
**Impact:** High - Adds monitoring capabilities and fixes container restart issues

## 🎯 Project Overview

Implemented comprehensive Prometheus metrics monitoring for the Mullvad VPN proxy pool with per-proxy labeling, created a Grafana dashboard for visualization, and fixed critical liveness probe failures causing container restarts. The metrics system is optional and non-blocking, ensuring backward compatibility while enabling full observability of proxy performance.

## 🚀 Major Accomplishments

### ✅ Prometheus Metrics Exporter (v0.5.4)
- Created Python-based metrics exporter exposing Prometheus-compatible metrics
- Implemented per-proxy metric labeling using `PROXY_NAME` environment variable
- Tracks data transfer, request rate, active connections, failed requests, and VPN status
- Metrics exposed on port 9090 (optional, non-blocking startup)
- Auto-discovers proxy pods when Prometheus is deployed

### ✅ Grafana Dashboard
- Designed comprehensive proxy pool monitoring dashboard
- Features:
  - **Proxy Pool Status Table**: Lists all proxies with VPN status, request rate, data transfer, and active connections
  - **Request Rate & Failures Chart**: Per-minute request rate with failed request overlay
  - **Active Connections Graph**: Real-time connection monitoring per proxy
  - **Data Transfer Chart**: Total bytes and bytes/sec for each proxy
- Dashboard auto-discovers all proxies via `proxy_name` labels
- Located at `monitoring/grafana/dashboards/proxy-pool-dashboard.json`

### ✅ Local Testing Environment
- Created Docker Compose setup (`docker-compose-test.yml`) with:
  - Mullvad proxy instance
  - Prometheus for metrics collection
  - Grafana with pre-provisioned datasources and dashboards
  - Test client for generating traffic
- Enables local testing before cluster deployment

### ✅ Health Probe Reliability Fix (v0.5.6) 🔥
- **Critical Fix**: Replaced flaky `nc`-based health probe with reliable Python socket server
- **Root Cause**: `nc -l` only accepts ONE connection before exiting, causing "connection reset by peer" on subsequent liveness checks
- **Solution**: Python socket server with `SO_REUSEADDR` properly handles multiple Kubernetes health checks
- **Result**: Zero container restarts after deployment

### ✅ SOCKS5 Configuration Fix
- Corrected `socksmethod` configuration in `danted.conf`
- Removed conflicting `socksmethod: username` when `PROXY_AUTH=false`
- Fixed dante startup failures in no-auth mode

## 📋 Technical Details

### **Metrics Exporter Implementation**

**File:** `scripts/metrics-exporter.py`

**Metrics Exposed:**
```prometheus
# Proxy information and identification
proxy_info{proxy_name="golden-crab"} 1

# Data transfer (from wg0 interface statistics)
proxy_bytes_transferred_total{proxy_name="golden-crab"} <bytes>

# Failed request tracking
proxy_requests_failed_total{proxy_name="golden-crab"} <count>

# Active connections (counts dante request-child and negotiate-child processes)
proxy_active_connections{proxy_name="golden-crab"} <count>

# Request rate per minute
proxy_request_rate_permin{proxy_name="golden-crab"} <rate>

# VPN connection status (1=up, 0=down, checks for wg0 peer)
vpn_connection_status{proxy_name="golden-crab"} <0|1>
```

**Key Features:**
- Reads network interface statistics from `/proc/net/dev` for accurate byte transfer tracking
- Counts active dante processes for real-time connection monitoring
- Validates WireGuard peer configuration for VPN status
- Non-blocking startup - container continues if metrics exporter fails
- Listens on port 9090 by default (`METRICS_PORT` environment variable)

### **Health Probe Fix**

**Before (Broken):**
```bash
# nc -l only accepts ONE connection, then exits
while true; do
    echo -e "HTTP/1.1 200 OK..." | nc -l -p 9999 >/dev/null 2>&1 || sleep 1
done
```

**After (Fixed):**
```python
# Python socket server properly handles multiple connections
server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server_socket.bind(("0.0.0.0", 9999))
server_socket.listen(5)

while True:
    client_socket, address = server_socket.accept()
    # Handle request and keep server running
```

**Why This Matters:**
- Kubernetes liveness probes check every 30 seconds
- Old `nc` implementation: Works for first check, fails for all subsequent checks
- New Python implementation: Handles unlimited connections reliably
- Prevents unnecessary pod restarts that disrupt proxy connections

### **Per-Proxy Labeling**

Added `PROXY_NAME` environment variable to Helm values and Flux HelmRelease:

```yaml
env:
  - name: PROXY_NAME
    value: "golden-crab"  # or "free-salmon"
```

Enables Grafana dashboard to:
- Display separate rows for each proxy in status table
- Show separate lines in time-series charts
- Filter and aggregate metrics by proxy name

### **Docker Compose Local Testing**

**Services:**
- `mullvad-mighty-bird`: Proxy instance with debug logging
- `prometheus`: Scrapes metrics from proxy
- `grafana`: Pre-configured with Prometheus datasource and dashboard
- `test-client`: Generates continuous traffic for testing

**Usage:**
```bash
cd /home/r2/dev/mullvad-kubernetes
docker compose -f docker-compose-test.yml up
# Grafana: http://localhost:3000 (admin/admin)
# Prometheus: http://localhost:9091
```

## 🔧 Files Modified/Created

### **Created Files**
```
scripts/metrics-exporter.py                                    # Prometheus metrics exporter
monitoring/prometheus/prometheus.yml                           # Prometheus configuration
monitoring/grafana/provisioning/datasources/prometheus.yml    # Grafana datasource config
monitoring/grafana/provisioning/dashboards/dashboards.yml     # Grafana dashboard provisioning
monitoring/grafana/dashboards/proxy-pool-dashboard.json       # Grafana dashboard definition
docker-compose-test.yml                                       # Local testing environment
changelog/2025-10-14_prometheus-metrics-grafana-dashboard-health-probe-fix.md
```

### **Modified Files**
```
docker/Dockerfile                                # Added metrics-exporter.py COPY instruction
scripts/configure-proxy.sh                       # Fixed SOCKS5 socksmethod configuration
scripts/mullvad-sidecar-entrypoint.sh           # Added metrics exporter startup, fixed health probe
helm/Chart.yaml                                  # Updated to v0.5.6
helm/values.yaml                                 # Added PROXY_NAME env var, updated image tag
flux-esxi/.../HelmRelease.yaml                  # Updated image tag and added PROXY_NAME
```

## 📊 Results

### **Monitoring Capabilities**
- ✅ Real-time visibility into proxy performance
- ✅ Per-proxy metrics for golden-crab and free-salmon
- ✅ Active connection tracking (17 connections per proxy confirmed)
- ✅ VPN status monitoring (both proxies showing UP)
- ✅ Data transfer tracking via WireGuard interface statistics
- ✅ Request rate monitoring (per minute)

### **Stability Improvements**
- ✅ **Zero container restarts** after v0.5.6 deployment
- ✅ Health probes consistently passing
- ✅ Pods stable for 5+ minutes of monitoring (previously restarting every 30-60 seconds)
- ✅ No disruption to active proxy connections

### **Deployment Success**
- ✅ GitHub Actions successfully building tagged releases
- ✅ Flux CD automatically reconciling HelmRelease updates
- ✅ Kubernetes pods pulling and running new image versions
- ✅ Metrics endpoint responding at `http://<pod-ip>:9090/metrics`

### **Version Progression**
- **v0.5.3** → **v0.5.4**: Added metrics exporter and per-proxy labeling
- **v0.5.4** → **v0.5.5**: Fixed missing metrics-exporter.py in Docker image
- **v0.5.5** → **v0.5.6**: Fixed health probe reliability issue

## 🎉 Key Success Factors

1. **Non-Breaking Design**: Metrics system is completely optional
   - Containers work perfectly without Prometheus installed
   - Metrics exporter failure doesn't affect VPN/proxy functionality
   - Health probe runs independently of metrics

2. **Proper Testing Workflow**:
   - Local Docker Compose testing before cluster deployment
   - Verified metrics format and labels locally
   - Caught health probe issue through cluster monitoring

3. **Incremental Version Bumps**:
   - Each issue fixed with dedicated version bump
   - Easy to track which version introduced which feature/fix
   - Clear git history with descriptive commits

4. **Per-Proxy Labeling**:
   - Using `PROXY_NAME` environment variable enables multi-proxy monitoring
   - Dashboard automatically discovers new proxies
   - No hardcoded proxy names in queries

5. **Root Cause Analysis**:
   - Properly diagnosed health probe issue (nc behavior)
   - Replaced with robust solution (Python socket server)
   - Validated fix with 3-minute stability test

## 🔮 Future Considerations

### **Prometheus/Grafana Deployment**
To fully utilize the metrics system, deploy to cluster:

1. **Install kube-prometheus-stack Helm chart**:
   ```bash
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring
   ```

2. **Create ServiceMonitor for auto-discovery**:
   ```yaml
   apiVersion: monitoring.coreos.com/v1
   kind: ServiceMonitor
   metadata:
     name: vpn-proxy-pool
     namespace: vpn-proxy-pool
   spec:
     selector:
       matchLabels:
         app.kubernetes.io/name: mullvad-proxy-pool
     endpoints:
       - port: metrics  # 9090
         interval: 15s
   ```

3. **Import Grafana dashboard**:
   - Use `monitoring/grafana/dashboards/proxy-pool-dashboard.json`
   - Dashboard will auto-populate with both proxies

### **Additional Metrics**
Consider adding in future versions:
- Request latency histograms
- Bandwidth usage per destination
- Failed connection reasons (from dante logs)
- WireGuard handshake timing
- DNS query metrics

### **Alerting**
Define Prometheus alerts for:
- VPN connection down
- High failed request rate
- Abnormal connection counts
- Low data transfer (possible connectivity issue)

### **Dashboard Enhancements**
- Add proxy-to-proxy comparison views
- Historical data analysis (week/month views)
- Geographic distribution of connections (if tracked)
- Cost per GB transferred

## 📝 Lessons Learned

### **1. Health Probe Reliability is Critical**
- Always use tools that properly handle multiple connections
- `nc -l` is NOT suitable for Kubernetes health probes
- Python's socket library provides reliable HTTP server capabilities
- Test health probes under load before production deployment

### **2. Interface Statistics for Byte Tracking**
- Dante logs don't include byte transfer information at `connect` log level
- Reading `/proc/net/dev` provides accurate interface-level statistics
- Initial reading saved to track delta from container start
- Works reliably even without request-level logging

### **3. Optional vs. Required Components**
- Making monitoring optional ensures backward compatibility
- Use conditional startup (`if [ -f script.py ]`) for optional features
- Background processes with `&` prevent blocking main application
- Document clearly what requires external dependencies

### **4. Local Testing Environment Value**
- Docker Compose test environment caught multiple issues
- Faster iteration than cluster deployments
- Easier debugging with direct container access
- Allows testing metrics/dashboard before cluster Prometheus install

### **5. Version Management Best Practices**
- Use automated version scripts (`./scripts/version.sh`)
- Tag every release for GitHub Actions automation
- Update both app version and chart version appropriately
- Keep version history in git tags for easy rollback

### **6. Process Counting for Active Connections**
- Dante spawns child processes per connection
- Counting `request-child` and `negotiate-child` processes gives accurate connection count
- More reliable than attempting to parse logs
- Updates in real-time without log parsing overhead

## 🔗 Related Documentation

- **Metrics Exporter**: `scripts/metrics-exporter.py`
- **Grafana Dashboard**: `monitoring/grafana/dashboards/proxy-pool-dashboard.json`
- **Local Testing**: `docker-compose-test.yml`
- **Helm Values**: `helm/values.yaml`
- **Flux HelmRelease**: `flux-esxi/workloads/vpn-proxy-pool/base/HelmRelease.yaml`

## 🎯 Next Steps

1. **Deploy Prometheus/Grafana to cluster** (optional, when monitoring is needed)
2. **Monitor pod stability** over next 24 hours to confirm health probe fix
3. **Consider adding alerting rules** for production monitoring
4. **Test under load** to validate metrics accuracy
5. **Document Prometheus setup** in main README if monitoring is deployed

---

**Contributors:** R2, Claude (AI Assistant)  
**Testing Environment:** ESXI Kubernetes Cluster, Local Docker Compose  
**Deployment Status:** ✅ Successfully deployed and stable  
**Image:** `ghcr.io/rixau/mullvad-kubernetes:0.5.6`

