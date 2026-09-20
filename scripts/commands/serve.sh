#!/usr/bin/env bash

command_main() {
  local model
  model="$(resolve_model "${1:-}")"
  [[ $# -eq 0 ]] || shift

  require_flm
  exec "$FLM_BIN" serve "$model" \
    --host "${FLM_HOST:-0.0.0.0}" \
    --port "${FLM_SERVE_PORT:-52625}" \
    "$@"
}
