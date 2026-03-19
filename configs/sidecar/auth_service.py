# configs/sidecar/auth_service.py
"""Spectre API key validation service.

Called by NGINX auth_request on every proxied request.
Returns 200 (allow) or 401 (deny).

Port: 8081
"""
import hashlib
import hmac
import os
import signal

from fastapi import FastAPI, Request, Response

app = FastAPI(title="Spectre Auth", docs_url=None, redoc_url=None)

# Load API key hashes from env file
# Format: comma-separated SHA-256 hex digests
_valid_hashes: set[str] = set()


def _load_keys() -> None:
    global _valid_hashes
    raw = os.environ.get("SPECTRE_API_KEY_HASHES", "")
    _valid_hashes = {h.strip() for h in raw.split(",") if h.strip()}


@app.on_event("startup")
async def startup() -> None:
    _load_keys()
    # Reload keys on SIGHUP
    signal.signal(signal.SIGHUP, lambda *_: _load_keys())


def _hash_key(key: str) -> str:
    return hashlib.sha256(key.encode()).hexdigest()


@app.get("/validate")
async def validate(request: Request) -> Response:
    api_key = request.headers.get("x-api-key", "")
    if not api_key or not _valid_hashes:
        return Response(status_code=401)

    key_hash = _hash_key(api_key)
    # Constant-time comparison against each valid hash
    for valid_hash in _valid_hashes:
        if hmac.compare_digest(key_hash, valid_hash):
            return Response(status_code=200)

    return Response(status_code=401)


@app.get("/healthz")
async def healthz() -> dict:
    return {"status": "ok", "keys_loaded": len(_valid_hashes)}
