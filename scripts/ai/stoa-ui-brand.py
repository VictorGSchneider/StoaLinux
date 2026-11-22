#!/usr/bin/env python3
"""stoa-ui-brand: gera uma cópia da interface web do llama com o nome "StoaAI".

O título da aba é texto fixo dentro do bundle da interface ("llama-ui",
"Search · llama.cpp"). Este script sobe um llama serve temporário, baixa a
interface, troca só essas strings de título e grava o resultado em OUT
(servido depois com `llama serve --path OUT`).

Uso: stoa-ui-brand.py OUT [LLAMA_BIN]     (OUT é recriado por inteiro)
"""
import gzip, os, posixpath, re, shutil, signal, subprocess, sys, time
import urllib.request

NAME = "StoaAI"
PORT = 9939
out = os.path.abspath(sys.argv[1])
llama = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/.local/bin/llama")
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
    seen, todo, failed = set(), [""], []
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
    if not patched or not os.path.exists(os.path.join(tmp, "index.html")):
        sys.exit("nenhum título encontrado para trocar: a interface mudou?")
    shutil.rmtree(out, ignore_errors=True)
    os.rename(tmp, out)
    print(f"{len(seen) - len(failed)} arquivos, {patched} com título trocado" + (f", {len(failed)} falharam" if failed else ""))
finally:
    try:
        os.killpg(srv.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    shutil.rmtree(tmp, ignore_errors=True)
