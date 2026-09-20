# ⚡ FastFlowLM Docker for AMD Ryzen AI NPU

[![Check](https://github.com/infocyph/docker-llm-fastflow/actions/workflows/check.yml/badge.svg)](https://github.com/infocyph/docker-llm-fastflow/actions/workflows/check.yml)
[![Docker Publish](https://github.com/infocyph/docker-llm-fastflow/actions/workflows/docker.publish.yml/badge.svg)](https://github.com/infocyph/docker-llm-fastflow/actions/workflows/docker.publish.yml)

`docker-llm-fastflow` is the AMD XDNA2 NPU provider for the Infocyph local-AI stack.

It is intentionally separate from `docker-llm-ollama`:

- **FastFlowLM** owns AMD XDNA2 NPU inference.
- **Ollama** remains the CPU, NVIDIA GPU, and AMD ROCm GPU provider.
- LocalDevStack can choose FastFlow automatically when a supported NPU is available.

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
amdxdna kernel driver
NPU firmware >= 1.1.0.0
/dev/accel/accel0
sufficient/unlimited memlock
```

Validate the device on the host:

```bash
ls -l /dev/accel/accel0
```

The image deliberately does **not** install `amdxdna-dkms`. A container must never replace the host's kernel driver.

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

Default endpoint:

```text
http://127.0.0.1:52625/v1
```

Check status:

```bash
docker compose ps
docker compose logs -f llm-fastflow
```

The first use of a model may download the FastFlow-optimized model artifacts into the persistent model volume.

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
internal:  http://llm-fastflow:52625/v1
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

Provider choice is an internal implementation detail. The end user should normally select or accept a runtime, not manage contradictory provider/runtime settings.

## Image build

Local builds use the current verified FastFlowLM release asset:

```bash
docker build -t llm-fastflow:local .
```

The Dockerfile verifies the official release tarball with SHA-256 before installing it.

Publication resolves the **current stable FastFlowLM GitHub release** at publish time and injects its version and official asset digest into the build. This keeps the moving `latest` image current without making the Dockerfile itself perform an unpinned "download latest" operation.

## Validation

Hardware-independent CI covers:

- Bash and ShellCheck
- Compose/device/memlock contract
- default-model presence in FastFlowLM's current upstream model catalog
- Dockerfile build checks
- official portable package checksum
- image layout
- FastFlowLM version execution without NPU access

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

GitHub-hosted runners do not expose an AMD XDNA2 NPU, so publication CI intentionally does not fake that hardware gate.

## Publication

Stable releases publish:

```text
docker.io/infocyph/llm-fastflow:<release>
docker.io/infocyph/llm-fastflow:latest

ghcr.io/infocyph/llm-fastflow:<release>
ghcr.io/infocyph/llm-fastflow:latest
```

Release tags are immutable. The moving `latest` tag can be refreshed against a newer stable FastFlowLM release after compatibility validation.

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

The only special hardware access is the explicitly passed XDNA2 accelerator device.

## Upstream

Powered by [FastFlowLM](https://github.com/ROCm/FastFlowLM).

FastFlowLM runtime/orchestration code is MIT licensed; model artifacts retain their respective upstream licenses.

## License

MIT
