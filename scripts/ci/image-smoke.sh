#!/usr/bin/env bash
set -euo pipefail

image="${1:?usage: image-smoke.sh <image>}"
expected_flm="${FASTFLOWLM_VERSION:-1.0.6}"
expected_wrapper="${LLM_FASTFLOW_VERSION:-dev}"
expected_model="${FASTFLOW_MODEL:-qwen3.5:9b}"
expect_baked_model="${FASTFLOW_EXPECT_BAKED_MODEL:-1}"

flm_output="$(docker run --rm --entrypoint /opt/fastflowlm/flm "$image" version)"
IFS= read -r flm_version <<<"$flm_output"
grep -Fq "FLM v${expected_flm}" <<<"$flm_version"

wrapper_output="$(docker run --rm --entrypoint llm-fastflow "$image" version)"
IFS= read -r wrapper_version <<<"$wrapper_output"
[[ "$wrapper_version" == "llm-fastflow ${expected_wrapper}" ]]

if [[ "$expect_baked_model" == "1" ]]; then
  docker run --rm --entrypoint /opt/fastflowlm/flm "$image" check "$expected_model" >/dev/null
fi

# shellcheck disable=SC2016
image_model="$(docker run --rm --entrypoint /bin/sh "$image" -c 'printf %s "$LLM_FASTFLOW_MODEL"')"
[[ "$image_model" == "$expected_model" ]]

# shellcheck disable=SC2016
docker run --rm --entrypoint /bin/sh "$image" -c '
  test -x /opt/fastflowlm/flm
  test -x /opt/fastflowlm/flm-real
  test -f /opt/fastflowlm/model_list.json
  test -f /opt/fastflowlm/model_info.json
  test -d /opt/fastflowlm/lib
  test -d /opt/fastflowlm/xclbins
  test "$FLM_MODEL_PATH" = /models
  test "$FLM_SERVE_PORT" = 52625
  test "$FLM_HOST" = 0.0.0.0
  test "$FLM_CORS" = 0
  test "$FLM_DISABLE_UPDATE_CHECK" = 1
  command -v git >/dev/null
  command -v pdftotext >/dev/null
  command -v pdftoppm >/dev/null
  test -f /usr/local/lib/llm-fastflow/prompts/ai-commit.txt
  llm-fastflow help | grep -q "ai-commit"
  llm-fastflow help | grep -q "prompt"
'

printf 'PASS: image smoke (%s)\n' "$image"
