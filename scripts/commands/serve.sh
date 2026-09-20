#!/usr/bin/env bash

command_main() {
  local model=""
  if [[ $# -gt 0 && "${1:-}" != -* ]]; then
    model="$1"
    shift
  fi
  model="$(resolve_model "$model")"

  local -a native=("$@")
  local -a args=(serve "$model")

  args_have_option "" --host "${native[@]}" ||
    args+=(--host "${FLM_HOST:-0.0.0.0}")
  args_have_option -p --port "${native[@]}" ||
    args+=(--port "${FLM_SERVE_PORT:-52625}")
  args_have_option "" --cors "${native[@]}" ||
    args+=(--cors "${FLM_CORS:-0}")

  require_flm
  exec "$FLM_BIN" "${args[@]}" "${native[@]}"
}
