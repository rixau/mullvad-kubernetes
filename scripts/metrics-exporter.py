#!/usr/bin/env python3
"""
Prometheus metrics exporter for Mullvad VPN Proxy Pool
Monitors dante SOCKS5 proxy logs and exports metrics
Enhanced with latency, speed tests, and success rate tracking
"""

import re
import time
import socket
from collections import defaultdict
from http.server import HTTPServer, BaseHTTPRequestHandler
from threading import Thread, Lock
import subprocess
import os

# Get proxy name from environment or hostname
PROXY_NAME = os.getenv('PROXY_NAME', socket.gethostname())
SOCKS5_PORT = int(os.getenv('SOCKS5_PORT', '1080'))

class ProxyMetrics:
    def __init__(self):
        self.request_count = 0
        self.bytes_transferred = 0
        self.active_connections = 0
        self.failed_requests = 0
        self.successful_requests = 0
        self.requests_by_host = defaultdict(int)
        self.last_request_time = time.time()
        self.initial_wg0_bytes = self.get_wg0_bytes()
        
        # Performance metrics
        self.latency_ms = 0
        self.latency_last_check = 0
        self.download_speed_mbps = 0
        self.speed_last_check = 0
        
        # Dante stats
        self.connection_durations = []  # Store last 100 connection durations
        self.avg_connection_duration = 0
        
        # Thread safety
        self.lock = Lock()
        
    def get_wg0_bytes(self):
        """Read total bytes transferred on wg0 interface"""
        try:
            with open('/proc/net/dev', 'r') as f:
                for line in f:
                    if 'wg0:' in line:
                        parts = line.split()
                        rx_bytes = int(parts[1])  # Received bytes
                        tx_bytes = int(parts[9])  # Transmitted bytes
                        return rx_bytes + tx_bytes
        except:
            return 0
        return 0
    
    def get_active_connections(self):
        """Count active dante connection processes"""
        try:
            result = subprocess.run(
                ['ps', 'aux'],
                capture_output=True,
                text=True,
                timeout=2
            )
            # Count request-child and negotiate-child processes (active connections)
            count = 0
            for line in result.stdout.split('\n'):
                if 'danted:' in line and ('request-child' in line or 'negotiate-child' in line):
                    count += 1
            return count
        except:
            return 0
    
    def get_success_rate(self):
        """Calculate success rate percentage"""
        total = self.successful_requests + self.failed_requests
        if total == 0:
            return 100.0  # No requests yet, assume healthy
        return (self.successful_requests / total) * 100.0
        
    def record_request(self, success=True, bytes_sent=0, host="unknown", client="unknown"):
        with self.lock:
            self.request_count += 1
            # Update bytes from interface stats
            current_bytes = self.get_wg0_bytes()
            self.bytes_transferred = current_bytes - self.initial_wg0_bytes
            if success:
                self.successful_requests += 1
            else:
                self.failed_requests += 1
            self.requests_by_host[host] += 1
            # Track requests by client container
            if client != "unknown":
                self.requests_by_host[client] += 1
            self.last_request_time = time.time()
    
    def update_latency(self, latency_ms):
        """Update latency metric"""
        with self.lock:
            self.latency_ms = latency_ms
            self.latency_last_check = time.time()
    
    def update_speed(self, speed_mbps):
        """Update download speed metric"""
        with self.lock:
            self.download_speed_mbps = speed_mbps
            self.speed_last_check = time.time()
    
    def add_connection_duration(self, duration_seconds):
        """Track connection duration"""
        with self.lock:
            self.connection_durations.append(duration_seconds)
            # Keep only last 100
            if len(self.connection_durations) > 100:
                self.connection_durations.pop(0)
            # Update average
            if self.connection_durations:
                self.avg_connection_duration = sum(self.connection_durations) / len(self.connection_durations)

metrics = ProxyMetrics()

