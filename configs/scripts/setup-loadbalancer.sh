#!/bin/bash
# configs/scripts/setup-loadbalancer.sh
# Bootstrap script for the Spectre load balancer host.
# Run as root on a fresh Ubuntu 24.04 server.
set -euo pipefail

STAMP="/opt/spectre/.setup-complete"
if [[ -f "$STAMP" ]]; then
    echo "Setup already complete. Remove $STAMP to re-run."
    exit 0
fi

echo "=== Spectre LB Setup ==="

# System packages
apt-get update
apt-get install -y nginx python3 python3-venv python3-pip curl jq

# Create spectre user and directories
id spectre &>/dev/null || useradd -r -s /usr/sbin/nologin spectre
mkdir -p /opt/spectre/{sidecar,auth,venv,scripts}
mkdir -p /etc/spectre
mkdir -p /etc/nginx/ssl

# Python venv
python3 -m venv /opt/spectre/venv
/opt/spectre/venv/bin/pip install --upgrade pip
/opt/spectre/venv/bin/pip install fastapi uvicorn[standard] httpx pydantic

# Generate self-signed SSL cert
if [[ ! -f /etc/nginx/ssl/spectre.crt ]]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/spectre.key \
        -out /etc/nginx/ssl/spectre.crt \
        -subj "/CN=ai-lb.local/O=Spectre/C=US"
    chmod 600 /etc/nginx/ssl/spectre.key
fi

# Generate API key
if [[ ! -f /etc/spectre/auth.env ]]; then
    API_KEY=$(openssl rand -hex 32)
    KEY_HASH=$(echo -n "$API_KEY" | sha256sum | cut -d' ' -f1)
    echo "SPECTRE_API_KEY_HASHES=$KEY_HASH" > /etc/spectre/auth.env
    echo "$API_KEY" > /etc/spectre/api-key.txt
    chmod 640 /etc/spectre/auth.env /etc/spectre/api-key.txt
    chown root:spectre /etc/spectre/auth.env /etc/spectre/api-key.txt
    echo "API key saved to /etc/spectre/api-key.txt"
fi

# Copy configs (assumes files are in /tmp/spectre-deploy/)
DEPLOY_DIR="${1:-/tmp/spectre-deploy}"
if [[ -d "$DEPLOY_DIR" ]]; then
    cp "$DEPLOY_DIR/nginx.conf" /etc/nginx/nginx.conf
    cp "$DEPLOY_DIR/sidecar_service.py" /opt/spectre/sidecar/
    cp "$DEPLOY_DIR/auth_service.py" /opt/spectre/auth/
    cp "$DEPLOY_DIR"/spectre-*.service /etc/systemd/system/
    cp "$DEPLOY_DIR/spectre.target" /etc/systemd/system/
    mkdir -p /etc/systemd/system/nginx.service.d
    cp "$DEPLOY_DIR/spectre-nginx.service" /etc/systemd/system/nginx.service.d/spectre.conf
fi

chown -R spectre:spectre /opt/spectre

# Enable and start services
systemctl daemon-reload
systemctl enable spectre.target spectre-sidecar spectre-auth nginx
systemctl restart spectre-sidecar spectre-auth
systemctl restart nginx

# Verify
nginx -t
systemctl is-active spectre-sidecar spectre-auth nginx

touch "$STAMP"
echo "=== Spectre LB Setup Complete ==="
