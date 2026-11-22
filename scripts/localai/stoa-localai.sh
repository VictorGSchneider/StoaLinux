#!/bin/bash
# stoa-localai: LocalAI (texto + imagem num servidor só) como serviço de usuário.
#
#   stoa-localai [open]  sobe o servidor, espera ficar pronto e abre a UI no navegador
#   stoa-localai start   sobe sem abrir o navegador
#   stoa-localai stop    para o servidor (libera a VRAM)
#   stoa-localai restart | status
#   stoa-localai run     em primeiro plano (é o que o serviço executa)
#
# Só escuta em 127.0.0.1 (o padrão do local-ai é *:8080, aberto na rede, sem login).
# Modelos: ~/Models (GGUFs em llm/, checkpoints SDXL na raiz), descritos em
# ~/.config/localai/models.yaml (config/localai/models.yaml no repositório).
# Um backend carregado por vez; o ocioso é descarregado depois de 5 min.
ADDR="${STOA_LOCALAI_ADDR:-127.0.0.1:8080}"
UNIT=stoa-localai

case "${1:-open}" in
  run)
    exec local-ai run --address "$ADDR" \
      --models-path "$HOME/Models" \
      --backends-path "$HOME/.local/share/localai/backends" \
      --models-config-file "$HOME/.config/localai/models.yaml" \
      --max-active-backends 1 --enable-watchdog-idle --watchdog-idle-timeout 5m
    ;;
  start)   systemctl --user start "$UNIT" ;;
  stop)    systemctl --user stop "$UNIT" ;;
  restart) systemctl --user restart "$UNIT" ;;
  status)  systemctl --user status "$UNIT" --no-pager ;;
  open)
    systemctl --user start "$UNIT" || exit 1
    for _ in $(seq 60); do
      curl -sf -m 1 "http://$ADDR/v1/models" >/dev/null && break
      sleep 1
    done
    exec xdg-open "http://$ADDR"
    ;;
  *) echo "uso: stoa-localai [open|start|stop|restart|status|run]" >&2; exit 2 ;;
esac
