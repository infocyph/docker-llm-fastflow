#!/usr/bin/env bash

command_main() {
  local model="" task stdin_data file_data context instruction
  local -a files=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--model) [[ $# -ge 2 ]] || die "Missing model after $1"; model="$2"; shift 2 ;;
      -f|--file) [[ $# -ge 2 ]] || die "Missing file after $1"; files+=("$2"); shift 2 ;;
      --) shift; break ;;
      -*) die "Unknown option: $1" ;;
      *) break ;;
    esac
  done
  model="$(resolve_model "$model")"
  task="${*:-}"
  stdin_data="$(read_stdin_if_piped)"
  file_data="$(file_context "${files[@]}")"
  context=""
  [[ -n "$stdin_data" ]] && context="--- STDIN ---"$'\n'"$stdin_data"
  [[ -z "$file_data" ]] || context+="${context:+$'\n\n'}$file_data"
  if [[ -z "$task" ]]; then
    [[ -n "$context" ]] || die "Coding task, piped input, or --file is required"
    task="Improve or implement the provided code. Preserve intended behavior unless a change is necessary."
  fi
  instruction="You are a senior software engineer. Produce the smallest correct production-ready solution. Prioritize correctness, performance, security, maintainability, and clear failure handling. Preserve the language and project conventions visible in the input. Return code first when code is requested; keep explanation concise. Do not invent unavailable project context."
  [[ -z "$context" ]] || task+=$'\n\nContext:\n'"$context"
  check_input_budget "Code input" "$task"
  run_text_prompt "$model" "$instruction" "$task"
}
