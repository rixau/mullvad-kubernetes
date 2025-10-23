# VPN Proxy Pool Expansion and Dashboard Fix - 2025-10-23

## 🎯 Project Overview

Expanded the VPN proxy pool from 2 to 5 proxies by adding three new Mullvad VPN locations (Chile, Mexico, United States) and resolved the data transfer rate dashboard metric issue. This provides geographic diversity for web scraping operations and improves monitoring visibility.

## 🚀 Major Accomplishments

### 1. **VPN Proxy Pool Expansion**
- Added `moden-shrimp` proxy (Chile - Santiago)
- Added `square-cat` proxy (Mexico - Mexico City)
- Added `great-ibex` proxy (United States)
- Increased total proxy count from 2 to 5 proxies
- Geographic coverage now spans 4 regions: Brazil (2), Chile (1), Mexico (1), US (1)

### 2. **SOPS Secret Management**
- Created encrypted WireGuard configuration secrets for all 3 new proxies
- Stored in `workloads/vpn-proxy-pool/base/secrets/`
- Updated kustomization.yaml to include new secret references
- Maintained security best practices with encrypted configs in git

### 3. **Dashboard Metrics Fix**
- Fixed "💾 Data Transfer Rate" panel showing no data
- Root cause: `rate()` function with 1-minute time window had insufficient samples
- Solution: Increased time window from `[1m]` to `[5m]`
- Dashboard chart version bumped from 0.5.2 → 0.5.4

### 4. **Avoided Prometheus Configuration Breakage**
- Initially attempted manual Prometheus scrape configuration (unnecessary)
- Discovered existing service annotation-based discovery was already working
- Reverted Prometheus changes to prevent breaking other dashboards
- Learned: If some panels work, scraping is already functional

## 📋 Technical Details

### **New VPN Proxy Configurations**

**moden-shrimp (Chile):**
```yaml
config:
  secretName: "mullvad-moden-shrimp"
  configKey: "wg0.conf"
env:
  - name: PROXY_NAME
    value: "moden-shrimp"
```

**square-cat (Mexico):**
```yaml
config:
  secretName: "mullvad-square-cat"
  configKey: "wg0.conf"
env:
  - name: PROXY_NAME
    value: "square-cat"
```

**great-ibex (United States):**
```yaml
config:
  secretName: "mullvad-great-ibex"
  configKey: "wg0.conf"
env:
  - name: PROXY_NAME
    value: "great-ibex"
```

### **Dashboard Query Fix**

**Before (Not Working):**
```promql
rate(proxy_bytes_transferred_total[1m])
```

**After (Working):**
```promql
rate(proxy_bytes_transferred_total[5m])
```

**Why:** The 1-minute time window didn't have enough scrape samples for Prometheus to calculate a rate. The 5-minute window provides multiple data points for reliable rate calculations.

### **Current Data Transfer Rates**
```
free-salmon:   ~91 KB/s
golden-crab:   ~72 KB/s  
moden-shrimp:  ~104 KB/s
square-cat:    ~136 KB/s
great-ibex:    ~37 KB/s
```

## 🔧 Files Modified/Created

### **Flux Repository (flux-esxi)**
- `workloads/vpn-proxy-pool/base/HelmRelease.yaml` - Added 3 new proxy configurations
- `workloads/vpn-proxy-pool/base/kustomization.yaml` - Added secret references
- `workloads/vpn-proxy-pool/base/secrets/mullvad-moden-shrimp.yaml` - **NEW**: SOPS-encrypted WireGuard config
- `workloads/vpn-proxy-pool/base/secrets/mullvad-square-cat.yaml` - **NEW**: SOPS-encrypted WireGuard config
- `workloads/vpn-proxy-pool/base/secrets/mullvad-great-ibex.yaml` - **NEW**: SOPS-encrypted WireGuard config
- `workloads/vpn-proxy-pool-dashboards/base/HelmRelease.yaml` - Updated dashboard version to 0.5.4

