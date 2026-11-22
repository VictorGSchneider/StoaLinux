#!/bin/bash
# stoa-models-llama: llama serve (modo router) com os modelos de ~/Models/llm, mais o
# stoa-mcp-web (busca/leitura de páginas) como serviços de usuário do systemd.
#
#   stoa-models-llama [open]  sobe tudo, espera ficar pronto e abre a UI no navegador
#   stoa-models-llama start   sobe tudo sem abrir o navegador
#   stoa-models-llama stop    para tudo (libera a VRAM)
#   stoa-models-llama restart | status
#   stoa-models-llama run [porta]   em primeiro plano (é o que o serviço executa)
#
# --ui-mcp-proxy: UI web usa servidores MCP públicos. NÃO use
# --ui-mcp-proxy-allow-private-urls (abriria a rede local).
PORT=9931
UNITS=(stoa-models-llama stoa-mcp-web)

case "${1:-open}" in
  run)
    shift
    LLAMA="$HOME/.local/bin/llama"
    # Interface com o nome StoaAI na aba (cópia gerada, refeita se o llama mudar de versão).
    UI="$HOME/.cache/stoa/llama-ui"; HERE=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
    python3 -I "$HERE/stoa-models-ui.py" --ensure >&2 \
      || echo "stoa-models-llama: usando a interface original do llama" >&2
    UIARG=(); [ -f "$UI/index.html" ] && UIARG=(--path "$UI")
    exec "$LLAMA" serve \
      --models-dir "$HOME/Models/llm" \
      --models-preset "$HOME/.config/llama/presets.ini" \
      --models-max 1 --host 127.0.0.1 --port "${1:-$PORT}" \
      --ui-mcp-proxy "${UIARG[@]}"
    ;;
  start)   systemctl --user start stoa-models-llama ;;
  stop)    systemctl --user stop "${UNITS[@]}" ;;
  restart) systemctl --user restart "${UNITS[@]}" ;;
  status)  systemctl --user status "${UNITS[@]}" --no-pager ;;
  open)
    systemctl --user start stoa-models-llama || exit 1
    for _ in $(seq 60); do
      curl -sf -m 1 "http://127.0.0.1:$PORT/v1/models" >/dev/null && break
      sleep 1
    done
    exec xdg-open "http://localhost:$PORT"
    ;;
  *) echo "uso: stoa-models-llama [open|start|stop|restart|status|run [porta]]" >&2; exit 2 ;;
esac
