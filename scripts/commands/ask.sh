#!/usr/bin/env bash

command_main() {
  local model="" prompt
  if [[ "${1:-}" == "-m" || "${1:-}" == "--model" ]]; then
    [[ $# -ge 2 ]] || die "Missing model after $1"
    model="$2"; shift 2
  fi
  model="$(resolve_model "$model")"
  prompt="$(read_input "$@")" || die "Prompt required. Example: llm-fastflow ask \"Hello\""
  [[ -n "$prompt" ]] || die "Prompt cannot be empty"
  check_input_budget "Prompt input" "$prompt"
  run_text_prompt "$model" "" "$prompt"
}
