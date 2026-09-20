#!/usr/bin/env bash
set -euo pipefail

image="${1:-infocyph/llm-fastflow:latest}"
model="${LLM_FASTFLOW_MODEL:-qwen3.5:9b}"
device="${LLM_FASTFLOW_NPU_DEVICE:-/dev/accel/accel0}"
name="llm-fastflow-npu-smoke-${RANDOM}"
volume="llm-fastflow-npu-smoke-${RANDOM}"

command -v docker >/dev/null 2>&1 || {
  printf 'docker is required for the NPU smoke test.\n' >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  printf 'jq is required for the NPU smoke test.\n' >&2
  exit 1
}

[[ -c "$device" ]] || {
  printf 'NPU device unavailable: %s\n' "$device" >&2
  exit 1
}

cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker volume rm -f "$volume" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

docker volume create "$volume" >/dev/null

start_container() {
  docker run -d \
    --name "$name" \
    --device "$device:/dev/accel/accel0" \
    --ulimit memlock=-1:-1 \
    --mount "type=volume,src=$volume,dst=/models" \
    -e "LLM_FASTFLOW_MODEL=$model" \
    "$image" >/dev/null
}

wait_healthy() {
  local state health
  for _ in $(seq 1 180); do
    state="$(docker inspect -f '{{.State.Status}}' "$name")"
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$name")"
    [[ "$health" == healthy ]] && return 0

    if [[ "$state" == exited || "$health" == unhealthy ]]; then
      docker logs "$name" >&2 || true
      return 1
    fi
    sleep 5
  done

  docker logs "$name" >&2 || true
  return 1
}

start_container
wait_healthy

docker exec "$name" /opt/fastflowlm/flm validate
docker exec "$name" /opt/fastflowlm/flm check "$model"
docker exec "$name" curl -fsS http://127.0.0.1:52625/v1/models |
  jq -e '.data | length >= 1' >/dev/null

payload="$(jq -nc --arg model "$model" '{
  model: $model,
  messages: [{role:"user",content:"Reply with OK only."}],
  stream: false,
  max_tokens: 16
}')"

docker exec "$name" curl -fsS http://127.0.0.1:52625/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d "$payload" | jq -e '.choices[0].message.content | length > 0' >/dev/null

# Prove the model volume survives container recreation independently of image content.
docker exec "$name" /bin/sh -c 'printf persistence-ok > /models/.llm-fastflow-smoke-persist'

# Docker uses the image STOPSIGNAL (SIGINT) here. The stop must complete without
# falling back to an externally forced container removal.
docker stop -t 30 "$name" >/dev/null
[[ "$(docker inspect -f '{{.State.Running}}' "$name")" == false ]]
docker rm "$name" >/dev/null

start_container
wait_healthy

docker exec "$name" test -f /models/.llm-fastflow-smoke-persist
docker exec "$name" /opt/fastflowlm/flm check "$model"
docker exec "$name" curl -fsS http://127.0.0.1:52625/v1/models |
  jq -e '.data | length >= 1' >/dev/null

docker stop -t 30 "$name" >/dev/null
[[ "$(docker inspect -f '{{.State.Running}}' "$name")" == false ]]

printf 'PASS: XDNA2 NPU inference, persistence and restart (%s)\n' "$model"
