#!/usr/bin/env python3
"""stoa-models-ollama: a interface web do llama.cpp (StoaAI) conversando com o Ollama.

A interface do llama só fala HTTP com um servidor llama (/props, /models,
/models/load, /v1/chat/completions...). Este servidor entrega a mesma interface
(a cópia com o nome StoaAI, gerada por stoa-models-ui.py) e traduz essas chamadas
para o Ollama em 127.0.0.1:11434:

  /props, /models, /v1/models   montados a partir de /api/tags, /api/ps e /api/show
  /models/load, /models/unload  /api/generate (keep_alive) + eventos em /models/sse
  /v1/chat/completions          repassado ao Ollama (mesmo formato OpenAI);
                                "reasoning" vira "reasoning_content", que a interface lê

Uso: stoa-models-ollama [porta]     (padrão 9940, só em 127.0.0.1)
"""
import http.client
import json
import mimetypes
import os
import posixpath
import queue
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlparse

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else int(os.environ.get("STOA_MODELS_OLLAMA_PORT", 9940))
OLLAMA = ("127.0.0.1", 11434)
HERE = os.path.dirname(os.path.realpath(__file__))
UI = os.path.expanduser("~/.cache/stoa/llama-ui")
HOSTS = {f"127.0.0.1:{PORT}", f"localhost:{PORT}"}
ORIGINS = {f"http://127.0.0.1:{PORT}", f"http://localhost:{PORT}"}
mimetypes.add_type("text/javascript", ".js")
mimetypes.add_type("application/manifest+json", ".webmanifest")

_info, _info_lock = {}, threading.Lock()
_clients, _clients_lock = [], threading.Lock()  # filas dos clientes de /models/sse


# ---- Ollama ------------------------------------------------------------------
def oll(method, path, body=None, timeout=30):
    c = http.client.HTTPConnection(*OLLAMA, timeout=timeout)
    try:
        c.request(method, path, None if body is None else json.dumps(body),
                  {"Content-Type": "application/json"})
        r = c.getresponse()
        return r.status, r.read()
    finally:
        c.close()


def ojson(method, path, body=None):
    status, data = oll(method, path, body)
    if status != 200:
        raise RuntimeError(f"Ollama HTTP {status}: {data[:200]!r}")
    return json.loads(data)


def model_info(name):
    """(capacidades, contexto nativo), com cache."""
    with _info_lock:
        if name in _info:
            return _info[name]
    try:
        j = ojson("POST", "/api/show", {"model": name})
        caps = j.get("capabilities") or []
        ctx = next((v for k, v in (j.get("model_info") or {}).items() if k.endswith(".context_length")), 4096)
    except Exception:
        caps, ctx = [], 4096
    with _info_lock:
        _info[name] = (caps, ctx)
    return caps, ctx


def model_entry(m, loaded):
    name = m["name"]
    caps, ctx = model_info(name)
    return {
        "id": name, "aliases": [name], "tags": [], "object": "model", "owned_by": "ollama",
        "created": int(time.time()),
        "status": {"value": "loaded" if name in loaded else "unloaded", "args": [], "preset": ""},
        "architecture": {"input_modalities": ["text"] + (["image"] if "vision" in caps else []),
                         "output_modalities": ["text"]},
        "source": "ollama", "can_remove": False, "context_length": ctx,
    }


def models_list():
    tags = ojson("GET", "/api/tags").get("models") or []
    loaded = {m["name"] for m in (ojson("GET", "/api/ps").get("models") or [])}
    return {"data": [model_entry(m, loaded) for m in tags], "object": "list"}


def props_router():
    return {"role": "router", "max_instances": 1, "models_autoload": True, "model_alias": "ollama",
            "model_path": "none", "default_generation_settings": {"params": None, "n_ctx": 0},
            "ui_settings": {}, "build_info": "stoa-ollama", "cors_proxy_enabled": False}


def props_model(name):
    caps, ctx = model_info(name)
    tools = "tools" in caps
    return {"default_generation_settings": {"params": {}, "n_ctx": ctx}, "total_slots": 1,
            "model_alias": name, "model_ftype": "", "model_path": "ollama://" + name,
            "modalities": {"vision": "vision" in caps, "video": False, "audio": False},
            "media_marker": "", "endpoint_slots": True, "endpoint_props": False,
            "endpoint_metrics": False, "ui": True, "ui_settings": {}, "chat_template": "",
            "chat_template_caps": {
                "supports_object_arguments": True, "supports_parallel_tool_calls": tools,
                "supports_preserve_reasoning": False, "supports_reasoning_effort": False,
                "supports_string_content": True, "supports_system_role": True,
                "supports_tool_calls": tools, "supports_tools": tools,
                "supports_typed_content": False, "reasoning_effort_levels": [],
                "reasoning_effort_rejected": []},
            "bos_token": "", "eos_token": "", "build_info": "stoa-ollama", "is_sleeping": False,
            "cors_proxy_enabled": False}


def broadcast(model, event, data):
    msg = "data: " + json.dumps({"model": model, "event": event, "data": data}) + "\n\n"
    with _clients_lock:
        for q in _clients:
            q.put(msg)


def fix_reasoning(obj):
    """Ollama manda o raciocínio em "reasoning"; a interface do llama lê "reasoning_content"."""
    for ch in obj.get("choices") or []:
        for key in ("delta", "message"):
            d = ch.get(key)
            if isinstance(d, dict) and d.get("reasoning") and "reasoning_content" not in d:
                d["reasoning_content"] = d["reasoning"]
    return obj


