#!/usr/bin/env python3
"""stoa-models-ui: gera uma cópia da interface web do llama com o nome "StoaAI".

O título da aba é texto fixo dentro do bundle da interface ("llama-ui",
"Search · llama.cpp"). Este script sobe um llama serve temporário, baixa a
interface, troca só essas strings de título e grava o resultado em OUT
(servido depois com `llama serve --path OUT`).

Uso: stoa-models-ui.py OUT [LLAMA_BIN]     (OUT é recriado por inteiro)
     stoa-models-ui.py --ensure            gera em ~/.cache/stoa/llama-ui só se faltar
                                          ou se a versão do llama mudou
"""
import fcntl, gzip, hashlib, os, posixpath, re, shutil, signal, subprocess, sys, time
import urllib.request

NAME = "StoaAI"
PORT = 9939
ensure = sys.argv[1:2] == ["--ensure"]
out = os.path.expanduser("~/.cache/stoa/llama-ui") if ensure else os.path.abspath(sys.argv[1])
llama = sys.argv[2] if len(sys.argv) > 2 and not ensure else os.path.expanduser("~/.local/bin/llama")
base = f"http://127.0.0.1:{PORT}/"
TITLE_PATTERNS = [  # (regex, substituição): só sufixos/atribuições de título e o nome do app
    (re.compile(r" - llama-ui`"), " - " + NAME + "`"),
    (re.compile(r"title=`llama-ui`"), "title=`" + NAME + "`"),
    (re.compile(r"=`llama-ui`([,;])"), "=`" + NAME + r"`\g<1>"),  # appName padrão
    (re.compile(r"(Search · )llama\.cpp`"), r"\g<1>" + NAME + "`"),
]


def get(path):
    req = urllib.request.Request(base + path, headers={"Accept-Encoding": "gzip"})
    with urllib.request.urlopen(req, timeout=15) as r:
        data = r.read()
        return gzip.decompress(data) if r.headers.get("Content-Encoding") == "gzip" else data


os.makedirs(os.path.dirname(out), exist_ok=True)
lock = open(out + ".lock", "w")
fcntl.flock(lock, fcntl.LOCK_EX)  # stoa-models-llama e stoa-models-ollama podem pedir ao mesmo tempo
ver = (subprocess.run([llama, "--version"], capture_output=True, text=True).stdout
       or "").strip().splitlines()[:1] or ["?"]
ver = ver[0]
try:
    uptodate = os.path.exists(os.path.join(out, "index.html")) and open(out + ".ver").read().strip() == ver
except OSError:
    uptodate = False
if ensure and uptodate:
    sys.exit(0)

srv = subprocess.Popen(
    [llama, "serve", "--host", "127.0.0.1", "--port", str(PORT),
     "--models-dir", os.path.expanduser("~/Models/llm")],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
tmp = out + ".tmp"
try:
    for _ in range(60):
        try:
            get("v1/models"); break
        except Exception:
            time.sleep(0.5)
    else:
        sys.exit("llama temporário não respondeu")
    shutil.rmtree(tmp, ignore_errors=True)
    seen, todo, failed = set(), ["", "service-worker.js", "sw.js"], []
    while todo:
        p = todo.pop()
        if p in seen:
            continue
        seen.add(p)
        try:
            data = get(p)
        except Exception as e:
            failed.append(p); continue
        fn = os.path.join(tmp, p or "index.html")
        os.makedirs(os.path.dirname(fn), exist_ok=True)
        open(fn, "wb").write(data)
        if p == "" or p.endswith((".js", ".html", ".webmanifest")):
            txt, cur = data.decode("utf8", "replace"), posixpath.dirname(p)
            for m in re.findall(
                r'["\'`(]((?:\./|\.\./|_app/|[A-Za-z0-9_-]+\.(?:png|ico|svg))[A-Za-z0-9_./~-]*\.'
                r'(?:js|css|svg|png|ico|webmanifest|json|woff2?))', txt):
                todo.append(posixpath.normpath(posixpath.join("" if m.startswith("_app/") else cur, m)))
    patched = 0
    for root, _d, files in os.walk(os.path.join(tmp, "_app")):
        for f in files:
            if not f.endswith(".js"):
                continue
            fp = os.path.join(root, f)
            t = open(fp, encoding="utf8", errors="surrogateescape").read()
            n = t
            for rx, rep in TITLE_PATTERNS:
                n = rx.sub(rep, n)
            if n != t:
                open(fp, "w", encoding="utf8", errors="surrogateescape").write(n); patched += 1
    # avisa o stoa-models-watch que há uma aba aberta (ele desliga tudo quando a última fecha)
    idx = os.path.join(tmp, "index.html")
    h = open(idx, encoding="utf8").read()
    beacon = '<script>try{new EventSource("http://127.0.0.1:9942/alive")}catch(e){}</script>'
    for anchor in ("</head>", "</body>"):
        if anchor in h:
            h = h.replace(anchor, beacon + anchor, 1)
            break
    else:
        sys.exit("index.html sem </head> nem </body>: a interface mudou?")
    open(idx, "w", encoding="utf8").write(h)
    stamp = hashlib.sha1(h.encode()).hexdigest()[:8]
    # service worker: muda a versão para o navegador reinstalar e refazer o cache
    swp = os.path.join(tmp, "service-worker.js")
    if os.path.exists(swp):
        t = open(swp, encoding="utf8", errors="surrogateescape").read()
        t2 = re.sub(r"version:`(\d+)`", r"version:`\g<1>-" + NAME.lower() + "-" + stamp + "`", t)
        open(swp, "w", encoding="utf8", errors="surrogateescape").write(t2)
        sw_ok = t2 != t
    else:
        sw_ok = False
    if not patched or not os.path.exists(os.path.join(tmp, "index.html")):
        sys.exit("nenhum título encontrado para trocar: a interface mudou?")
    shutil.rmtree(out, ignore_errors=True)
    os.rename(tmp, out)
    open(out + ".ver", "w").write(ver)
    print(f"{len(seen) - len(failed)} arquivos, {patched} com título trocado, service worker {'atualizado' if sw_ok else 'NÃO encontrado'}" + (f", {len(failed)} falharam" if failed else ""))
finally:
    try:
        os.killpg(srv.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    shutil.rmtree(tmp, ignore_errors=True)
