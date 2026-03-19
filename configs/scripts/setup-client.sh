#!/bin/bash
# configs/scripts/setup-client.sh
# Bootstrap script for a Spectre client host.
set -euo pipefail

STAMP="/opt/ai-lb-client/.setup-complete"
if [[ -f "$STAMP" ]]; then
    echo "Setup already complete."
    exit 0
fi

echo "=== Spectre Client Setup ==="

apt-get update
apt-get install -y curl jq

mkdir -p /opt/ai-lb-client

DEPLOY_DIR="${1:-/tmp/spectre-deploy}"
if [[ -d "$DEPLOY_DIR" ]]; then
    cp "$DEPLOY_DIR/test-client.sh" /opt/ai-lb-client/
    chmod +x /opt/ai-lb-client/test-client.sh
fi

touch "$STAMP"
echo "=== Spectre Client Setup Complete ==="
