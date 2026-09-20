#!/usr/bin/env bash
set -euo pipefail

image="${1:?usage: image-smoke.sh <image>}"
expected_flm="${FASTFLOWLM_VERSION:-1.0.6}"
expected_wrapper="${LLM_FASTFLOW_VERSION:-dev}"

flm_output="$(docker run --rm --entrypoint /opt/fastflowlm/flm "$image" version)"
IFS= read -r flm_version <<<"$flm_output"
grep -Fq "FLM v${expected_flm}" <<<"$flm_version"

wrapper_output="$(docker run --rm --entrypoint llm-fastflow "$image" version)"
IFS= read -r wrapper_version <<<"$wrapper_output"
[[ "$wrapper_version" == "llm-fastflow ${expected_wrapper}" ]]

# shellcheck disable=SC2016
docker run --rm --entrypoint /bin/sh "$image" -c '
  test -x /opt/fastflowlm/flm
  test -x /opt/fastflowlm/flm-real
  test -f /opt/fastflowlm/model_list.json
  test -f /opt/fastflowlm/model_info.json
  test -d /opt/fastflowlm/lib
  test -d /opt/fastflowlm/xclbins
  test "$FLM_MODEL_PATH" = /models
  test "$LLM_FASTFLOW_MODEL" = qwen3.5:9b
  test "$FLM_SERVE_PORT" = 52625
  test "$FLM_DISABLE_UPDATE_CHECK" = 1
'

printf 'PASS: image smoke (%s)\n' "$image"
