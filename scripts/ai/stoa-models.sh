#!/bin/bash
# stoa-models: escolhe como conversar com os modelos locais.
#   stoa-models          janela para escolher entre llama (navegador) e Ollama (terminal)
#   stoa-models llama    sobe o llama serve + MCP e abre o chat StoaAI no navegador
#   stoa-models ollama   abre o chat StoaAI para o Ollama no navegador
#   stoa-models ollama-term  escolhe um modelo do Ollama e abre `ollama run` no kitty
#   stoa-models stop     para o llama serve, o MCP e o chat, e descarrega os modelos do Ollama
#   (ao fechar a última aba do chat, o stoa-models-watch roda `stoa-models stop` sozinho)
note() { notify-send "StoaAI" "$1" 2>/dev/null || echo "StoaAI: $1" >&2; }

ollama_web() {
  systemctl --user start stoa-models-ollama || exit 1
  for _ in $(seq 30); do curl -sf -m 1 http://127.0.0.1:9940/ >/dev/null && break; sleep 0.3; done
  exec xdg-open http://localhost:9940
}

ollama_term() {
  command -v ollama >/dev/null || { note "ollama não está instalado"; exit 1; }
  local models choice
  models=$(ollama list 2>/dev/null | awk 'NR>1 {print $1}')
  [ -n "$models" ] || { note "Ollama não respondeu ou não tem modelos (o serviço está ativo?)"; exit 1; }
  choice=$(printf '%s\n' "$models" | yad --list --title "StoaAI · Ollama" --text "Modelo:" \
    --column "Modelo" --print-column 1 --separator '' --width 460 --height 320 \
    --button "Cancelar:1" --button "Abrir:0") || exit 0
  [ -n "$choice" ] && exec kitty --title "StoaAI · $choice" ollama run "$choice"
}

case "${1:-choose}" in
  llama)  exec stoa-models-llama open ;;
  ollama) ollama_web ;;
  ollama-term) ollama_term ;;
  stop)
    stoa-models-llama stop
    systemctl --user stop stoa-models-ollama
    command -v ollama >/dev/null && ollama ps 2>/dev/null | awk 'NR>1 {print $1}' | xargs -r -n1 ollama stop
    systemctl --user stop stoa-models-watch  # por último: pode ser quem chamou
    ;;
  choose)
    pick=$(yad --list --title "StoaAI" --text "Como você quer conversar?" \
      --column "id:HD" --column "Motor" --column "Como abre" --print-column 1 --separator '' \
      llama  "llama.cpp"  "Navegador, com busca na web (MCP)" \
      ollama "Ollama"     "Navegador (chat StoaAI)" \
      ollama-term "Ollama" "Terminal (ollama run)" \
      --width 520 --height 260 --button "Cancelar:1" --button "Abrir:0") || exit 0
    [ -n "$pick" ] && exec "$0" "$pick"
    ;;
  *) echo "uso: stoa-models [llama|ollama|ollama-term|stop]" >&2; exit 2 ;;
esac
