#!/usr/bin/env python3
"""
Prometheus metrics exporter for Mullvad VPN Proxy Pool
Monitors dante SOCKS5 proxy logs and exports metrics
"""

import re
import time
import socket
from collections import defaultdict
from http.server import HTTPServer, BaseHTTPRequestHandler
from threading import Thread
import subprocess
import os

# Get proxy name from environment or hostname
PROXY_NAME = os.getenv('PROXY_NAME', socket.gethostname())

class ProxyMetrics:
    def __init__(self):
        self.request_count = 0
        self.bytes_transferred = 0
        self.active_connections = 0
        self.failed_requests = 0
        self.requests_by_host = defaultdict(int)
        self.last_request_time = time.time()
        self.initial_wg0_bytes = self.get_wg0_bytes()
        
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
        
    def record_request(self, success=True, bytes_sent=0, host="unknown"):
        self.request_count += 1
        # Update bytes from interface stats
        current_bytes = self.get_wg0_bytes()
        self.bytes_transferred = current_bytes - self.initial_wg0_bytes
        if not success:
            self.failed_requests += 1
        self.requests_by_host[host] += 1
        self.last_request_time = time.time()

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
            
            # Active connections (count from dante processes)
            active_conns = metrics.get_active_connections()
            output.append('# HELP proxy_active_connections Current active proxy connections')
            output.append('# TYPE proxy_active_connections gauge')
            output.append(f'proxy_active_connections{{proxy_name="{PROXY_NAME}"}} {active_conns}')
            output.append('')
            
            # Request rate (requests per minute)
            # Calculate based on requests in last 60 seconds
            request_rate_per_min = metrics.request_count * (60.0 / max(time.time() - metrics.last_request_time, 1)) if metrics.request_count > 0 else 0
            output.append('# HELP proxy_request_rate_permin Current proxy request rate per minute')
            output.append('# TYPE proxy_request_rate_permin gauge')
            output.append(f'proxy_request_rate_permin{{proxy_name="{PROXY_NAME}"}} {request_rate_per_min:.2f}')
            output.append('')
            
            # VPN connection status (check WireGuard)
            vpn_up = 1 if self.check_vpn_status() else 0
            output.append('# HELP vpn_connection_status VPN connection status (1=up, 0=down)')
            output.append('# TYPE vpn_connection_status gauge')
            output.append(f'vpn_connection_status{{proxy_name="{PROXY_NAME}"}} {vpn_up}')
            output.append('')
            
            self.wfile.write('\n'.join(output).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()
    
    def check_vpn_status(self):
        """Check if WireGuard VPN is connected"""
        try:
            result = subprocess.run(['wg', 'show', 'wg0'], 
                                  capture_output=True, 
                                  text=True, 
                                  timeout=2)
            if result.returncode == 0:
                output = result.stdout
                # Check if peer is configured (VPN interface is up)
                # For proxy use, if peer exists, consider it "up"
                # Handshake may not appear until first traffic
                return 'peer:' in output
            return False
        except:
            return False
    
    def log_message(self, format, *args):
        pass  # Suppress HTTP server logs

def monitor_dante_logs():
    """Monitor dante logs and extract metrics"""
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
            # Example: "info: pass(1): tcp/connect"
            if 'pass' in line or 'block' in line:
                success = 'pass' in line
                metrics.record_request(success=success)
                
            # Look for data transfer info
            bytes_match = re.search(r'(\d+)\s+bytes', line)
            if bytes_match:
                metrics.bytes_transferred += int(bytes_match.group(1))
                
    except FileNotFoundError:
        print("⚠️  Warning: /var/log/danted.log not found, running with simulated metrics")
        # Run in simulation mode for testing
        while True:
            time.sleep(10)
            # Simulate some activity for testing
            if metrics.request_count > 0:
                metrics.active_connections = max(0, metrics.active_connections + (-1 if time.time() % 2 == 0 else 1))

def main():
    # Start log monitoring in background
    monitor_thread = Thread(target=monitor_dante_logs, daemon=True)
    monitor_thread.start()
    
    # Start metrics HTTP server
    port = int(os.getenv('METRICS_PORT', '9090'))
    server = HTTPServer(('0.0.0.0', port), MetricsHandler)
    
    print(f"🎯 Metrics exporter started on port {port}")
    print(f"📊 Metrics endpoint: http://0.0.0.0:{port}/metrics")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n👋 Shutting down metrics exporter")
        server.shutdown()

if __name__ == '__main__':
    main()

