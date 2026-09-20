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

bash -n scripts/llm-fastflow scripts/lib/*.sh scripts/commands/*.sh
pass "Bash syntax"

test "$(env -u LLM_FASTFLOW_MODEL bash -c 'source scripts/lib/core.sh; resolve_model')" = "qwen3.5:9b"
test "$(LLM_FASTFLOW_MODEL=qwen3.5:4b bash -c 'source scripts/lib/core.sh; resolve_model')" = "qwen3.5:4b"
test "$(LLM_FASTFLOW_MODEL=qwen3.5:4b bash -c 'source scripts/lib/core.sh; resolve_model qwen3.5:9b')" = "qwen3.5:9b"
pass "model selection precedence"

help="$(FLM_BIN=/bin/true bash scripts/llm-fastflow help)"
for command in serve run validate models pull check remove flm version; do
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
jq -e '.services["llm-fastflow"].volumes | any(.target == "/models")' <<<"$compose_json" >/dev/null
jq -e '.services["llm-fastflow"].devices | any(.source == "/dev/accel/accel0" and .target == "/dev/accel/accel0")' <<<"$compose_json" >/dev/null
if grep -qE '^[[:space:]]*privileged:' compose.yml; then
  fail "FastFlowLM must not require privileged mode"
fi
if grep -qE '^[[:space:]]*container_name:' compose.yml; then
  fail "fixed container_name is not allowed"
fi
grep -q 'memlock:' compose.yml
grep -q 'soft: -1' compose.yml
grep -q 'hard: -1' compose.yml
pass "Compose NPU contract"

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
grep -Fq 'http://127.0.0.1:52625/v1/models' Dockerfile
grep -Fqx 'ENTRYPOINT ["llm-fastflow"]' Dockerfile
grep -Fqx 'CMD ["serve"]' Dockerfile
grep -Fqx 'STOPSIGNAL SIGINT' Dockerfile
grep -Fq 'libxrt_driver_xdna.so.2' Dockerfile
if grep -Fq 'amdxdna-dkms' Dockerfile; then
  fail "host kernel driver must not be installed inside the image"
fi
pass "Dockerfile provider boundary"

grep -Fq '/dev/accel/accel0' README.md
grep -Fq 'qwen3.5:9b' README.md
grep -Fq 'qwen3:14b' README.md
pass "documentation contract"

grep -Fq 'branches: [main]' .github/workflows/check.yml
grep -Fq 'releases/latest' .github/workflows/check.yml
grep -Fq 'FASTFLOW_BASE_IMAGE=' .github/workflows/check.yml
grep -Fq 'timeout-minutes: 60' .github/workflows/check.yml
pass "current-upstream CI policy"

test -f docs/plans/docker-llm-fastflow-npu-runtime-plan.md
grep -Fq 'fastflow-1.0/npu-runtime' docs/plans/docker-llm-fastflow-npu-runtime-plan.md
grep -Fq 'qwen3.5:9b' docs/plans/docker-llm-fastflow-npu-runtime-plan.md
pass "authoritative implementation plan"

grep -Fq 'workflow_dispatch:' .github/workflows/docker.publish.yml
grep -Fq 'releases/latest' .github/workflows/docker.publish.yml
grep -Fq 'publish_immutable' .github/workflows/docker.publish.yml
grep -Fq 'Refusing to overwrite immutable release tag' .github/workflows/docker.publish.yml
grep -Fq 'platforms: linux/amd64' .github/workflows/docker.publish.yml
grep -Fq 'provenance: mode=max' .github/workflows/docker.publish.yml
grep -Fq 'sbom: true' .github/workflows/docker.publish.yml
grep -Fq 'Verify published runtime by digest' .github/workflows/docker.publish.yml
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

fake_flm="$(mktemp)"
trap 'rm -f "$fake_flm"' EXIT
cat >"$fake_flm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*"
EOF
chmod +x "$fake_flm"

pull_args="$(FLM_BIN="$fake_flm" LLM_FASTFLOW_MODEL=qwen3.5:9b bash -c 'source scripts/lib/core.sh; source scripts/commands/pull.sh; command_main --force')"
[[ "$pull_args" == 'pull qwen3.5:9b --force' ]] || fail "pull flags were mistaken for a model: $pull_args"

serve_args="$(FLM_BIN="$fake_flm" LLM_FASTFLOW_MODEL=qwen3.5:9b FLM_HOST=0.0.0.0 FLM_SERVE_PORT=52625 FLM_CORS=0 bash -c 'source scripts/lib/core.sh; source scripts/commands/serve.sh; command_main --cors 1')"
[[ "$serve_args" == 'serve qwen3.5:9b --host 0.0.0.0 --port 52625 --cors 1' ]] || fail "serve flags were mistaken for a model: $serve_args"

serve_override="$(FLM_BIN="$fake_flm" LLM_FASTFLOW_MODEL=qwen3.5:9b FLM_HOST=0.0.0.0 FLM_SERVE_PORT=52625 FLM_CORS=0 bash -c 'source scripts/lib/core.sh; source scripts/commands/serve.sh; command_main --host 127.0.0.1 --port 6000 --cors 1')"
[[ "$serve_override" == 'serve qwen3.5:9b --host 127.0.0.1 --port 6000 --cors 1' ]] ||
  fail "explicit FastFlow server options were duplicated or overwritten: $serve_override"

serve_default="$(FLM_BIN="$fake_flm" LLM_FASTFLOW_MODEL=qwen3.5:9b FLM_HOST=0.0.0.0 FLM_SERVE_PORT=52625 FLM_CORS=0 bash -c 'source scripts/lib/core.sh; source scripts/commands/serve.sh; command_main')"
[[ "$serve_default" == 'serve qwen3.5:9b --host 0.0.0.0 --port 52625 --cors 0' ]] ||
  fail "FastFlow server defaults drifted: $serve_default"

pass "optional model arguments and native FastFlow server options are preserved"
