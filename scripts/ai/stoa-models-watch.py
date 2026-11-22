#!/usr/bin/env python3
"""stoa-models-watch: desliga o StoaAI quando a última aba do chat é fechada.

Cada aba da interface (llama.cpp em :9931, Ollama em :9940) abre uma conexão
EventSource para http://127.0.0.1:9942/alive (o script é injetado na interface
por stoa-models-ui.py). Quando todas as conexões caem e ficam assim por GRACE
segundos (assim um reload não desliga nada), roda `stoa-models stop` e sai.
Só desliga depois de ter visto ao menos uma aba, então usar só a API não é afetado.

Uso: stoa-models-watch [porta]      (padrão 9942, só em 127.0.0.1)
Env: STOA_MODELS_GRACE (segundos, padrão 30), STOA_MODELS_STOP_CMD (padrão: stoa-models stop)
"""
import os
import select
import shlex
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else int(os.environ.get("STOA_MODELS_WATCH_PORT", 9942))
GRACE = float(os.environ.get("STOA_MODELS_GRACE", 30))
STOP = os.environ.get("STOA_MODELS_STOP_CMD", os.path.expanduser("~/.local/bin/stoa-models") + " stop")
HOSTS = {f"127.0.0.1:{PORT}", f"localhost:{PORT}"}
ORIGINS = {f"http://{h}:{p}" for h in ("localhost", "127.0.0.1") for p in (9931, 9940)}

lock = threading.Lock()
count, seen, zero_since = 0, False, None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        global count, seen, zero_since
        origin = self.headers.get("Origin")
        if self.path.split("?")[0] != "/alive" or self.headers.get("Host", "") not in HOSTS or origin not in ORIGINS:
            self.send_response(403)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", origin)
        self.send_header("Vary", "Origin")
        self.end_headers()
        with lock:
            count += 1
            seen, zero_since = True, None
        try:
            while True:
                self.wfile.write(b": ping\n\n")
                self.wfile.flush()
                # espera até 2 s; se o navegador fechou a conexão, o socket fica legível (EOF)
                if select.select([self.connection], [], [], 2)[0] and not self.connection.recv(1024):
                    break
        except OSError:
            pass
        finally:
            with lock:
                count -= 1
                if count == 0:
                    zero_since = time.time()


def monitor():
    while True:
        time.sleep(1)
        with lock:
            due = seen and count == 0 and zero_since is not None and time.time() - zero_since >= GRACE
        if due:
            print("todas as abas fechadas: desligando", flush=True)
            subprocess.run(shlex.split(STOP))
            os._exit(0)


if __name__ == "__main__":
    threading.Thread(target=monitor, daemon=True).start()
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    srv.daemon_threads = True
    print(f"stoa-models-watch -> http://127.0.0.1:{PORT}/alive (grace {GRACE:g}s)", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
