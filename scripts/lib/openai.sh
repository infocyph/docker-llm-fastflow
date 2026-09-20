#!/usr/bin/env bash

api_url() {
  local path="${1:-/}"
  case "$path" in
    http://*|https://*) printf '%s\n' "$path" ;;
    /*) printf '%s%s\n' "${API_URL%/}" "$path" ;;
    *) printf '%s/%s\n' "${API_URL%/}" "$path" ;;
  esac
}

models_json() {
  require_command curl
  curl --connect-timeout 3 --fail-with-body -sS "$(api_url /v1/models)"
}

model_available() {
  local model="$1" response
  response="$(models_json 2>/dev/null)" || return 1
  jq -e --arg model "$model" '[.data[]?.id] | index($model) != null' <<<"$response" >/dev/null 2>&1
}

require_model() {
  local model="$1"
  require_command jq
  model_available "$model" || die "Model '$model' is not available from FastFlowLM. Run 'llm-fastflow pull $model' and ensure the server is running."
}

image_mime() {
  local lower="${1,,}"
  case "$lower" in
    *.png) printf '%s' image/png ;;
    *.jpg|*.jpeg) printf '%s' image/jpeg ;;
    *) return 1 ;;
  esac
}

encode_images_json() {
  require_command jq
  require_command base64
  local output_file="$1"; shift
  local tmp image mime
  tmp="$(mktemp)"
  : >"$tmp"
  check_attachment_bytes_set "Vision payload" "$@"
  for image in "$@"; do
    [[ -f "$image" && -s "$image" ]] || { rm -f "$tmp"; die "Image file unavailable or empty: $image"; }
    mime="$(image_mime "$image")" || { rm -f "$tmp"; die "FastFlow vision supports PNG/JPEG image input: $image"; }
    {
      printf 'data:%s;base64,' "$mime"
      base64 "$image" | tr -d '\r\n'
      printf '\n'
    } >>"$tmp"
  done
  jq -Rsc 'split("\n") | map(select(length > 0))' "$tmp" >"$output_file"
  rm -f "$tmp"
}

normalize_think_mode() {
  case "${1:-}" in
    "") printf '%s' "" ;;
    1|true|TRUE|yes|YES|on|ON) printf '%s' true ;;
    0|false|FALSE|no|NO|off|OFF) printf '%s' false ;;
    *) die "LLM_FASTFLOW_THINK must be true/false when set" ;;
  esac
}

build_chat_payload() {
  require_command jq
  local model="$1" system_file="$2" content_file="$3" images_file="$4" output_file="$5"
  local think
  think="$(normalize_think_mode "${LLM_FASTFLOW_THINK:-}")"
  jq -n     --arg model "$model"     --rawfile system "$system_file"     --rawfile content "$content_file"     --slurpfile images "$images_file"     --arg think "$think"     '{
      model: $model,
      messages:
        ((if ($system | length) > 0 then [{role:"system",content:$system}] else [] end)
        + [{
            role:"user",
            content:
              (if (($images[0] // []) | length) > 0
               then ([{type:"text",text:$content}]
                     + (($images[0] // []) | map({type:"image_url",image_url:{url:.}})))
               else $content
               end)
          }]),
      stream:false
    }
    | if $think == "" then .
      else . + {think: ($think == "true")}
      end' >"$output_file"
}

run_chat_prompt() {
  local model="$1" instruction="$2" content="$3"; shift 3
  local -a images=("$@")
  local tmp_dir system_file content_file images_file payload_file response_file response
  require_model "$model"
  require_command curl
  require_command jq

  tmp_dir="$(mktemp -d)"
  system_file="$tmp_dir/system.txt"
  content_file="$tmp_dir/content.txt"
  images_file="$tmp_dir/images.json"
  payload_file="$tmp_dir/request.json"
  response_file="$tmp_dir/response.json"
  printf '%s' "$instruction" >"$system_file"
  printf '%s' "$content" >"$content_file"
  encode_images_json "$images_file" "${images[@]}"
  build_chat_payload "$model" "$system_file" "$content_file" "$images_file" "$payload_file"

  if ! curl --connect-timeout 3 --fail-with-body -sS       -H 'Content-Type: application/json'       --data-binary @"$payload_file"       "$(api_url /v1/chat/completions)" >"$response_file"; then
    [[ ! -s "$response_file" ]] || cat "$response_file" >&2
    die "FastFlowLM failed to process the request"
  fi

  response="$(jq -er '.choices[0].message.content // empty' "$response_file")" || {
    cat "$response_file" >&2
    rm -rf -- "$tmp_dir"
    die "FastFlowLM response did not contain message content"
  }
  rm -rf -- "$tmp_dir"
  printf '%s\n' "$response"
}

run_text_prompt() {
  run_chat_prompt "$1" "$2" "$3"
}
