#!/bin/bash
# configs/scripts/setup-backend.sh
# Bootstrap script for a Spectre backend server.
# Run as root. Requires MODEL_NAME env var.
set -euo pipefail

MODEL_NAME="${MODEL_NAME:?MODEL_NAME must be set (e.g., qwen3:4b)}"
RUNTIME="${RUNTIME:-ollama}"

STAMP="/opt/spectre/.setup-complete"
if [[ -f "$STAMP" ]]; then
    echo "Setup already complete. Remove $STAMP to re-run."
    exit 0
fi

echo "=== Spectre Backend Setup (model: $MODEL_NAME, runtime: $RUNTIME) ==="

# System packages
apt-get update
apt-get install -y python3 python3-venv python3-pip curl jq

# Create spectre user and directories
id spectre &>/dev/null || useradd -r -s /usr/sbin/nologin spectre
mkdir -p /opt/spectre/{gpu-monitor,venv,scripts}
mkdir -p /etc/spectre

# Python venv
python3 -m venv /opt/spectre/venv
/opt/spectre/venv/bin/pip install --upgrade pip
/opt/spectre/venv/bin/pip install fastapi uvicorn[standard] psutil

# Install pynvml if NVIDIA GPU detected
if command -v nvidia-smi &>/dev/null; then
    /opt/spectre/venv/bin/pip install nvidia-ml-py
fi

# Install inference runtime
if [[ "$RUNTIME" == "ollama" ]]; then
    if ! command -v ollama &>/dev/null; then
        curl -fsSL https://ollama.ai/install.sh | sh
    fi
    # Configure Ollama
    mkdir -p /etc/systemd/system/ollama.service.d
    cat > /etc/systemd/system/ollama.service.d/spectre.conf <<EOF
[Service]
Environment="OLLAMA_HOST=0.0.0.0:1234"
Environment="OLLAMA_KEEP_ALIVE=-1"
Environment="OLLAMA_NUM_PARALLEL=4"
Environment="OLLAMA_FLASH_ATTENTION=true"
EOF
    systemctl daemon-reload
    systemctl enable ollama
    systemctl restart ollama
    # Wait for Ollama to start
    for i in $(seq 1 30); do
        curl -sf http://localhost:1234/ && break
        sleep 2
    done
    # Pull model
    OLLAMA_HOST="http://localhost:1234" ollama pull "$MODEL_NAME"
else
    echo "llmster runtime — install manually via lms CLI"
fi

# Write inference env
cat > /etc/spectre/inference.env <<EOF
RUNTIME=$RUNTIME
MODEL_NAME=$MODEL_NAME
INFERENCE_PORT=1234
EOF
chmod 640 /etc/spectre/inference.env

# Copy GPU monitor and scripts
DEPLOY_DIR="${1:-/tmp/spectre-deploy}"
if [[ -d "$DEPLOY_DIR" ]]; then
    cp "$DEPLOY_DIR/gpu_monitor_agent.py" /opt/spectre/gpu-monitor/
    cp "$DEPLOY_DIR"/spectre-gpu-monitor.service /etc/systemd/system/
    cp "$DEPLOY_DIR"/spectre-inference.service /etc/systemd/system/
    cp "$DEPLOY_DIR"/wait-for-inference.sh /opt/spectre/scripts/
    cp "$DEPLOY_DIR"/start-inference.sh /opt/spectre/scripts/
    chmod +x /opt/spectre/scripts/*.sh
fi

chown -R spectre:spectre /opt/spectre

systemctl daemon-reload
systemctl enable spectre-gpu-monitor
systemctl restart spectre-gpu-monitor

touch "$STAMP"
echo "=== Spectre Backend Setup Complete ==="
