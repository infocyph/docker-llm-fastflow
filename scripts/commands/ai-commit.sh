#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$LLM_FASTFLOW_RUNTIME_ROOT/lib/commit.sh"

print_ai_commit_help() {
  cat <<'EOF'
Usage: llm-fastflow ai-commit [options]

Generate a Conventional Commit + Gitmoji message from the staged diff.

Options:
  -m, --model <model>   Override the FastFlow model
  -y, --yes             Commit immediately
  -e, --edit            Edit the generated message, then commit
  -p, --print           Print only; do not commit
      --diff-stdin      Read the diff from stdin and print
  -h, --help            Show this help
EOF
}

git_cmd() { git -c safe.directory='*' "$@"; }

commit_with_message_file() {
  local commit_msg="$1" edit="${2:-0}" msg_file="$AI_COMMIT_TMP/commit-message.txt"
  printf '%s\n' "$commit_msg" >"$msg_file"
  if (( edit )); then
    local editor_value="${EDITOR:-vi}"
    local -a editor_cmd=()
    read -r -a editor_cmd <<<"$editor_value"
    [[ ${#editor_cmd[@]} -gt 0 ]] || editor_cmd=(vi)
    "${editor_cmd[@]}" "$msg_file"
  fi
  [[ -s "$msg_file" ]] || die "Commit message is empty"
  git_cmd commit -F "$msg_file"
  info "Committed successfully."
}

command_main() {
  local model="" action="interactive" diff_stdin=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--model) [[ $# -ge 2 ]] || die "Missing model after $1"; model="$2"; shift 2 ;;
      -y|--yes) action=yes; shift ;;
      -e|--edit) action=edit; shift ;;
      -p|--print) action=print; shift ;;
      --diff-stdin) diff_stdin=1; action=print; shift ;;
      -h|--help) print_ai_commit_help; return 0 ;;
      *) die "Unknown ai-commit option: $1" ;;
    esac
  done

  model="$(resolve_model "$model")"
  AI_COMMIT_TMP="$(mktemp -d)"
  export AI_COMMIT_TMP
  trap 'rm -rf -- "${AI_COMMIT_TMP:-}"' EXIT
  local diff_file="$AI_COMMIT_TMP/staged.diff" prompt commit_msg

  if (( diff_stdin )); then
    [[ ! -t 0 ]] || die "--diff-stdin requires a diff on stdin"
    cat >"$diff_file"
  else
    require_command git
    git_cmd rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not inside a Git repository"
    git_cmd diff --cached --quiet && die "No staged changes found. Stage changes first."
    git_cmd diff --cached >"$diff_file"
  fi
  [[ -s "$diff_file" ]] || die "No diff content found"
  check_file_budget "Git diff" "$diff_file"
  warn "Analyzing changes with $model..."
  prompt="$(load_ai_commit_prompt)"
  commit_msg="$(run_text_prompt "$model" "$prompt" "Analyze the following git diff and generate a commit message:"$'\n\n'"$(cat "$diff_file")")"
  [[ -n "$commit_msg" ]] || die "Generated commit message is empty"

  if [[ "$action" == print ]]; then printf '%s\n' "$commit_msg"; return 0; fi
  printf '\n%s================ Generated Commit Message ================%s\n\n%s\n\n' "$YELLOW" "$RESET" "$commit_msg"
  case "$action" in
    yes) commit_with_message_file "$commit_msg" 0 ;;
    edit) commit_with_message_file "$commit_msg" 1 ;;
    interactive)
      local choice=""
      read -r -p "Commit with this message? (y/e/n): " choice || choice=n
      case "$choice" in
        y|Y) commit_with_message_file "$commit_msg" 0 ;;
        e|E) commit_with_message_file "$commit_msg" 1 ;;
        *) printf '%s\n' "Commit cancelled. Changes remain staged." ;;
      esac ;;
  esac
}
