#!/usr/bin/env bash

command_main() {
  local model="" schema_file="" response_only=0 prompt instruction response schema=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--model) [[ $# -ge 2 ]] || die "Missing model after $1"; model="$2"; shift 2 ;;
      --schema) [[ $# -ge 2 ]] || die "Missing schema file after $1"; schema_file="$2"; shift 2 ;;
      -r|--response-only) response_only=1; shift ;;
      --) shift; break ;;
      -*) die "Unknown option: $1" ;;
      *) break ;;
    esac
  done
  require_command jq
  model="$(resolve_model "$model")"
  prompt="$(read_input "$@")" || die "Prompt required. Example: llm-fastflow json \"Return name and version\""
  [[ -n "$prompt" ]] || die "Prompt cannot be empty"
  check_input_budget "JSON prompt" "$prompt"

  instruction="Return exactly one valid JSON value and no markdown or commentary."
  if [[ -n "$schema_file" ]]; then
    [[ -f "$schema_file" && -s "$schema_file" ]] || die "Schema file unavailable or empty: $schema_file"
    schema="$(jq -ce . "$schema_file" 2>/dev/null)" || die "Schema file is not valid JSON: $schema_file"
    instruction+=$'\nThe response must conform to this JSON Schema:\n'"$schema"
  fi

  response="$(LLM_FASTFLOW_THINK=false run_text_prompt "$model" "$instruction" "$prompt")"
  if ! jq -e . >/dev/null 2>&1 <<<"$response"; then
    die "FastFlowLM JSON command returned invalid JSON"
  fi
  if (( response_only )); then
    jq . <<<"$response"
  else
    jq -n --arg model "$model" --argjson response "$response" '{model:$model,response:$response}'
  fi
}
