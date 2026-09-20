#!/usr/bin/env bash

command_main() {
  local model=""
  if [[ $# -gt 0 && "${1:-}" != -* ]]; then
    model="$1"
    shift
  fi
  model="$(resolve_model "$model")"
  exec_flm pull "$model" "$@"
}
