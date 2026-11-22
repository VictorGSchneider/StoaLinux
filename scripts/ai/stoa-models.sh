#!/bin/bash
# stoa-models: llama serve (modo router) com os modelos de ~/Models/llm, mais o
# stoa-mcp-web (busca/leitura de páginas) como serviços de usuário do systemd.
#
#   stoa-models [open]  sobe tudo, espera ficar pronto e abre a UI no navegador
#   stoa-models start   sobe tudo sem abrir o navegador
#   stoa-models stop    para tudo (libera a VRAM)
#   stoa-models restart | status
#   stoa-models run [porta]   em primeiro plano (é o que o serviço executa)
#
# --ui-mcp-proxy: UI web usa servidores MCP públicos. NÃO use
# --ui-mcp-proxy-allow-private-urls (abriria a rede local).
PORT=9931
UNITS=(stoa-models stoa-mcp-web)

case "${1:-open}" in
  run)
    shift
    LLAMA="$HOME/.local/bin/llama"
    # Interface com o nome StoaAI na aba (cópia gerada, refeita se o llama mudar de versão).
    UI="$HOME/.cache/stoa/llama-ui"; VER=$("$LLAMA" --version 2>&1 | head -1)
    if [ ! -f "$UI/index.html" ] || [ "$(cat "$UI.ver" 2>/dev/null)" != "$VER" ]; then
      HERE=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")"); mkdir -p "$(dirname "$UI")"
      if python3 -I "$HERE/stoa-ui-brand.py" "$UI" "$LLAMA" >&2; then echo "$VER" > "$UI.ver"
      else rm -rf "$UI" "$UI.ver"; echo "stoa-models: usando a interface original do llama" >&2; fi
    fi
    UIARG=(); [ -f "$UI/index.html" ] && UIARG=(--path "$UI")
    exec "$LLAMA" serve \
      --models-dir "$HOME/Models/llm" \
      --models-preset "$HOME/.config/llama/presets.ini" \
      --models-max 1 --host 127.0.0.1 --port "${1:-$PORT}" \
      --ui-mcp-proxy "${UIARG[@]}"
    ;;
  start)   systemctl --user start stoa-models ;;
  stop)    systemctl --user stop "${UNITS[@]}" ;;
  restart) systemctl --user restart "${UNITS[@]}" ;;
  status)  systemctl --user status "${UNITS[@]}" --no-pager ;;
  open)
    systemctl --user start stoa-models || exit 1
    for _ in $(seq 60); do
      curl -sf -m 1 "http://127.0.0.1:$PORT/v1/models" >/dev/null && break
      sleep 1
    done
    exec xdg-open "http://localhost:$PORT"
    ;;
  *) echo "uso: stoa-models [open|start|stop|restart|status|run [porta]]" >&2; exit 2 ;;
esac
