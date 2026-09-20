#!/usr/bin/env bash

attachment_kind() {
  local lower="${1,,}"
  case "$lower" in
    *.png|*.jpg|*.jpeg) printf '%s\n' image ;;
    *.webp|*.gif|*.bmp|*.tif|*.tiff|*.svg) printf '%s\n' unsupported-image ;;
    *.pdf) printf '%s\n' pdf ;;
    *) printf '%s\n' text ;;
  esac
}

validate_image_file() {
  local file="$1"
  [[ -f "$file" && -s "$file" ]] || die "Image file unavailable or empty: $file"
  check_attachment_set "Image attachment" "$file"
  image_mime "$file" >/dev/null || die "FastFlow vision supports PNG/JPEG images: $file"
}

pdf_text_context() {
  (( $# > 0 )) || return 0
  require_command pdftotext
  check_attachment_set "PDF text attachments" "$@"
  local file text first=1
  for file in "$@"; do
    [[ -f "$file" && -s "$file" ]] || die "PDF file unavailable or empty: $file"
    text="$(pdftotext -layout "$file" - 2>/dev/null)" || die "Failed to extract text from PDF: $file"
    [[ -n "$(printf '%s' "$text" | tr -d '[:space:]')" ]] || die "PDF has no extractable text: $file. Use --pdf-vision for scanned/image PDFs."
    (( first )) || printf '\n\n'
    first=0
    printf '%s\n%s\n' "--- PDF: $file ---" "$text"
  done
}

pdf_page_count() {
  require_command pdfinfo
  local file="$1" pages
  pages="$(LC_ALL=C pdfinfo "$file" 2>/dev/null | awk -F: '/^Pages:/ {gsub(/[[:space:]]/,"",$2); print $2; exit}')"
  [[ "$pages" =~ ^[1-9][0-9]*$ ]] || die "Unable to determine PDF page count: $file"
  printf '%s\n' "$pages"
}

check_pdf_vision_pages() {
  (( $# > 0 )) || return 0
  validate_attachment_limits
  local max_pages="${LLM_FASTFLOW_PDF_MAX_PAGES:-$DEFAULT_PDF_MAX_PAGES}" file pages total=0
  for file in "$@"; do pages="$(pdf_page_count "$file")"; total=$((total + pages)); done
  if (( max_pages > 0 && total > max_pages )) && ! large_input_allowed; then
    die "PDF vision input has ${total} pages; page limit is $max_pages."
  fi
}

render_pdf_pages() {
  require_command pdftoppm
  local file="$1" out_dir="$2" index="$3" dpi="${LLM_FASTFLOW_PDF_DPI:-120}" prefix
  [[ "$dpi" =~ ^[1-9][0-9]*$ ]] || die "LLM_FASTFLOW_PDF_DPI must be a positive integer"
  mkdir -p "$out_dir"
  prefix="$out_dir/pdf-${index}"
  pdftoppm -png -r "$dpi" "$file" "$prefix" >/dev/null 2>&1 || die "Failed to render PDF pages: $file"
  find "$out_dir" -maxdepth 1 -type f -name "pdf-${index}-*.png" -print | sort -V
}