# ---- HTTP --------------------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    server_version = "stoa-models-ollama"

    def log_message(self, *a):
        pass

    # respostas
    def _send(self, code, body=b"", ctype="application/json", extra=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _json(self, obj, code=200):
        self._send(code, json.dumps(obj, ensure_ascii=False).encode())

    def _err(self, code, msg, typ="invalid_request_error"):
        self._json({"error": {"code": code, "message": msg, "type": typ}}, code)

    # segurança: só localhost e, nos POST, só a própria origem (evita CSRF de outros sites)
    def _ok(self, post):
        if self.headers.get("Host", "") not in HOSTS:
            return False
        origin = self.headers.get("Origin")
        return not post or origin is None or origin in ORIGINS

    def do_GET(self):
        if not self._ok(False):
            return self._err(403, "forbidden")
        u = urlparse(self.path)
        p, q = u.path.rstrip("/") or "/", parse_qs(u.query)
        model = (q.get("model") or [""])[0]
        try:
            if p in ("/models", "/v1/models"):
                return self._json(models_list())
            if p == "/props":
                return self._json(props_model(model) if model else props_router())
            if p == "/slots":
                if not model:
                    return self._err(400, "model name is missing from the request")
                return self._json([{"id": 0, "n_ctx": model_info(model)[1], "speculative": False,
                                    "is_processing": False}])
            if p == "/health":
                return self._json({"status": "ok"})
            if p == "/models/sse":
                return self._sse()
            if p in ("/tools", "/cors-proxy"):
                return self._json({"error": {"message": "this feature is disabled",
                                             "type": "feature_disabled"}}, 403)
        except Exception as e:
            return self._err(502, f"Ollama não respondeu: {e}", "server_error")
        self._static(p)

    def do_POST(self):
        if not self._ok(True):
            return self._err(403, "forbidden")
        p = urlparse(self.path).path.rstrip("/")
        try:
            n = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(n) if 0 < n < 20_000_000 else b""
            if p == "/v1/chat/completions":
                return self._chat(raw)
            body = json.loads(raw or b"{}")
            name = body.get("model") or ""
            if p == "/models/load" and name:
                broadcast(name, "model_status", {"status": "loading"})
                oll("POST", "/api/generate", {"model": name, "keep_alive": "10m"}, timeout=300)
                broadcast(name, "status_change", {"status": "loaded", "info": model_entry({"name": name}, {name})})
                return self._json({"success": True})
            if p == "/models/unload" and name:
                oll("POST", "/api/generate", {"model": name, "keep_alive": 0})
                broadcast(name, "status_change", {"status": "unloaded"})
                return self._json({"success": True})
        except Exception as e:
            return self._err(502, f"Ollama não respondeu: {e}", "server_error")
        self._err(404, "not found", "not_found_error")

    def _sse(self):
        q = queue.Queue()
        with _clients_lock:
            _clients.append(q)
        try:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            while True:
                try:
                    msg = q.get(timeout=15)
                except queue.Empty:
                    msg = ": ping\n\n"
                self.wfile.write(msg.encode())
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            with _clients_lock:
                _clients.remove(q)

    def _chat(self, raw):
        req = json.loads(raw)
        stream = bool(req.get("stream"))
        c = http.client.HTTPConnection(*OLLAMA, timeout=900)
        try:
            c.request("POST", "/v1/chat/completions", json.dumps(req), {"Content-Type": "application/json"})
            r = c.getresponse()
            if not stream or r.status != 200:
                data = r.read()
                if r.status == 200:
                    data = json.dumps(fix_reasoning(json.loads(data))).encode()
                return self._send(r.status, data, r.getheader("Content-Type", "application/json"))
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            for line in r:
                if line.startswith(b"data: {"):
                    try:
                        line = b"data: " + json.dumps(fix_reasoning(json.loads(line[6:]))).encode() + b"\n"
                    except ValueError:
                        pass
                self.wfile.write(line)
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass  # o navegador parou a resposta
        except OSError as e:
            if not self.wfile.closed:
                try:
                    self._err(502, f"Ollama não respondeu: {e}", "server_error")
                except OSError:
                    pass
        finally:
            c.close()

    def _static(self, path):
        rel = posixpath.normpath(unquote(path)).lstrip("/")
        full = os.path.realpath(os.path.join(UI, rel))
        if not (full == UI or full.startswith(UI + os.sep)) or not os.path.isfile(full):
            if "." in posixpath.basename(rel) or rel.startswith("_app/"):
                return self._err(404, "not found", "not_found_error")
            full = os.path.join(UI, "index.html")  # rotas da SPA
        with open(full, "rb") as f:
            data = f.read()
        self._send(200, data, mimetypes.guess_type(full)[0] or "application/octet-stream")


def ensure_ui():
    brand = os.path.join(HERE, "stoa-models-ui.py")
    r = subprocess.run([sys.executable, "-I", brand, "--ensure"], capture_output=True, text=True)
    if r.returncode or not os.path.exists(os.path.join(UI, "index.html")):
        sys.exit("não consegui gerar a interface StoaAI: " + (r.stderr or r.stdout).strip()[:300])


if __name__ == "__main__":
    ensure_ui()
    print(f"stoa-models-ollama -> http://localhost:{PORT}", flush=True)
    try:
        ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
    except KeyboardInterrupt:
        pass