class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/metrics':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain; charset=utf-8')
            self.end_headers()
            
            output = []
            
            # Update bytes from interface (real-time)
            current_bytes = metrics.get_wg0_bytes()
            current_transferred = current_bytes - metrics.initial_wg0_bytes
            
            # Proxy info
            output.append('# HELP proxy_info Information about the proxy')
            output.append('# TYPE proxy_info gauge')
            output.append(f'proxy_info{{proxy_name="{PROXY_NAME}"}} 1')
            output.append('')
            
            # Bytes transferred
            output.append('# HELP proxy_bytes_transferred_total Total bytes transferred through proxy')
            output.append('# TYPE proxy_bytes_transferred_total counter')
            output.append(f'proxy_bytes_transferred_total{{proxy_name="{PROXY_NAME}"}} {current_transferred}')
            output.append('')
            
            # Failed requests
            output.append('# HELP proxy_requests_failed_total Total number of failed proxy requests')
            output.append('# TYPE proxy_requests_failed_total counter')
            output.append(f'proxy_requests_failed_total{{proxy_name="{PROXY_NAME}"}} {metrics.failed_requests}')
            output.append('')
            
            # Successful requests
            output.append('# HELP proxy_requests_successful_total Total number of successful proxy requests')
            output.append('# TYPE proxy_requests_successful_total counter')
            output.append(f'proxy_requests_successful_total{{proxy_name="{PROXY_NAME}"}} {metrics.successful_requests}')
            output.append('')
            
            # Success rate percentage
            success_rate = metrics.get_success_rate()
            output.append('# HELP proxy_success_rate_percent Percentage of successful requests')
            output.append('# TYPE proxy_success_rate_percent gauge')
            output.append(f'proxy_success_rate_percent{{proxy_name="{PROXY_NAME}"}} {success_rate:.2f}')
            output.append('')
            
            # Active connections (count from dante processes)
            active_conns = metrics.get_active_connections()
            output.append('# HELP proxy_active_connections Current active proxy connections')
            output.append('# TYPE proxy_active_connections gauge')
            output.append(f'proxy_active_connections{{proxy_name="{PROXY_NAME}"}} {active_conns}')
            output.append('')
            
            # Request rate (requests per minute)
            request_rate_per_min = metrics.request_count * (60.0 / max(time.time() - metrics.last_request_time, 1)) if metrics.request_count > 0 else 0
            output.append('# HELP proxy_request_rate_permin Current proxy request rate per minute')
            output.append('# TYPE proxy_request_rate_permin gauge')
            output.append(f'proxy_request_rate_permin{{proxy_name="{PROXY_NAME}"}} {request_rate_per_min:.2f}')
            output.append('')
            
            # Latency (milliseconds) - skip if still initial value of 0
            if metrics.latency_ms != 0:
                output.append('# HELP proxy_latency_ms Proxy connection latency in milliseconds')
                output.append('# TYPE proxy_latency_ms gauge')
                output.append(f'proxy_latency_ms{{proxy_name="{PROXY_NAME}"}} {metrics.latency_ms:.2f}')
                output.append('')
            
            # Download speed (Mbps) - skip if still initial value of 0
            if metrics.download_speed_mbps != 0:
                output.append('# HELP proxy_download_speed_mbps Proxy download speed in Mbps')
                output.append('# TYPE proxy_download_speed_mbps gauge')
                output.append(f'proxy_download_speed_mbps{{proxy_name="{PROXY_NAME}"}} {metrics.download_speed_mbps:.2f}')
                output.append('')
            
            # Average connection duration - skip if still initial value of 0
            if metrics.avg_connection_duration != 0:
                output.append('# HELP proxy_avg_connection_duration_seconds Average connection duration in seconds')
                output.append('# TYPE proxy_avg_connection_duration_seconds gauge')
                output.append(f'proxy_avg_connection_duration_seconds{{proxy_name="{PROXY_NAME}"}} {metrics.avg_connection_duration:.2f}')
                output.append('')
            
            # VPN connection status (check WireGuard)
            vpn_up = 1 if self.check_vpn_status() else 0
            output.append('# HELP vpn_connection_status VPN connection status (1=up, 0=down)')
            output.append('# TYPE vpn_connection_status gauge')
            output.append(f'vpn_connection_status{{proxy_name="{PROXY_NAME}"}} {vpn_up}')
            output.append('')
            
            # Requests by client/container
            output.append('# HELP proxy_requests_by_client_total Total requests by client container')
            output.append('# TYPE proxy_requests_by_client_total counter')
            for client, count in metrics.requests_by_host.items():
                if count > 0:
                    # Clean up client name for prometheus label
                    client_label = client.replace('.', '_').replace('-', '_')
                    output.append(f'proxy_requests_by_client_total{{proxy_name="{PROXY_NAME}",client="{client_label}"}} {count}')
            output.append('')
            
            self.wfile.write('\n'.join(output).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()
    
    def check_vpn_status(self):
        """Check if WireGuard VPN is connected with fresh handshake"""
        try:
            result = subprocess.run(['wg', 'show', 'wg0'], 
                                  capture_output=True, 
                                  text=True, 
                                  timeout=2)
            if result.returncode == 0:
                output = result.stdout
                
                # Check if peer is configured
                if 'peer:' not in output:
                    return False
                
                # Check handshake freshness (critical for detecting stale tunnels)
                if 'latest handshake:' in output:
                    handshake_line = [line for line in output.split('\n') if 'latest handshake:' in line]
                    if handshake_line:
                        handshake_info = handshake_line[0].split('latest handshake:')[-1].strip()
                        
                        # VPN is DOWN if handshake is stale (days, hours, or >3 minutes)
                        if 'day' in handshake_info or 'hour' in handshake_info:
                            return False
                        
                        # Check minutes
                        import re
                        minutes_match = re.search(r'(\d+)\s+minute', handshake_info)
                        if minutes_match:
                            minutes = int(minutes_match.group(1))
                            if minutes > 3:
                                return False  # Stale handshake
                        
                        # Fresh handshake - VPN is UP
                        return True
                    return False
                else:
                    # No handshake yet - VPN not fully connected
                    return False
            
            return False
        except:
            return False
    
    def log_message(self, format, *args):
        pass  # Suppress HTTP server logs

def resolve_ip_to_container(ip_address):
    """Try to resolve IP address to container name"""
    # Try getent for Docker network DNS
    try:
        result = subprocess.run(
            ['getent', 'hosts', ip_address],
            capture_output=True,
            text=True,
            timeout=1
        )
        if result.returncode == 0 and result.stdout:
            # Format: "IP_ADDRESS  hostname"
            parts = result.stdout.strip().split()
            if len(parts) >= 2:
                return parts[1]
    except:
        pass
    
    # Fallback to Python socket DNS lookup
    try:
        hostname = socket.gethostbyaddr(ip_address)[0]
        return hostname
    except:
        # If all fails, return clean IP format
        return ip_address.replace('.', '_')

def monitor_dante_logs():
    """Monitor dante logs and extract metrics"""
    connection_start_times = {}  # Track connection start times by connection ID
    
    try:
        # Try to tail dante log file
        process = subprocess.Popen(
            ['tail', '-f', '/var/log/danted.log'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        
        for line in process.stdout:
            # Parse dante log lines for connection info
            # Example: "info: pass(1): tcp/accept ]: 172.23.0.10.52345 172.23.0.5.1080"
            # Format: "IP.port IP.port" where first IP is client
            client_name = "unknown"
            
            # Extract client IP from dante log format
            # Pattern: "]: IP.port IP.port" or "tcp/accept ]: IP.port"
            client_match = re.search(r'\]:\s+(\d+\.\d+\.\d+\.\d+)\.\d+\s+\d+\.\d+\.\d+\.\d+\.\d+', line)
            if client_match:
                client_ip = client_match.group(1)
                # Skip localhost health checks
                if client_ip != "127.0.0.1":
                    client_name = resolve_ip_to_container(client_ip)
            
            if 'pass' in line or 'block' in line:
                success = 'pass' in line
                metrics.record_request(success=success, client=client_name)
            
            # Track connection duration
            # Look for connection start/end patterns
            if 'pass' in line and 'tcp/connect' in line:
                # New connection - extract connection ID if available
                conn_id_match = re.search(r'pass\((\d+)\)', line)
                if conn_id_match:
                    conn_id = conn_id_match.group(1)
                    connection_start_times[conn_id] = time.time()
            
            # Connection closed
            if 'info:' in line and 'closed' in line:
                conn_id_match = re.search(r'pass\((\d+)\)', line)
                if conn_id_match:
                    conn_id = conn_id_match.group(1)
                    if conn_id in connection_start_times:
                        duration = time.time() - connection_start_times[conn_id]
                        metrics.add_connection_duration(duration)
                        del connection_start_times[conn_id]
            
            # Look for data transfer info
            bytes_match = re.search(r'(\d+)\s+bytes', line)
            if bytes_match:
                metrics.bytes_transferred += int(bytes_match.group(1))
                
    except FileNotFoundError:
        print("⚠️  Warning: /var/log/danted.log not found, running without log monitoring")
        # Keep thread alive
        while True:
            time.sleep(60)

def periodic_latency_check():
    """Periodically check pure network latency (ICMP)"""
    while True:
        try:
            start = time.time()
            subprocess.run(["ping", "-c", "1", "-W", "2", "1.1.1.1"], 
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            latency_ms = (time.time() - start) * 1000
            metrics.update_latency(latency_ms)
            print(f"✅ Ping latency: {latency_ms:.2f}ms")
        except Exception as e:
            print(f"❌ Latency check error: {e}")
            metrics.update_latency(-1)
        time.sleep(30)

def periodic_speed_test():
    """Periodically test download speed through proxy"""
    while True:
        try:
            result = subprocess.run(
                ['curl', '-s', '-o', '/dev/null', '-w', '%{speed_download}',
                 '--socks5', f'127.0.0.1:{SOCKS5_PORT}',
                 '--max-time', '60',
                 'http://speedtest.tele2.net/10MB.zip'],
                capture_output=True, text=True, timeout=70)
            if result.returncode == 0:
                # bytes per second -> megabits per second
                speed_mbps = float(result.stdout.strip()) * 8 / 1_000_000
                metrics.update_speed(speed_mbps)
                print(f"✅ Download speed: {speed_mbps:.2f} Mbps")
        except Exception as e:
            print(f"❌ Speed test error: {e}")
            metrics.update_speed(-1)
        time.sleep(600)
        
def main():
    # Start log monitoring in background
    monitor_thread = Thread(target=monitor_dante_logs, daemon=True)
    monitor_thread.start()
    print(f"✅ Started log monitoring thread (PID: {monitor_thread.ident})")
    
    # Start latency check thread
    latency_thread = Thread(target=periodic_latency_check, daemon=True)
    latency_thread.start()
    print(f"✅ Started latency check thread (PID: {latency_thread.ident})")
    
    # Start speed test thread
    speed_thread = Thread(target=periodic_speed_test, daemon=True)
    speed_thread.start()
    print(f"✅ Started speed test thread (PID: {speed_thread.ident})")
    
    # Start metrics HTTP server
    port = int(os.getenv('METRICS_PORT', '9090'))
    server = HTTPServer(('0.0.0.0', port), MetricsHandler)
    
    print(f"🎯 Metrics exporter started on port {port}")
    print(f"📊 Metrics endpoint: http://0.0.0.0:{port}/metrics")
    print(f"📡 Enhanced monitoring: latency, speed tests, success rate, connection duration")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n👋 Shutting down metrics exporter")
        server.shutdown()

if __name__ == '__main__':
    main()

