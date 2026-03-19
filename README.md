# Spectre

NGINX-based load balancer for compute offload to multiple AI backends with model-aware routing, GPU health monitoring, and multi-platform support.

## Architecture

- **Load Balancer**: NGINX on Ubuntu Server 24.04 with SSL termination and auth
- **Backends**: 3 GPU servers running LM Studio headless (`llmster`) on port 1234
- **Sidecar**: Python FastAPI service for health monitoring, GPU-aware routing, and model registry (`:8080`)
- **Auth Service**: Python FastAPI API key validation (`:8081`)
- **GPU Monitor**: Per-backend agent reporting GPU utilization, VRAM, and temperature (`:9090`)

## Network

| Subnet | CIDR | Hosts |
|--------|------|-------|
| Public | 10.0.1.0/24 | Load balancer (.5), Clients (.10-.13) |
| Private | 10.0.2.0/24 | Backends (.10-.12) |

## Key Features

- **Model-aware routing** via URL paths (`/route/{model}/...`) or `X-Model-Id` header
- **GPU load scoring**: 50% GPU util + 30% VRAM + 20% active requests
- **Apple Silicon + NVIDIA support** via `macmon` and `nvidia-smi`
- **Session pinning** for stateful chat conversations
- **CPU-only mode** for testing on VMs without GPUs

## Project Structure

```
configs/
├── nginx/          # NGINX load balancer config
├── sidecar/        # FastAPI sidecar, auth, and GPU monitor
├── systemd/        # Service unit files
├── scripts/        # Bootstrap scripts
└── client-test/    # Automated test suite
terraform/          # AWS infrastructure (VPC, EC2, security groups)
diagrams/           # Architecture diagrams
docs/               # Operations runbook, guides
```

## Deployment Stages

1. Terraform infrastructure provisioning
2. Load balancer configuration
3. Backend server setup + model loading
4. End-to-end testing
5. Scale clients (2 → 4)
6. Load testing
7. Documentation

## License

MIT
