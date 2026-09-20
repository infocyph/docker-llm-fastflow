#!/usr/bin/env bash

command_main() {
  local model="" focus stdin_data file_data context instruction item
  local -a files=() remaining=() focus_parts=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--model) [[ $# -ge 2 ]] || die "Missing model after $1"; model="$2"; shift 2 ;;
      -f|--file) [[ $# -ge 2 ]] || die "Missing file after $1"; files+=("$2"); shift 2 ;;
      --) shift; remaining+=("$@"); break ;;
      -*) die "Unknown option: $1" ;;
      *) remaining+=("$1"); shift ;;
    esac
  done
  model="$(resolve_model "$model")"
  for item in "${remaining[@]}"; do
    if [[ -f "$item" ]]; then files+=("$item"); else focus_parts+=("$item"); fi
  done
  focus="${focus_parts[*]:-}"
  stdin_data="$(read_stdin_if_piped)"
  file_data="$(file_context "${files[@]}")"
  context=""
  [[ -n "$stdin_data" ]] && context="--- STDIN ---"$'\n'"$stdin_data"
  [[ -z "$file_data" ]] || context+="${context:+$'\n\n'}$file_data"
  [[ -n "$context" ]] || die "Provide a file, --file, or piped code to review"
  instruction="Review the supplied code as a senior engineer. Prioritize correctness, security, performance, concurrency, resource handling, edge cases, API/compatibility risks, and production failure modes. Report concrete findings ordered by severity. Include the affected file or area and a practical fix. Avoid style-only noise unless it materially affects maintainability. If there are no meaningful issues, say so clearly."
  [[ -z "$focus" ]] || context="Review focus: $focus"$'\n\n'"$context"
  check_input_budget "Review input" "$context"
  run_text_prompt "$model" "$instruction" "$context"
}
