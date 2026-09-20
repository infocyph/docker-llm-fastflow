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

bash -n scripts/entrypoint.sh scripts/llm-fastflow
shellcheck scripts/entrypoint.sh scripts/llm-fastflow
pass "shell syntax and ShellCheck"

grep -Fqx 'FROM debian:13-slim' Dockerfile || fail "Dockerfile must use Debian 13 slim"
grep -Fq 'ARG FASTFLOW_VERSION=1.0.6' Dockerfile || fail "FastFlow fallback version drifted"
grep -Fq 'ARG FASTFLOW_SHA256=99f1032656b3dd8135675ca3be4e3aa4169e732ecd2d5fb886b24570b0a80851' Dockerfile ||
  fail "FastFlow portable asset digest drifted"
grep -Fq 'LLM_FASTFLOW_MODEL="qwen3.5:9b"' Dockerfile || fail "default model drifted"
grep -Eq '^EXPOSE[[:space:]]+52625[[:space:]]*$' Dockerfile || fail "port contract drifted"
grep -Fqx 'STOPSIGNAL SIGTERM' Dockerfile || fail "stop signal contract drifted"
grep -Fqx 'ENTRYPOINT ["/usr/local/bin/llm-fastflow-entrypoint"]' Dockerfile ||
  fail "entrypoint contract drifted"
pass "Dockerfile provider contract"

compose="$(docker compose -f compose.yml config)"
grep -Fq '/dev/accel/accel0' <<<"$compose" || fail "NPU device mapping missing"
grep -Fq 'memlock:' <<<"$compose" || fail "memlock ulimit missing"
grep -Fq '127.0.0.1' <<<"$compose" || fail "standalone API must bind loopback only"
grep -Fq '52625' <<<"$compose" || fail "FastFlow server port missing"
grep -Fq '/models' <<<"$compose" || fail "persistent model mount missing"
grep -Fq 'qwen3.5:9b' <<<"$compose" || fail "Compose default model drifted"

if grep -Eq '^[[:space:]]*privileged:' compose.yml; then
  fail "privileged mode is not allowed"
fi
if grep -Fq '/var/run/docker.sock' compose.yml; then
  fail "Docker socket is not allowed"
fi
if grep -Eq '^[[:space:]]*container_name:' compose.yml; then
  fail "fixed container_name is not allowed"
fi
pass "Compose XDNA2 security contract"

fake="$(mktemp)"
trap 'rm -f "$fake"' EXIT
cat >"$fake" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@"
EOF
chmod +x "$fake"

args="$(
  FLM_BIN="$fake" \
  LLM_FASTFLOW_MODEL=qwen3.5:9b \
  FLM_SERVE_PORT=52625 \
  LLM_FASTFLOW_QUEUE_LENGTH=10 \
  LLM_FASTFLOW_SOCKET_CONNECTIONS=10 \
  bash scripts/entrypoint.sh
)"

for expected in serve qwen3.5:9b --host 0.0.0.0 --port 52625 --cors 0 --q-len 10 --socket 10; do
  grep -Fxq -- "$expected" <<<"$args" || fail "entrypoint missing argument: $expected"
done
pass "default entrypoint command"

args="$(
  FLM_BIN="$fake" \
  LLM_FASTFLOW_MODEL=qwen3.5:9b \
  FLM_SERVE_PORT=52625 \
  LLM_FASTFLOW_QUEUE_LENGTH=10 \
  LLM_FASTFLOW_SOCKET_CONNECTIONS=10 \
  bash scripts/entrypoint.sh serve qwen3.5:4b --port 6000 --host 127.0.0.1 --cors 1
)"
grep -Fxq 'qwen3.5:4b' <<<"$args" || fail "explicit model override lost"
grep -Fxq '6000' <<<"$args" || fail "explicit port override lost"
grep -Fxq '127.0.0.1' <<<"$args" || fail "explicit host override lost"
grep -Fxq '1' <<<"$args" || fail "explicit CORS override lost"
pass "explicit FastFlow serve overrides"

wrapper_version="$(
  FLM_BIN="$fake" LLM_FASTFLOW_VERSION=test-build bash scripts/llm-fastflow version
)"
grep -Fqx 'llm-fastflow test-build' <<<"$wrapper_version" ||
  fail "wrapper version contract drifted"

models="$(
  FLM_BIN="$fake" bash scripts/llm-fastflow models --json
)"
grep -Fxq 'list' <<<"$models" || fail "models alias must call flm list"
grep -Fxq -- '--json' <<<"$models" || fail "models arguments were not forwarded"
pass "CLI wrapper command mapping"

if grep -R -nE 'docker (run|exec|start|stop|restart|logs)|/var/run/docker.sock' scripts; then
  fail "bundled provider scripts must not own Docker lifecycle"
fi
pass "provider CLI trust boundary"
