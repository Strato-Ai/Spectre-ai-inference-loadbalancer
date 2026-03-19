# configs/sidecar/gpu_monitor_agent.py
"""Spectre GPU monitor agent — runs on each backend server.

Reports GPU utilization, VRAM, temperature, and power metrics.
Supports NVIDIA (pynvml/nvidia-smi), Apple Silicon (macmon), and CPU fallback.

Port: 9090
"""
import json
import os
import platform
import shutil
import subprocess
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI
from pydantic import BaseModel

# --- Try importing optional GPU libraries ---
try:
    import pynvml
    HAS_PYNVML = True
except ImportError:
    HAS_PYNVML = False

try:
    import psutil
    HAS_PSUTIL = True
except ImportError:
    HAS_PSUTIL = False


class GpuMetrics(BaseModel):
    gpu_utilization: float = 0.0
    vram_percent: float = 0.0
    active_requests: int = 0
    max_requests: int = 8
    load_score: float = 0.0
    temperature: float | None = None
    power_watts: float | None = None
    gpu_type: str = "unknown"
    gpu_name: str = "unknown"
    stale: bool = False


# --- GPU Backend Implementations ---

def _detect_gpu_type() -> str:
    if HAS_PYNVML:
        try:
            pynvml.nvmlInit()
            count = pynvml.nvmlDeviceGetCount()
            if count > 0:
                return "nvidia"
        except Exception:
            pass
    if platform.system() == "Darwin" and platform.machine() == "arm64":
        if shutil.which("macmon"):
            return "apple_silicon"
    return "cpu"


def _read_nvidia() -> dict[str, Any]:
    if HAS_PYNVML:
        try:
            handle = pynvml.nvmlDeviceGetHandleByIndex(0)
            util = pynvml.nvmlDeviceGetUtilizationRates(handle)
            mem = pynvml.nvmlDeviceGetMemoryInfo(handle)
            temp = pynvml.nvmlDeviceGetTemperature(handle, pynvml.NVML_TEMPERATURE_GPU)
            power = pynvml.nvmlDeviceGetPowerUsage(handle) / 1000.0
            name = pynvml.nvmlDeviceGetName(handle)
            if isinstance(name, bytes):
                name = name.decode()
            return {
                "gpu_utilization": float(util.gpu),
                "vram_percent": mem.used / mem.total * 100 if mem.total > 0 else 0,
                "temperature": float(temp),
                "power_watts": power,
                "gpu_type": "nvidia",
                "gpu_name": name,
            }
        except Exception:
            pass

    # Fallback to nvidia-smi
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,name",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5,
        )
        parts = result.stdout.strip().split(", ")
        if len(parts) >= 6:
            mem_used, mem_total = float(parts[1]), float(parts[2])
            return {
                "gpu_utilization": float(parts[0]),
                "vram_percent": mem_used / mem_total * 100 if mem_total > 0 else 0,
                "temperature": float(parts[3]),
                "power_watts": float(parts[4]),
                "gpu_type": "nvidia",
                "gpu_name": parts[5].strip(),
            }
    except Exception:
        pass

    return {}


def _read_apple_silicon() -> dict[str, Any]:
    try:
        result = subprocess.run(
            ["macmon", "pipe", "--interval", "1000", "--count", "1"],
            capture_output=True, text=True, timeout=5,
        )
        data = json.loads(result.stdout.strip().splitlines()[-1])
        return {
            "gpu_utilization": data.get("gpu_usage", 0.0) * 100,
            "vram_percent": data.get("memory_used", 0) / data.get("memory_total", 1) * 100,
            "temperature": data.get("temp_gpu", None),
            "power_watts": data.get("gpu_power_w", None),
            "gpu_type": "apple_silicon",
            "gpu_name": f"Apple {platform.machine()}",
        }
    except Exception:
        return {}


def _read_cpu() -> dict[str, Any]:
    if HAS_PSUTIL:
        return {
            "gpu_utilization": psutil.cpu_percent(interval=0.1),
            "vram_percent": psutil.virtual_memory().percent,
            "temperature": None,
            "power_watts": None,
            "gpu_type": "cpu",
            "gpu_name": "CPU fallback",
        }
    return {
        "gpu_utilization": 0.0,
        "vram_percent": 0.0,
        "gpu_type": "cpu",
        "gpu_name": "CPU fallback (no psutil)",
    }


# --- State ---
_gpu_type: str = "unknown"
_readers = {
    "nvidia": _read_nvidia,
    "apple_silicon": _read_apple_silicon,
    "cpu": _read_cpu,
}


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _gpu_type
    _gpu_type = _detect_gpu_type()
    if HAS_PYNVML and _gpu_type == "nvidia":
        try:
            pynvml.nvmlInit()
        except Exception:
            pass
    yield
    if HAS_PYNVML and _gpu_type == "nvidia":
        try:
            pynvml.nvmlShutdown()
        except Exception:
            pass


app = FastAPI(title="Spectre GPU Monitor", lifespan=lifespan)


def _compute_load_score(gpu_util: float, vram_pct: float, active: int, max_req: int) -> float:
    req_pct = (active / max_req * 100) if max_req > 0 else 0
    return 0.5 * gpu_util + 0.3 * vram_pct + 0.2 * req_pct


@app.get("/metrics")
async def metrics() -> GpuMetrics:
    reader = _readers.get(_gpu_type, _read_cpu)
    raw = reader()

    gpu_util = raw.get("gpu_utilization", 0.0)
    vram_pct = raw.get("vram_percent", 0.0)
    active = 0  # TODO: query inference engine for active request count
    max_req = int(os.environ.get("SPECTRE_MAX_REQUESTS", "8"))

    return GpuMetrics(
        gpu_utilization=gpu_util,
        vram_percent=vram_pct,
        active_requests=active,
        max_requests=max_req,
        load_score=_compute_load_score(gpu_util, vram_pct, active, max_req),
        temperature=raw.get("temperature"),
        power_watts=raw.get("power_watts"),
        gpu_type=raw.get("gpu_type", _gpu_type),
        gpu_name=raw.get("gpu_name", "unknown"),
    )


@app.get("/healthz")
async def healthz() -> dict:
    return {"status": "ok", "gpu_type": _gpu_type}
