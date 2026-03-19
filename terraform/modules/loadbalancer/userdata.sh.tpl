#!/bin/bash
set -euo pipefail
echo "Spectre LB bootstrap — run setup-loadbalancer.sh after deploy"
# Backend IPs: ${join(", ", backend_ips)}
