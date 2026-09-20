#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$*"
}

bash -n scripts/llm-fastflow scripts/lib/*.sh scripts/commands/*.sh scripts/ci/*.sh tests/*.sh
pass "Bash syntax"

test "$(env -u LLM_FASTFLOW_MODEL bash -c 'source scripts/lib/core.sh; resolve_model')" = "qwen3.5:9b"
test "$(LLM_FASTFLOW_MODEL=qwen3.5:4b bash -c 'source scripts/lib/core.sh; resolve_model')" = "qwen3.5:4b"
test "$(LLM_FASTFLOW_MODEL=qwen3.5:4b bash -c 'source scripts/lib/core.sh; resolve_model qwen3.5:9b')" = "qwen3.5:9b"
pass "model selection precedence"

help="$(FLM_BIN=/bin/true bash scripts/llm-fastflow help)"
for command in ask chat prompt code review json ai-commit serve run validate models pull check remove flm api version; do
  grep -Eq "^  ${command}[[:space:]]" <<<"$help" || fail "help missing command: $command"
done
pass "CLI command registry"

version="$(LLM_FASTFLOW_VERSION=test-build FLM_BIN=/bin/true bash scripts/llm-fastflow version | head -n1)"
[[ "$version" == "llm-fastflow test-build" ]] || fail "wrapper version drifted: $version"
pass "wrapper version contract"

compose_json="$(docker compose -f compose.yml config --format json)"
jq -e '.services["llm-fastflow"].image == "infocyph/llm-fastflow:latest"' <<<"$compose_json" >/dev/null
jq -e '.services["llm-fastflow"].environment.LLM_FASTFLOW_MODEL == "qwen3.5:9b"' <<<"$compose_json" >/dev/null
jq -e '.services["llm-fastflow"].environment.FLM_MODEL_PATH == "/models"' <<<"$compose_json" >/dev/null
jq -e '.services["llm-fastflow"].environment.FLM_CORS == "0"' <<<"$compose_json" >/dev/null
jq -e '.services["llm-fastflow"].ports[0].target == 52625' <<<"$compose_json" >/dev/null
jq -e '.services["llm-fastflow"].ports[0].host_ip == "127.0.0.1"' <<<"$compose_json" >/dev/null
jq -e '.services["llm-fastflow"].volumes | any(.target == "/models")' <<<"$compose_json" >/dev/null
jq -e '.services["llm-fastflow"].devices | any(.source == "/dev/accel/accel0" and .target == "/dev/accel/accel0")' <<<"$compose_json" >/dev/null
grep -q 'memlock:' compose.yml
grep -q 'soft: -1' compose.yml
grep -q 'hard: -1' compose.yml
if grep -qE '^[[:space:]]*privileged:' compose.yml; then
  fail "FastFlowLM must not require privileged mode"
fi
if grep -qE '^[[:space:]]*container_name:' compose.yml; then
  fail "fixed container_name is not allowed"
fi
pass "Compose NPU contract"

workspace_json="$(LLM_FASTFLOW_WORKSPACE="$ROOT" docker compose -f compose.yml -f compose.workspace.yml config --format json)"
jq -e '.services["llm-fastflow"].working_dir == "/workspace"' <<<"$workspace_json" >/dev/null
jq -e '.services["llm-fastflow"].volumes | any(.target == "/workspace" and .read_only == true)' <<<"$workspace_json" >/dev/null
pass "optional workspace contract"

grep -Fq 'ARG FASTFLOW_BASE_IMAGE=debian:stable-slim' Dockerfile
grep -Fq "FROM \${FASTFLOW_BASE_IMAGE}" Dockerfile
grep -Fq 'FASTFLOWLM_VERSION=1.0.6' Dockerfile
grep -Fq "fastflowlm_\${FASTFLOWLM_VERSION}_linux.tar.gz" Dockerfile
grep -Fq 'sha256sum -c -' Dockerfile
grep -Fq 'ARG FASTFLOW_MODEL=qwen3.5:9b' Dockerfile
grep -Fq 'FLM_MODEL_PATH="/models"' Dockerfile
grep -Fq "LLM_FASTFLOW_MODEL=\"\${FASTFLOW_MODEL}\"" Dockerfile
grep -Fq "/opt/fastflowlm/flm pull \"\${FASTFLOW_MODEL}\"" Dockerfile
grep -Fq "/opt/fastflowlm/flm check \"\${FASTFLOW_MODEL}\"" Dockerfile
grep -Fq 'EXPOSE 52625' Dockerfile
grep -Fq "http://127.0.0.1:\${FLM_SERVE_PORT:-52625}/v1/models" Dockerfile
grep -Fqx 'ENTRYPOINT ["llm-fastflow"]' Dockerfile
grep -Fqx 'CMD ["serve"]' Dockerfile
grep -Fqx 'STOPSIGNAL SIGINT' Dockerfile
grep -Fq 'libxrt_driver_xdna.so.2' Dockerfile
grep -Fq 'poppler-utils' Dockerfile
grep -Fq 'COPY scripts/prompts /usr/local/lib/llm-fastflow/prompts' Dockerfile
if grep -Fq 'amdxdna-dkms' Dockerfile; then
  fail "host kernel driver must not be installed inside the image"
fi
pass "Dockerfile provider boundary"

for file in scripts/lib/openai.sh scripts/lib/attachments.sh scripts/lib/commit.sh \
  scripts/commands/ask.sh scripts/commands/chat.sh scripts/commands/prompt.sh \
  scripts/commands/code.sh scripts/commands/review.sh scripts/commands/json.sh \
  scripts/commands/ai-commit.sh scripts/commands/api.sh scripts/prompts/ai-commit.txt; do
  [[ -s "$file" ]] || fail "developer parity file missing: $file"
done

grep -Fq '/v1/chat/completions' scripts/lib/openai.sh
grep -Fq '/v1/models' scripts/lib/openai.sh
if grep -R -nE '/api/(chat|generate|tags)' scripts/lib scripts/commands; then
  fail "FastFlow developer CLI must not depend on Ollama-native API routes"
fi

mime_png="$(bash -c 'source scripts/lib/core.sh; source scripts/lib/openai.sh; image_mime sample.png')"
mime_jpeg="$(bash -c 'source scripts/lib/core.sh; source scripts/lib/openai.sh; image_mime sample.jpeg')"
[[ "$mime_png" == image/png ]] || fail "PNG MIME contract drifted"
[[ "$mime_jpeg" == image/jpeg ]] || fail "JPEG MIME contract drifted"

uri_tmp="$(mktemp)"
img_tmp="$(mktemp --suffix=.png)"
trap 'rm -f "$uri_tmp" "$img_tmp" "${fake_flm:-}"' EXIT
printf 'png-test' >"$img_tmp"
bash -c 'source scripts/lib/core.sh; source scripts/lib/openai.sh; encode_images_json "$1" "$2"' _ "$uri_tmp" "$img_tmp"
jq -e 'length == 1 and .[0] | startswith("data:image/png;base64,")' "$uri_tmp" >/dev/null
pass "OpenAI vision data URI contract"

fake_flm="$(mktemp)"
cat >"$fake_flm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*"
EOF
chmod +x "$fake_flm"

pull_args="$(FLM_BIN="$fake_flm" LLM_FASTFLOW_MODEL=qwen3.5:9b bash -c 'source scripts/lib/core.sh; source scripts/commands/pull.sh; command_main --force')"
[[ "$pull_args" == 'pull qwen3.5:9b --force' ]] || fail "pull flags were mistaken for a model: $pull_args"

serve_args="$(FLM_BIN="$fake_flm" LLM_FASTFLOW_MODEL=qwen3.5:9b FLM_HOST=0.0.0.0 FLM_SERVE_PORT=52625 FLM_CORS=0 bash -c 'source scripts/lib/core.sh; source scripts/commands/serve.sh; command_main --cors 1')"
[[ "$serve_args" == 'serve qwen3.5:9b --host 0.0.0.0 --port 52625 --cors 1' ]] ||
  fail "serve flags were mistaken for a model: $serve_args"

serve_override="$(FLM_BIN="$fake_flm" LLM_FASTFLOW_MODEL=qwen3.5:9b FLM_HOST=0.0.0.0 FLM_SERVE_PORT=52625 FLM_CORS=0 bash -c 'source scripts/lib/core.sh; source scripts/commands/serve.sh; command_main --host 127.0.0.1 --port 6000 --cors 1')"
[[ "$serve_override" == 'serve qwen3.5:9b --host 127.0.0.1 --port 6000 --cors 1' ]] ||
  fail "explicit FastFlow server options were duplicated or overwritten: $serve_override"

serve_default="$(FLM_BIN="$fake_flm" LLM_FASTFLOW_MODEL=qwen3.5:9b FLM_HOST=0.0.0.0 FLM_SERVE_PORT=52625 FLM_CORS=0 bash -c 'source scripts/lib/core.sh; source scripts/commands/serve.sh; command_main')"
[[ "$serve_default" == 'serve qwen3.5:9b --host 0.0.0.0 --port 52625 --cors 0' ]] ||
  fail "FastFlow server defaults drifted: $serve_default"
pass "native FastFlow server option preservation"

grep -Fq '/dev/accel/accel0' README.md
grep -Fq 'qwen3.5:9b' README.md
grep -Fq 'qwen3:14b' README.md
grep -Fq 'mutually exclusive' README.md
grep -Fq 'never run at the same time' README.md
pass "documentation and mutual-exclusion contract"

grep -Fq 'branches: [main]' .github/workflows/check.yml
grep -Fq 'releases/latest' .github/workflows/check.yml
grep -Fq 'FASTFLOW_BASE_IMAGE=' .github/workflows/check.yml
grep -Fq 'timeout-minutes: 60' .github/workflows/check.yml
grep -Fq 'target: fastflow-runtime' .github/workflows/check.yml
grep -Fq 'FASTFLOW_EXPECT_BAKED_MODEL: "0"' .github/workflows/check.yml
grep -Fq 'Build final baked image contract' .github/workflows/check.yml
grep -Fq "github.event_name == 'push'" .github/workflows/check.yml
pass "current-upstream and staged-image CI policy"

test -f docs/plans/docker-llm-fastflow-npu-runtime-plan.md
grep -Fq 'fastflow-1.0/npu-runtime' docs/plans/docker-llm-fastflow-npu-runtime-plan.md
grep -Fq 'qwen3.5:9b' docs/plans/docker-llm-fastflow-npu-runtime-plan.md
grep -Fq 'mutually exclusive' docs/plans/docker-llm-fastflow-npu-runtime-plan.md
pass "authoritative implementation plan"

grep -Fq 'workflow_dispatch:' .github/workflows/docker.publish.yml
grep -Fq 'releases/latest' .github/workflows/docker.publish.yml
grep -Fq 'publish_immutable' .github/workflows/docker.publish.yml
grep -Fq 'Refusing to overwrite immutable release tag' .github/workflows/docker.publish.yml
grep -Fq 'platforms: linux/amd64' .github/workflows/docker.publish.yml
grep -Fq 'provenance: mode=max' .github/workflows/docker.publish.yml
grep -Fq 'sbom: true' .github/workflows/docker.publish.yml
grep -Fq 'Verify published runtime by digest' .github/workflows/docker.publish.yml
grep -Fq 'type=gha,scope=fastflow-check' .github/workflows/docker.publish.yml
if grep -Fq 'platforms: linux/amd64,linux/arm64' .github/workflows/docker.publish.yml; then
  fail "arm64 publication must not be enabled without a native FastFlow/XDNA2 gate"
fi
pass "release publication policy"

if grep -R -nF '/var/run/docker.sock' Dockerfile compose.yml scripts; then
  fail "FastFlow provider must not access the Docker socket"
fi
if grep -R -nE -- '--privileged|privileged:[[:space:]]*true' Dockerfile compose.yml scripts; then
  fail "FastFlow provider must not require privileged mode"
fi
pass "provider trust boundary"