### **Mullvad Kubernetes Repository**
- `charts/dashboard/dashboards/proxy-pool-dashboard.json` - Fixed rate query time window
- `charts/dashboard/Chart.yaml` - Bumped version to 0.5.4

## 📊 Results

### **VPN Proxy Pool Status**
- ✅ **5 proxies deployed and running** (previously 2)
- ✅ **All proxies reporting healthy** VPN connection status
- ✅ **Geographic diversity** across 4 countries/regions
- ✅ **Load balancing** operational via Kubernetes service

### **Dashboard Status**
- ✅ **All panels working** including previously broken data transfer rate
- ✅ **Metrics collection** via existing Prometheus service discovery
- ✅ **Real-time monitoring** of all 5 proxy instances
- ✅ **Performance visibility** for connection latency, download speeds, and data transfer

### **Deployment Verification**
```
Proxy Name      Status  Location          Data Transfer (5m avg)
golden-crab     UP      Brazil (São Paulo)      ~72 KB/s
free-salmon     UP      Brazil (Fortaleza)      ~91 KB/s
moden-shrimp    UP      Chile (Santiago)       ~104 KB/s
square-cat      UP      Mexico (Mexico City)   ~136 KB/s
great-ibex      UP      United States           ~37 KB/s
```

## 🎉 Key Success Factors

### **1. SOPS Workflow Adherence**
- Followed proper decrypt → edit → encrypt workflow for all secrets
- Avoided direct editing of encrypted files
- Maintained security compliance throughout

### **2. Incremental Deployment**
- Added proxies one at a time initially
- Then added final proxy after validation
- Prevented mass failures from configuration issues

### **3. Troubleshooting Methodology**
- Verified Prometheus was scraping (other panels worked = scraping functional)
- Tested queries directly against Prometheus API to isolate issue
- Identified rate calculation as the problem, not discovery
- Fixed with minimal changes (just the time window)

### **4. Avoiding Over-Engineering**
- Recognized that working panels meant scraping was functional
- Reverted unnecessary Prometheus configuration changes
- Applied Occam's Razor: simplest fix was the right fix

## 🔮 Future Considerations

### **Proxy Pool Scaling**
- Consider adding more geographic regions (Europe, Asia, Oceania)
- Implement automatic failover for proxy health issues
- Add proxy selection logic based on target region

### **Monitoring Enhancements**
- Add alerting for VPN connection failures
- Track proxy utilization and balance load across instances
- Monitor cost per proxy for optimization decisions

### **Dashboard Improvements**
- Add historical trends for long-term capacity planning
- Implement proxy rotation recommendations based on usage
- Create alerts for proxies with consistently low performance

## 📝 Lessons Learned

### **1. Rate Function Requirements**
- `rate()` functions need sufficient time windows for reliable calculations
- Short time windows ([1m]) may not have enough scrape samples
- Use [5m] or longer for counter-based rate calculations
- Test queries directly in Prometheus before debugging infrastructure

### **2. Prometheus Discovery Patterns**
- Service annotations enable automatic discovery
- If some metrics work, discovery is already functional
- Don't add manual scrape configs if auto-discovery works
- Check existing configuration before adding complexity

### **3. Troubleshooting Strategy**
- Working panels = scraping is functional (eliminates discovery issues)
- Test queries directly against Prometheus API
- Isolate the actual problem before making changes
- Revert unnecessary changes quickly

### **4. SOPS Best Practices**
- Always use temporary files for decryption/encryption
- Never edit encrypted files directly
- Follow established workflows to prevent corruption
- Keep unencrypted configs in separate repository for reference

---

**Date**: October 23, 2025  
**Duration**: ~2 hours  
**Status**: ✅ Complete  
**Next Steps**: Monitor proxy performance, consider adding additional geographic regions, implement alerting for VPN failures

