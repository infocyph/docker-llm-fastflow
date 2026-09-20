#!/usr/bin/env bash

VERSION="${LLM_FASTFLOW_VERSION:-dev}"
DEFAULT_MODEL="qwen3.5:9b"
FLM_BIN="${FLM_BIN:-/opt/fastflowlm/flm}"

die() {
  printf 'llm-fastflow: %s\n' "$*" >&2
  exit 1
}

require_flm() {
  [[ -x "$FLM_BIN" ]] || die "FastFlowLM binary not found: $FLM_BIN"
}

resolve_model() {
  local explicit="${1:-}"
  if [[ -n "$explicit" ]]; then
    printf '%s' "$explicit"
  elif [[ -n "${LLM_FASTFLOW_MODEL:-}" ]]; then
    printf '%s' "$LLM_FASTFLOW_MODEL"
  else
    printf '%s' "$DEFAULT_MODEL"
  fi
}

exec_flm() {
  require_flm
  exec "$FLM_BIN" "$@"
}
