#!/usr/bin/env bash
set -euo pipefail

FLM_BIN="${FLM_BIN:-/opt/fastflowlm/flm}"

die() {
  printf 'llm-fastflow: %s\n' "$*" >&2
  exit 1
}

is_positive_integer() {
  [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

has_option() {
  local short="${1:-}" long="${2:-}"
  shift 2 || true
  local arg
  for arg in "$@"; do
    [[ "$arg" == "$short" || "$arg" == "$long" || "$arg" == "$long="* ]] && return 0
  done
  return 1
}

start_server() {
  local model="${LLM_FASTFLOW_MODEL:-qwen3.5:9b}"
  local port="${FLM_SERVE_PORT:-52625}"
  local queue="${LLM_FASTFLOW_QUEUE_LENGTH:-10}"
  local sockets="${LLM_FASTFLOW_SOCKET_CONNECTIONS:-10}"
  local context="${LLM_FASTFLOW_CONTEXT_LENGTH:-}"
  local -a extra=("$@")
  local -a args=(serve)

  if (("${#extra[@]}" > 0)) && [[ "${extra[0]}" != -* ]]; then
    model="${extra[0]}"
    extra=("${extra[@]:1}")
  fi

  [[ -n "$model" ]] || die "LLM_FASTFLOW_MODEL must not be empty"
  is_positive_integer "$port" || die "FLM_SERVE_PORT must be a positive integer"
  is_positive_integer "$queue" || die "LLM_FASTFLOW_QUEUE_LENGTH must be a positive integer"
  is_positive_integer "$sockets" || die "LLM_FASTFLOW_SOCKET_CONNECTIONS must be a positive integer"
  [[ -z "$context" ]] || is_positive_integer "$context" ||
    die "LLM_FASTFLOW_CONTEXT_LENGTH must be empty or a positive integer"

  args+=("$model")

  has_option "" --host "${extra[@]}" || args+=(--host 0.0.0.0)
  has_option -p --port "${extra[@]}" || args+=(--port "$port")
  has_option "" --cors "${extra[@]}" || args+=(--cors 0)
  has_option -q --q-len "${extra[@]}" || args+=(--q-len "$queue")
  has_option -s --socket "${extra[@]}" || args+=(--socket "$sockets")

  if [[ -n "$context" ]] && ! has_option "" --ctx-len "${extra[@]}"; then
    args+=(--ctx-len "$context")
  fi

  exec "$FLM_BIN" "${args[@]}" "${extra[@]}"
}

[[ -x "$FLM_BIN" ]] || die "FastFlowLM runtime not found at $FLM_BIN"

if (($# == 0)); then
  start_server
fi

case "$1" in
  serve)
    shift
    start_server "$@"
    ;;
  llm-fastflow)
    shift
    exec /usr/local/bin/llm-fastflow "$@"
    ;;
  flm)
    shift
    exec "$FLM_BIN" "$@"
    ;;
  *)
    exec "$FLM_BIN" "$@"
    ;;
esac
