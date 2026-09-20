#!/usr/bin/env bash

command_main() {
  local model
  model="$(resolve_model "${1:-}")"
  [[ $# -eq 0 ]] || shift
  exec_flm run "$model" "$@"
}
