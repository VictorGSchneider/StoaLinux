#!/bin/bash
# stoa-models: sobe o llama serve (modo router) com os modelos de ~/Models/llm.
# Uso: stoa-models [porta]   (padrão 9931)  | extras: stoa-models 9931 --models-max 2
PORT="${1:-9931}"; [ $# -gt 0 ] && shift
echo "stoa-models -> http://localhost:$PORT"
exec "$HOME/.local/bin/llama" serve \
  --models-dir "$HOME/Models/llm" \
  --models-preset "$HOME/.config/llama/presets.ini" \
  --models-max 1 --host 127.0.0.1 --port "$PORT" "$@"
