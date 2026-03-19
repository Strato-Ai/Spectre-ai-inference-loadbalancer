# configs/sidecar/sidecar_service.py
"""Spectre sidecar — health monitoring and routing recommendations.

Polls backends every 5 seconds for GPU metrics and model status.
Provides /health and /route endpoints.

Port: 8080
"""
import asyncio
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from enum import Enum
from typing import Any

import httpx
from fastapi import FastAPI, Response
from pydantic import BaseModel

# --- Configuration ---
BACKEND_HOSTS = [
    {"ip": "10.0.2.10", "port": 1234, "id": 1},
    {"ip": "10.0.2.11", "port": 1234, "id": 2},
    {"ip": "10.0.2.12", "port": 1234, "id": 3},
]
POLL_INTERVAL = 5.0
STALE_THRESHOLD = POLL_INTERVAL * 2
GPU_MONITOR_PORT = 9090


class BackendStatus(str, Enum):
    HEALTHY = "healthy"
    DEGRADED = "degraded"
    DOWN = "down"


class BackendHealth(BaseModel):
    id: int
    ip: str
    status: BackendStatus
    models: list[str] = []
    gpu_utilization: float = 0.0
    vram_percent: float = 0.0
    active_requests: int = 0
    max_requests: int = 8
    load_score: float = 100.0
    gpu_type: str = "unknown"
    stale: bool = False


class ClusterHealth(BaseModel):
    status: str
    backends: list[BackendHealth]
    total_models: list[str]


class RouteRequest(BaseModel):
    model: str


class RouteResponse(BaseModel):
    backend_ip: str
    backend_id: int
    load_score: float


# --- State ---
@dataclass
class BackendState:
    health: dict[str, BackendHealth] = field(default_factory=dict)
    circuit_breaker: dict[str, int] = field(default_factory=dict)  # failure counts
    CB_THRESHOLD: int = 3


state = BackendState()


def _compute_load_score(gpu_util: float, vram_pct: float, active: int, max_req: int) -> float:
    req_pct = (active / max_req * 100) if max_req > 0 else 0
    return 0.5 * gpu_util + 0.3 * vram_pct + 0.2 * req_pct


async def _poll_backend(client: httpx.AsyncClient, host: dict[str, Any]) -> None:
    ip = host["ip"]
    backend_id = host["id"]
    key = ip

    try:
        # Check inference API for models
        models_resp = await client.get(f"http://{ip}:{host['port']}/v1/models")
        models_data = models_resp.json()
        model_ids = [m["id"] for m in models_data.get("data", [])]

        # Check GPU metrics
        gpu_util = 0.0
        vram_pct = 0.0
        active_reqs = 0
        gpu_type = "cpu"
        try:
            metrics_resp = await client.get(f"http://{ip}:{GPU_MONITOR_PORT}/metrics")
            metrics = metrics_resp.json()
            gpu_util = metrics.get("gpu_utilization", 0.0)
            vram_pct = metrics.get("vram_percent", 0.0)
            active_reqs = metrics.get("active_requests", 0)
            gpu_type = metrics.get("gpu_type", "cpu")
        except (httpx.RequestError, Exception):
            pass  # GPU monitor optional; inference API is what matters

        load_score = _compute_load_score(gpu_util, vram_pct, active_reqs, 8)

        state.health[key] = BackendHealth(
            id=backend_id,
            ip=ip,
            status=BackendStatus.HEALTHY,
            models=model_ids,
            gpu_utilization=gpu_util,
            vram_percent=vram_pct,
            active_requests=active_reqs,
            load_score=load_score,
            gpu_type=gpu_type,
        )
        state.circuit_breaker[key] = 0

    except (httpx.RequestError, Exception):
        failures = state.circuit_breaker.get(key, 0) + 1
        state.circuit_breaker[key] = failures

        if failures >= state.CB_THRESHOLD:
            state.health[key] = BackendHealth(
                id=backend_id,
                ip=ip,
                status=BackendStatus.DOWN,
                load_score=100.0,
            )
        elif key in state.health:
            state.health[key].status = BackendStatus.DEGRADED
            state.health[key].stale = True


async def _poll_loop(client: httpx.AsyncClient) -> None:
    while True:
        tasks = [_poll_backend(client, host) for host in BACKEND_HOSTS]
        await asyncio.gather(*tasks, return_exceptions=True)
        await asyncio.sleep(POLL_INTERVAL)


@asynccontextmanager
async def lifespan(app: FastAPI):
    async with httpx.AsyncClient(
        timeout=httpx.Timeout(connect=2.0, read=3.0, write=3.0, pool=5.0),
        limits=httpx.Limits(max_connections=10, max_keepalive_connections=6),
    ) as client:
        poll_task = asyncio.create_task(_poll_loop(client))
        yield
        poll_task.cancel()
        try:
            await poll_task
        except asyncio.CancelledError:
            pass


app = FastAPI(title="Spectre Sidecar", lifespan=lifespan)


@app.get("/health")
async def health() -> Response:
    backends = list(state.health.values())
    if not backends:
        return Response(
            content='{"status":"down","backends":[],"total_models":[]}',
            status_code=503,
            media_type="application/json",
        )

    healthy = [b for b in backends if b.status != BackendStatus.DOWN]
    all_models = sorted({m for b in backends for m in b.models})

    if len(healthy) == len(backends):
        cluster_status = "healthy"
    elif healthy:
        cluster_status = "degraded"
    else:
        cluster_status = "down"

    result = ClusterHealth(
        status=cluster_status,
        backends=backends,
        total_models=all_models,
    )

    status_code = 200 if cluster_status != "down" else 503
    return Response(
        content=result.model_dump_json(),
        status_code=status_code,
        media_type="application/json",
    )


@app.post("/route")
async def route(req: RouteRequest) -> RouteResponse | Response:
    candidates = [
        b for b in state.health.values()
        if b.status != BackendStatus.DOWN and req.model in b.models
    ]

    if not candidates:
        # Check if model exists at all
        all_models = {m for b in state.health.values() for m in b.models}
        if req.model not in all_models:
            return Response(
                content=f'{{"error":"model not found: {req.model}"}}',
                status_code=404,
                media_type="application/json",
            )
        return Response(
            content='{"error":"all backends for this model are down"}',
            status_code=503,
            media_type="application/json",
        )

    best = min(candidates, key=lambda b: b.load_score)
    return RouteResponse(
        backend_ip=best.ip,
        backend_id=best.id,
        load_score=best.load_score,
    )


@app.get("/backends")
async def list_backends() -> list[BackendHealth]:
    return list(state.health.values())
