#!/usr/bin/env bash
set -euo pipefail

image="${1:-infocyph/llm-fastflow:latest}"
model="${LLM_FASTFLOW_MODEL:-qwen3.5:9b}"
device="${LLM_FASTFLOW_NPU_DEVICE:-/dev/accel/accel0}"
name="llm-fastflow-npu-smoke-${RANDOM}"

[[ -c "$device" ]] || {
  printf 'NPU device unavailable: %s\n' "$device" >&2
  exit 1
}

cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

docker run -d \
  --name "$name" \
  --device "$device:/dev/accel/accel0" \
  --ulimit memlock=-1:-1 \
  -e "LLM_FASTFLOW_MODEL=$model" \
  "$image" >/dev/null

for _ in $(seq 1 180); do
  state="$(docker inspect -f '{{.State.Status}}' "$name")"
  health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$name")"
  [[ "$health" == healthy ]] && break
  if [[ "$state" == exited || "$health" == unhealthy ]]; then
    docker logs "$name" >&2 || true
    exit 1
  fi
  sleep 5
done

[[ "$(docker inspect -f '{{.State.Health.Status}}' "$name")" == healthy ]]
docker exec "$name" /opt/fastflowlm/flm validate
docker exec "$name" curl -fsS http://127.0.0.1:52625/v1/models | jq -e '.data | length >= 1' >/dev/null

payload="$(jq -nc --arg model "$model" '{
  model: $model,
  messages: [{role:"user",content:"Reply with OK only."}],
  stream: false,
  max_tokens: 16
}')"

docker exec "$name" curl -fsS http://127.0.0.1:52625/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d "$payload" | jq -e '.choices[0].message.content | length > 0' >/dev/null

printf 'PASS: XDNA2 NPU inference (%s)\n' "$model"
