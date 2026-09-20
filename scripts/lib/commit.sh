#!/usr/bin/env bash

ai_commit_prompt_file() {
  printf '%s\n' "${LLM_FASTFLOW_AI_COMMIT_PROMPT_FILE:-$LLM_FASTFLOW_RUNTIME_ROOT/prompts/ai-commit.txt}"
}

load_ai_commit_prompt() {
  local prompt_file
  prompt_file="$(ai_commit_prompt_file)"
  [[ -f "$prompt_file" && -s "$prompt_file" ]] || die "AI commit prompt unavailable: $prompt_file"
  cat -- "$prompt_file"
}
