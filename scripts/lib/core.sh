#!/usr/bin/env bash

# Shared by dynamically loaded command modules.
# shellcheck disable=SC2034
VERSION="${LLM_FASTFLOW_VERSION:-dev}"
DEFAULT_MODEL="qwen3.5:9b"
FLM_BIN="${FLM_BIN:-/opt/fastflowlm/flm}"
API_URL="${LLM_FASTFLOW_URL:-http://127.0.0.1:${FLM_SERVE_PORT:-52625}}"
DEFAULT_INPUT_WARN_BYTES=1048576
DEFAULT_INPUT_MAX_BYTES=0
DEFAULT_ATTACHMENT_MAX_BYTES=16777216
DEFAULT_ATTACHMENTS_MAX_BYTES=33554432
DEFAULT_ATTACHMENT_MAX_COUNT=16
DEFAULT_PDF_MAX_PAGES=24

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  RED=$'\033[31m'
  RESET=$'\033[0m'
else
  BOLD='' GREEN='' YELLOW='' RED='' RESET=''
fi

info() { printf '%s\n' "${GREEN}$*${RESET}"; }
warn() { printf '%s\n' "${YELLOW}$*${RESET}" >&2; }
die() { printf '%s\n' "${RED}Error:${RESET} $*" >&2; exit 1; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
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

validate_input_limits() {
  local warn_bytes="${LLM_FASTFLOW_INPUT_WARN_BYTES:-$DEFAULT_INPUT_WARN_BYTES}"
  local max_bytes="${LLM_FASTFLOW_INPUT_MAX_BYTES:-$DEFAULT_INPUT_MAX_BYTES}"
  [[ "$warn_bytes" =~ ^[0-9]+$ ]] || die "LLM_FASTFLOW_INPUT_WARN_BYTES must be a non-negative integer"
  [[ "$max_bytes" =~ ^[0-9]+$ ]] || die "LLM_FASTFLOW_INPUT_MAX_BYTES must be a non-negative integer"
  if (( max_bytes > 0 && warn_bytes > max_bytes )); then
    die "LLM_FASTFLOW_INPUT_WARN_BYTES cannot exceed a non-zero LLM_FASTFLOW_INPUT_MAX_BYTES"
  fi
}

check_input_bytes() {
  local label="$1" bytes="$2"
  local warn_bytes="${LLM_FASTFLOW_INPUT_WARN_BYTES:-$DEFAULT_INPUT_WARN_BYTES}"
  local max_bytes="${LLM_FASTFLOW_INPUT_MAX_BYTES:-$DEFAULT_INPUT_MAX_BYTES}"
  validate_input_limits
  [[ "$bytes" =~ ^[0-9]+$ ]] || die "Invalid byte count for $label"
  if (( max_bytes > 0 && bytes > max_bytes )) && [[ "${LLM_FASTFLOW_ALLOW_LARGE_INPUT:-0}" != 1 ]]; then
    die "$label is ${bytes} bytes; configured limit is ${max_bytes}. Raise LLM_FASTFLOW_INPUT_MAX_BYTES, set it to 0, or deliberately set LLM_FASTFLOW_ALLOW_LARGE_INPUT=1."
  fi
  if (( warn_bytes > 0 && bytes > warn_bytes )); then
    warn "$label is ${bytes} bytes; the selected model may be slow or lose useful context."
  fi
}

check_input_budget() {
  local label="$1" input="$2" bytes
  bytes="$(LC_ALL=C printf '%s' "$input" | wc -c | tr -d '[:space:]')"
  check_input_bytes "$label" "$bytes"
}

check_file_budget() {
  local label="$1" file="$2" bytes
  [[ -f "$file" ]] || die "File not found: $file"
  bytes="$(LC_ALL=C wc -c < "$file" | tr -d '[:space:]')"
  check_input_bytes "$label" "$bytes"
}

large_input_allowed() {
  [[ "${LLM_FASTFLOW_ALLOW_LARGE_INPUT:-0}" == 1 ]]
}

validate_attachment_limits() {
  local max_bytes="${LLM_FASTFLOW_ATTACHMENT_MAX_BYTES:-$DEFAULT_ATTACHMENT_MAX_BYTES}"
  local total_max_bytes="${LLM_FASTFLOW_ATTACHMENTS_MAX_BYTES:-$DEFAULT_ATTACHMENTS_MAX_BYTES}"
  local max_count="${LLM_FASTFLOW_ATTACHMENT_MAX_COUNT:-$DEFAULT_ATTACHMENT_MAX_COUNT}"
  local max_pages="${LLM_FASTFLOW_PDF_MAX_PAGES:-$DEFAULT_PDF_MAX_PAGES}"
  [[ "$max_bytes" =~ ^[0-9]+$ ]] || die "LLM_FASTFLOW_ATTACHMENT_MAX_BYTES must be a non-negative integer"
  [[ "$total_max_bytes" =~ ^[0-9]+$ ]] || die "LLM_FASTFLOW_ATTACHMENTS_MAX_BYTES must be a non-negative integer"
  [[ "$max_count" =~ ^[0-9]+$ ]] || die "LLM_FASTFLOW_ATTACHMENT_MAX_COUNT must be a non-negative integer"
  [[ "$max_pages" =~ ^[0-9]+$ ]] || die "LLM_FASTFLOW_PDF_MAX_PAGES must be a non-negative integer"
}

check_attachment_bytes_set() {
  local label="$1"; shift
  (( $# > 0 )) || return 0
  validate_attachment_limits
  local max_bytes="${LLM_FASTFLOW_ATTACHMENT_MAX_BYTES:-$DEFAULT_ATTACHMENT_MAX_BYTES}"
  local total_max_bytes="${LLM_FASTFLOW_ATTACHMENTS_MAX_BYTES:-$DEFAULT_ATTACHMENTS_MAX_BYTES}"
  local file bytes total_bytes=0
  for file in "$@"; do
    [[ -f "$file" ]] || die "Attachment file not found: $file"
    bytes="$(LC_ALL=C wc -c < "$file" | tr -d '[:space:]')"
    if (( max_bytes > 0 && bytes > max_bytes )) && ! large_input_allowed; then
      die "$label file '$file' is ${bytes} bytes; per-file limit is ${max_bytes}."
    fi
    total_bytes=$((total_bytes + bytes))
  done
  if (( total_max_bytes > 0 && total_bytes > total_max_bytes )) && ! large_input_allowed; then
    die "$label totals ${total_bytes} bytes; aggregate limit is ${total_max_bytes}."
  fi
}

check_attachment_set() {
  local label="$1"; shift
  (( $# > 0 )) || return 0
  validate_attachment_limits
  local max_count="${LLM_FASTFLOW_ATTACHMENT_MAX_COUNT:-$DEFAULT_ATTACHMENT_MAX_COUNT}"
  if (( max_count > 0 && $# > max_count )) && ! large_input_allowed; then
    die "$label has $# files; attachment-count limit is $max_count."
  fi
  check_attachment_bytes_set "$label" "$@"
}

read_input() {
  if [[ $# -gt 0 ]]; then
    printf '%s\n' "$*"
  elif [[ ! -t 0 ]]; then
    cat
  else
    return 1
  fi
}

read_stdin_if_piped() {
  [[ -t 0 ]] || cat
}

file_context() {
  local file first=1
  check_attachment_set "File context" "$@"
  for file in "$@"; do
    [[ -f "$file" ]] || die "File not found: $file"
    (( first )) || printf '\n\n'
    first=0
    printf '%s\n' "--- FILE: $file ---"
    cat -- "$file"
  done
}

args_have_option() {
  local short="${1:-}" long="${2:-}"
  shift 2 || true
  local arg
  for arg in "$@"; do
    [[ -n "$short" && "$arg" == "$short" ]] && return 0
    [[ -n "$long" && ( "$arg" == "$long" || "$arg" == "$long="* ) ]] && return 0
  done
  return 1
}

exec_flm() {
  require_flm
  exec "$FLM_BIN" "$@"
}
