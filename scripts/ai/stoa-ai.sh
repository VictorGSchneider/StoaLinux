#!/bin/bash
# stoa-ai: escolhe como conversar com os modelos locais.
#   stoa-ai          janela para escolher entre llama (navegador) e Ollama (terminal)
#   stoa-ai llama    sobe o llama serve + MCP e abre o chat StoaAI no navegador
#   stoa-ai ollama   escolhe um modelo do Ollama e abre `ollama run` no kitty
#   stoa-ai stop     para o llama serve + MCP e descarrega os modelos do Ollama
note() { notify-send "StoaAI" "$1" 2>/dev/null || echo "StoaAI: $1" >&2; }

ollama_chat() {
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
  llama)  exec stoa-models open ;;
  ollama) ollama_chat ;;
  stop)
    stoa-models stop
    command -v ollama >/dev/null && ollama ps 2>/dev/null | awk 'NR>1 {print $1}' | xargs -r -n1 ollama stop
    ;;
  choose)
    pick=$(yad --list --title "StoaAI" --text "Como você quer conversar?" \
      --column "id:HD" --column "Motor" --column "Como abre" --print-column 1 --separator '' \
      llama  "llama.cpp"  "Navegador, com busca na web (MCP)" \
      ollama "Ollama"     "Terminal (ollama run)" \
      --width 520 --height 230 --button "Cancelar:1" --button "Abrir:0") || exit 0
    [ -n "$pick" ] && exec "$0" "$pick"
    ;;
  *) echo "uso: stoa-ai [llama|ollama|stop]" >&2; exit 2 ;;
esac
