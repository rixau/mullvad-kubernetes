FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages for WireGuard and Proxy
RUN apt-get update && \
    apt-get install -y software-properties-common && \
    add-apt-repository universe && \
    apt-get update && \
    apt-get install -y \
    wireguard-tools \
    curl \
    wget \
    iproute2 \
    iptables \
    iputils-ping \
    dnsutils \
    net-tools \
    netcat-openbsd \
    ca-certificates \
    kmod \
    openresolv \
    dante-server \
    tinyproxy \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create necessary directories
RUN mkdir -p /etc/wireguard /tmp/mullvad /etc/danted

# Add WireGuard validation script
COPY scripts/validate-wireguard.sh /usr/local/bin/validate-wireguard.sh
RUN chmod +x /usr/local/bin/validate-wireguard.sh

# Add proxy configuration script
COPY scripts/configure-proxy.sh /usr/local/bin/configure-proxy.sh
RUN chmod +x /usr/local/bin/configure-proxy.sh

# Add Mullvad sidecar entrypoint
COPY scripts/mullvad-proxy-entrypoint.sh /usr/local/bin/mullvad-proxy-entrypoint.sh
RUN chmod +x /usr/local/bin/mullvad-proxy-entrypoint.sh

# Add metrics exporter script
COPY scripts/metrics-exporter.py /usr/local/bin/metrics-exporter.py
RUN chmod +x /usr/local/bin/metrics-exporter.py

# Set working directory
WORKDIR /tmp/mullvad

# Use the Mullvad sidecar entrypoint
ENTRYPOINT ["/usr/local/bin/mullvad-proxy-entrypoint.sh"]
