#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$LLM_FASTFLOW_RUNTIME_ROOT/lib/attachments.sh"

command_main() {
  local model="" system input stdin_data file_data pdf_data attachment_tmp rendered kind image
  local -a files=() images=() pdfs=() pdf_vision=() rendered_pages=()
  system="${LLM_FASTFLOW_SYSTEM:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--model) [[ $# -ge 2 ]] || die "Missing model after $1"; model="$2"; shift 2 ;;
      -s|--system) [[ $# -ge 2 ]] || die "Missing system prompt after $1"; system="$2"; shift 2 ;;
      -f|--file) [[ $# -ge 2 ]] || die "Missing file after $1"; files+=("$2"); shift 2 ;;
      --image) [[ $# -ge 2 ]] || die "Missing image after $1"; images+=("$2"); shift 2 ;;
      --pdf) [[ $# -ge 2 ]] || die "Missing PDF after $1"; pdfs+=("$2"); shift 2 ;;
      --pdf-vision) [[ $# -ge 2 ]] || die "Missing PDF after $1"; pdf_vision+=("$2"); shift 2 ;;
      --attach)
        [[ $# -ge 2 ]] || die "Missing attachment after $1"
        kind="$(attachment_kind "$2")"
        case "$kind" in
          image) images+=("$2") ;;
          unsupported-image) die "Unsupported FastFlow image format for --attach: $2. Use PNG/JPEG." ;;
          pdf) pdfs+=("$2") ;;
          text) files+=("$2") ;;
        esac
        shift 2 ;;
      --) shift; break ;;
      -*) die "Unknown option: $1" ;;
      *) break ;;
    esac
  done

  model="$(resolve_model "$model")"
  local -a source_attachments=("${files[@]}" "${images[@]}" "${pdfs[@]}" "${pdf_vision[@]}")
  check_attachment_set "Prompt attachments" "${source_attachments[@]}"
  check_pdf_vision_pages "${pdf_vision[@]}"
  input="${*:-}"
  stdin_data="$(read_stdin_if_piped)"
  file_data="$(file_context "${files[@]}")"
  pdf_data="$(pdf_text_context "${pdfs[@]}")"
  [[ -z "$stdin_data" ]] || input+="${input:+$'\n\n'}--- STDIN ---"$'\n'"$stdin_data"
  [[ -z "$file_data" ]] || input+="${input:+$'\n\n'}$file_data"
  [[ -z "$pdf_data" ]] || input+="${input:+$'\n\n'}$pdf_data"

  for image in "${images[@]}"; do validate_image_file "$image"; done

  if (( ${#pdf_vision[@]} > 0 )); then
    attachment_tmp="$(mktemp -d)"
    trap 'rm -rf -- "${attachment_tmp:-}"' RETURN
    local index=0 pdf
    for pdf in "${pdf_vision[@]}"; do
      index=$((index + 1))
      rendered="$(render_pdf_pages "$pdf" "$attachment_tmp" "$index")"
      [[ -n "$rendered" ]] || die "PDF rendered no image pages: $pdf"
      mapfile -t rendered_pages <<<"$rendered"
      images+=("${rendered_pages[@]}")
      rendered_pages=()
    done
  fi

  if [[ -z "$input" && ${#images[@]} -gt 0 ]]; then
    input="Analyze the attached image content and answer concisely."
  fi
  [[ -n "$input" ]] || die "Prompt, piped input, --file, --pdf, --image, --pdf-vision, or --attach is required"
  check_input_budget "Prompt input" "$input"
  run_chat_prompt "$model" "$system" "$input" "${images[@]}"
  [[ -z "${attachment_tmp:-}" ]] || rm -rf -- "$attachment_tmp"
}
