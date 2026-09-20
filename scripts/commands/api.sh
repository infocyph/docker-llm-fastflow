#!/usr/bin/env bash

command_main() {
  require_command curl
  local path="${1:-}"
  [[ -n "$path" ]] || die "API path required. Example: llm-fastflow api /v1/models"
  shift
  curl --fail-with-body -sS "$@" "$(api_url "$path")"
  printf '\n'
}
