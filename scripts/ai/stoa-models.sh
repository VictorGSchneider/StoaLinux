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
    exec "$HOME/.local/bin/llama" serve \
      --models-dir "$HOME/Models/llm" \
      --models-preset "$HOME/.config/llama/presets.ini" \
      --models-max 1 --host 127.0.0.1 --port "${1:-$PORT}" \
      --ui-mcp-proxy
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
