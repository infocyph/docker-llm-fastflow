#!/usr/bin/env bash

command_main() {
  local model=""
  if [[ $# -gt 0 && "${1:-}" != -* ]]; then
    model="$1"
    shift
  fi
  model="$(resolve_model "$model")

  require_flm
  exec "$FLM_BIN" serve "$model" \
    --host "${FLM_HOST:-0.0.0.0}" \
    --port "${FLM_SERVE_PORT:-52625}" \
    "$@"
}
