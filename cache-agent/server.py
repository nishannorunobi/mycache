"""
Cache Agent HTTP Server — runs inside mycache-redis container on port 8892.

Endpoints:
  GET  /health              liveness + Redis ping status
  GET  /api/redis/info      Redis INFO stats (memory, clients, keyspace)
  GET  /api/redis/clients   connected clients list
  POST /api/tasks           AI agent task (called by docker-manager-agent)
  WS   /ws/chat             streaming chat (proxied by orchestrator)
"""
import asyncio
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
import anthropic as _anthropic
from pydantic import BaseModel

AGENT_DIR = Path(__file__).parent
load_dotenv(AGENT_DIR / "agent.conf")

REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", "")
REDIS_HOST     = "127.0.0.1"
REDIS_PORT_INT = 6379

app = FastAPI(title="Cache Agent", version="1.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


# ── Redis helpers ─────────────────────────────────────────────────────────────

def _redis_cmd(*args) -> str:
    cmd = ["redis-cli", "-h", REDIS_HOST, "-p", str(REDIS_PORT_INT)]
    if REDIS_PASSWORD:
        cmd += ["-a", REDIS_PASSWORD, "--no-auth-warning"]
    cmd += list(args)
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
    return r.stdout.strip()


def _redis_running() -> bool:
    try:
        return _redis_cmd("PING") == "PONG"
    except Exception:
        return False


def _redis_info() -> dict:
    raw = _redis_cmd("INFO", "all")
    info: dict = {}
    section = "default"
    for line in raw.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            if line.startswith("# "):
                section = line[2:].lower()
            continue
        if ":" in line:
            k, _, v = line.partition(":")
            info[f"{section}.{k.strip()}"] = v.strip()
    return info


# ── Routes ────────────────────────────────────────────────────────────────────

@app.get("/")
def root():
    return RedirectResponse("/docs")


@app.get("/health")
def health():
    running = _redis_running()
    return {
        "status":        "ok" if running else "degraded",
        "agent":         "cache-agent",
        "redis_running": running,
        "time":          datetime.utcnow().isoformat(),
    }


@app.get("/api/redis/info")
def redis_info():
    if not _redis_running():
        return {"error": "Redis not reachable"}
    info = _redis_info()
    return {
        "redis_version":      info.get("server.redis_version"),
        "uptime_seconds":     info.get("server.uptime_in_seconds"),
        "connected_clients":  info.get("clients.connected_clients"),
        "used_memory_human":  info.get("memory.used_memory_human"),
        "peak_memory_human":  info.get("memory.used_memory_peak_human"),
        "total_commands":     info.get("stats.total_commands_processed"),
        "keyspace_hits":      info.get("stats.keyspace_hits"),
        "keyspace_misses":    info.get("stats.keyspace_misses"),
        "db0_keys":           info.get("keyspace.db0", "—"),
        "aof_enabled":        info.get("persistence.aof_enabled"),
        "role":               info.get("replication.role"),
    }


@app.get("/api/redis/clients")
def redis_clients():
    if not _redis_running():
        return {"error": "Redis not reachable"}
    raw = _redis_cmd("CLIENT", "LIST")
    clients = []
    for line in raw.splitlines():
        client: dict = {}
        for pair in line.split():
            if "=" in pair:
                k, _, v = pair.partition("=")
                client[k] = v
        if client:
            clients.append(client)
    return {"count": len(clients), "clients": clients}


# ── AI task endpoint ──────────────────────────────────────────────────────────

class TaskRequest(BaseModel):
    task: str

@app.post("/api/tasks")
def run_task(req: TaskRequest):
    api_key = os.getenv("ANTHROPIC_API_KEY", "")
    if not api_key:
        return {"error": "ANTHROPIC_API_KEY not set"}
    client = _anthropic.Anthropic(api_key=api_key)
    info_summary = json.dumps(_redis_info(), indent=2) if _redis_running() else "Redis not reachable"
    system = (
        "You are a Redis cache agent running inside a Docker container (mycache-redis). "
        "You can inspect Redis stats and report on cache health. "
        f"Current Redis info:\n{info_summary}"
    )
    msg = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=1024,
        system=system,
        messages=[{"role": "user", "content": req.task}],
    )
    return {"result": msg.content[0].text}


# ── WebSocket chat ────────────────────────────────────────────────────────────

@app.websocket("/ws/chat")
async def ws_chat(ws: WebSocket):
    await ws.accept()
    api_key = os.getenv("ANTHROPIC_API_KEY", "")
    client  = _anthropic.Anthropic(api_key=api_key) if api_key else None
    history: list = []
    try:
        while True:
            text = await ws.receive_text()
            history.append({"role": "user", "content": text})
            if not client:
                await ws.send_text(json.dumps({"type": "text", "text": "ANTHROPIC_API_KEY not set."}))
                await ws.send_text(json.dumps({"type": "done"}))
                continue
            loop = asyncio.get_event_loop()
            info_summary = await loop.run_in_executor(None, lambda: json.dumps(_redis_info(), indent=2) if _redis_running() else "Redis not reachable")
            system = (
                "You are a Redis cache agent running inside mycache-redis container. "
                "Help with Redis diagnostics, cache health, and key management. "
                f"Current Redis info:\n{info_summary}"
            )
            with client.messages.stream(
                model="claude-haiku-4-5-20251001",
                max_tokens=2048,
                system=system,
                messages=history,
            ) as stream:
                full = ""
                for chunk in stream.text_stream:
                    full += chunk
                    await ws.send_text(json.dumps({"type": "text", "text": chunk}))
            history.append({"role": "assistant", "content": full})
            await ws.send_text(json.dumps({"type": "done"}))
    except WebSocketDisconnect:
        pass
