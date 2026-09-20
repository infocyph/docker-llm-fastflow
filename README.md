# ⚡ FastFlowLM Docker for AMD Ryzen AI NPU

[![Check](https://github.com/infocyph/docker-llm-fastflow/actions/workflows/check.yml/badge.svg)](https://github.com/infocyph/docker-llm-fastflow/actions/workflows/check.yml)
[![Docker Publish](https://github.com/infocyph/docker-llm-fastflow/actions/workflows/docker.publish.yml/badge.svg)](https://github.com/infocyph/docker-llm-fastflow/actions/workflows/docker.publish.yml)

`docker-llm-fastflow` is the AMD XDNA2 NPU provider for the Infocyph local-AI stack.

It is intentionally separate from `docker-llm-ollama`:

- **FastFlowLM** owns AMD XDNA2 NPU inference.
- **Ollama** remains the CPU, NVIDIA GPU, and AMD ROCm GPU provider.
- The two provider services are **mutually exclusive** for one LocalDevStack runtime.
- `llm-fastflow` and `llm-ollama` **never run at the same time** in the selected architecture.
- LocalDevStack chooses FastFlow automatically when a supported NPU is available.
- The external/common `llm` identity points to whichever single provider is active.

## Runtime contract

| Item | Contract |
|---|---|
| Runtime | FastFlowLM |
| Current upstream baseline | FastFlowLM 1.0.6 |
| Accelerator | AMD XDNA2 NPU |
| NPU device | `/dev/accel/accel0` |
| Default model | `qwen3.5:9b` |
| API | OpenAI-compatible `/v1` |
| Container port | `52625` |
| Model store | `/models` |
| Published platform | `linux/amd64` |
| Host driver | `amdxdna` |
| Container privilege | not required |

The image packages FastFlowLM's official portable Linux distribution. The host owns the kernel driver and NPU firmware; the container owns the FastFlowLM/XRT/XDNA userspace runtime.

## Why `qwen3.5:9b` is the default

The original target was `qwen3:14b`, matching the Ollama provider. FastFlowLM's current NPU model catalog does **not** publish a `qwen3:14b` artifact.

For Ryzen AI 9 HX 370 / Strix Point, the current default is therefore:

```text
qwen3.5:9b
```

It is an XDNA2-native FastFlow model with reasoning, vision, and tool-capable model support and is a strong fit for the HX 370's NPU. The default is centralized in `LLM_FASTFLOW_MODEL`, so moving to a future `qwen3:14b` FastFlow artifact requires no architecture change.

## Supported host hardware

FastFlowLM currently requires an AMD **XDNA2** NPU. Relevant families include:

- Ryzen AI 300-series / Strix Point and Kraken Point
- Ryzen AI Max 300-series / Strix Halo
- Ryzen AI 400-series / Gorgon Point
- Ryzen Z2 Extreme-class XDNA2 devices

XDNA1 is not part of this image contract.

## Host prerequisites

Docker does not emulate the NPU. The host must provide the working kernel/firmware stack before the container starts.

Minimum host contract:

```text
AMD XDNA2 NPU
Kernel 7.0+ with amdxdna, or a host-installed amdxdna-dkms driver
NPU firmware >= 1.1.0.0
/dev/accel/accel0
sufficient/unlimited memlock
```

Validate the device on the host:

```bash
ls -l /dev/accel/accel0
```

The image deliberately does **not** install `amdxdna-dkms`. FastFlowLM's current Linux contract allows kernel 7.0+ with the in-kernel `amdxdna` driver or a compatible host-installed `amdxdna-dkms`; either way, kernel-driver ownership stays on the host.

## Quick start

```bash
docker compose pull
docker compose up -d
```

The standalone Compose file:

- maps `/dev/accel/accel0`
- gives the container unlimited memlock
- persists models in `llm-fastflow-models`
- exposes the API only on loopback
- keeps FastFlow CORS disabled by default

Default endpoint:

```text
http://127.0.0.1:52625/v1
```

Check status:

```bash
docker compose ps
docker compose logs -f llm-fastflow
```

The default `qwen3.5:9b` FastFlow-optimized model is baked into the image. On first creation of the named volume, Docker seeds `/models` from the image, so the default runtime does not need a first-run model download. Additional models are downloaded into the persistent volume as needed.

## Persistent model state

The default volume is:

```text
llm-fastflow-models -> /models
```

Override the volume name when isolation is required:

```bash
LLM_FASTFLOW_VOLUME=my-fastflow-models docker compose up -d
```

Override the default model:

```bash
LLM_FASTFLOW_MODEL=qwen3.5:4b docker compose up -d
```

## Bundled CLI

The image exposes a small provider-focused wrapper:

```text
Runtime: serve, run, validate
Models:  models, pull, check, remove
Low:     flm, version, help
```

Examples:

```bash
docker compose exec llm-fastflow llm-fastflow version
docker compose exec llm-fastflow llm-fastflow validate
docker compose exec llm-fastflow llm-fastflow models
docker compose exec llm-fastflow llm-fastflow pull qwen3.5:9b
docker compose exec llm-fastflow llm-fastflow check qwen3.5:9b
```

Use the native FastFlow CLI when needed:

```bash
docker compose exec llm-fastflow llm-fastflow flm help
```

## Developer CLI parity

FastFlow now carries the same developer-facing command family as `llm-ollama` where
the backend capability exists:

```text
Developer: ask, chat, prompt, code, review, json, ai-commit
Runtime:   serve, run, validate
Model:     models, pull, check, remove
Low level: flm, api, version
```

The developer commands use FastFlowLM's maintained OpenAI-compatible API
(`/v1/models`, `/v1/chat/completions`). They do not emulate Ollama-native
`/api/*` endpoints.

Thinking stays at the model/provider default for normal developer commands. Set
`LLM_FASTFLOW_THINK=true|false` to force it per invocation. Strict structured
output is different: `llm-fastflow json` always sends `think:false` so reasoning
cannot displace or contaminate the JSON response.

FastFlow's Qwen3.5 9B model supports vision. `prompt` accepts PNG/JPEG images and can
render PDF pages to PNG for vision input. Text PDFs can be extracted locally with
Poppler.

Repository-aware commands can use the optional workspace overlay:

```bash
LLM_FASTFLOW_WORKSPACE="$PWD" \
  docker compose -f compose.yml -f compose.workspace.yml up -d
```

The workspace defaults to read-only. Set `LLM_FASTFLOW_WORKSPACE_MODE=rw` only for
commands such as `ai-commit --yes` that intentionally mutate Git state.

## OpenAI-compatible API

List models:

```bash
curl http://127.0.0.1:52625/v1/models
```

Chat completion:

```bash
curl http://127.0.0.1:52625/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "qwen3.5:9b",
    "messages": [
      {"role": "user", "content": "Reply with OK only."}
    ],
    "stream": false
  }'
```

FastFlowLM also supports its maintained OpenAI-compatible embeddings and audio-transcription endpoints.

## Standalone `docker run`

```bash
docker run -d \
  --name llm-fastflow \
  --restart unless-stopped \
  --device /dev/accel/accel0:/dev/accel/accel0 \
  --ulimit memlock=-1:-1 \
  -p 127.0.0.1:52625:52625 \
  --mount type=volume,src=llm-fastflow-models,dst=/models \
  infocyph/llm-fastflow:latest
```

No `--privileged` flag is required.

## LocalDevStack integration contract

LocalDevStack should treat this as the NPU runtime:

```text
runtime:   npu
service:   llm-fastflow
internal standalone: http://llm-fastflow:52625/v1
LocalDevStack common identity: http://llm:11434/v1
device:    /dev/accel/accel0
model:     qwen3.5:9b
```

Expected automatic preference:

```text
supported XDNA2 NPU -> FastFlowLM
NVIDIA GPU          -> Ollama
AMD ROCm GPU        -> Ollama
otherwise           -> Ollama CPU
```

Provider choice is an internal implementation detail. Only one provider is started for a stack: FastFlow on a supported XDNA2 NPU, otherwise Ollama on NVIDIA/ROCm/CPU. The common `llm` route therefore needs no load balancing or failover between simultaneously running providers; it is simply an alias for the selected one.

## Image build

Local builds use the current verified FastFlowLM release asset:

```bash
docker build -t llm-fastflow:local .
```

The Dockerfile verifies the official release tarball with SHA-256 before installing it, then pulls and verifies the HX 370 default `qwen3.5:9b` model during the image build. Heavy OS, FastFlow runtime, and model layers are isolated from the per-build image version so normal commits/releases can reuse the multi-gigabyte model cache.

CI and publication resolve the **current stable FastFlowLM GitHub release** and verify that `qwen3.5:9b` exists in that exact release catalog. Publication also resolves the moving `debian:stable-slim` base to a digest before building. This keeps `latest` current while making each individual build traceable to concrete upstream inputs.

## Validation

Hardware-independent CI covers:

- Bash and ShellCheck
- Compose/device/memlock contract
- default-model presence in FastFlowLM's current upstream model catalog
- Dockerfile build checks
- official portable package checksum
- a lightweight `fastflow-runtime` image smoke without exporting the multi-gigabyte model layer
- a full `final` baked-model build contract whose model pull/check executes inside BuildKit
- baked `qwen3.5:9b` model integrity
- FastFlowLM version execution without NPU access
- critical XRT/XDNA shared-library dependency resolution

Real NPU validation is provided separately:

```bash
bash scripts/ci/npu-smoke.sh infocyph/llm-fastflow:latest
```

That test requires an XDNA2 host and verifies:

- device access
- `flm validate`
- server health
- `/v1/models`
- real NPU chat inference
- named-volume persistence across container recreation
- restart health
- the image SIGINT stop contract

GitHub-hosted runners do not expose an AMD XDNA2 NPU, so publication CI intentionally does not fake that hardware gate.

## Publication

Stable releases publish:

```text
docker.io/infocyph/llm-fastflow:<release>
docker.io/infocyph/llm-fastflow:latest

ghcr.io/infocyph/llm-fastflow:<release>
ghcr.io/infocyph/llm-fastflow:latest
```

Release tags are immutable. The moving `latest` tag can be refreshed against a newer stable FastFlowLM release after compatibility validation. Publication can reuse the baked-model cache generated by main-branch validation, while the published final image is still verified by registry digest.

Publication is currently `linux/amd64` only because the upstream FastFlowLM Linux release asset and supported Ryzen AI NPU systems are x86-64.

## Security and isolation

The image intentionally has:

- no Docker socket
- no `--privileged`
- no host kernel-driver installation
- no wildcard host binding
- no cloud-provider fallback
- no automatic workspace mount
- update checks disabled inside the fixed container runtime

The only special hardware access is the explicitly passed XDNA2 accelerator device. Docker stop uses `SIGINT`, matching FastFlowLM's Linux signal path.

FastFlow's internal server binds `0.0.0.0` so other containers can reach it, while the standalone Compose publication remains loopback-only. The wrapper also defaults `--cors 0`; callers can explicitly override native FastFlow server flags when required.

## Implementation plan

The authoritative implementation and release-readiness plan is:

```text
docs/plans/docker-llm-fastflow-npu-runtime-plan.md
```

All remaining work stays on `fastflow-1.0/npu-runtime`.

## Upstream

Powered by [FastFlowLM](https://github.com/ROCm/FastFlowLM).

FastFlowLM runtime/orchestration code is MIT licensed; model artifacts retain their respective upstream licenses.

## License

MIT
