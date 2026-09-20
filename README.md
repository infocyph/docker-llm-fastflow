# docker-llm-fastflow

FastFlowLM provider image for **AMD Ryzen AI XDNA2 NPUs**, designed as the NPU sibling
of [docker-llm-ollama](https://github.com/infocyph/docker-llm-ollama).

> Status: active implementation on `fastflow-1.0/xdna2-runtime`.

## Target

Primary validation target:

- AMD Ryzen AI 9 HX 370 / Strix Point
- XDNA2 NPU
- Linux/amd64
- `/dev/accel/accel0`

This image is intentionally NPU-only. CPU, NVIDIA GPU and AMD ROCm GPU inference remain
the responsibility of `docker-llm-ollama`.

## Default model

The first runnable default is:

```text
qwen3.5:9b
```

FastFlowLM does not currently publish a `qwen3:14b` NPU2 model, so this repository does
not invent that tag. Qwen3.5 9B is the current practical default for Ryzen AI 9 HX 370:
NPU2/Q4_K weights, reasoning, tool-calling, vision, about 8.7 GB model footprint and a
32k default context.

The default is centralized as `LLM_FASTFLOW_MODEL` so it can move to Qwen3 14B when
FastFlowLM actually publishes that model.

## Runtime source

The image consumes the official portable Linux release from
[ROCm/FastFlowLM](https://github.com/ROCm/FastFlowLM).

Current direct-build fallback:

```text
FastFlowLM v1.0.6
fastflowlm_1.0.6_linux.tar.gz
```

The archive includes FastFlowLM plus its portable XRT/XDNA userspace libraries. The host
still owns the kernel driver, firmware and NPU device.

## Host requirements

The host must provide:

- supported AMD XDNA2 hardware;
- current NPU firmware;
- working `amdxdna` driver;
- `/dev/accel/accel0`;
- Docker device passthrough.

FastFlowLM currently does not support XDNA1 for this Linux runtime.

The container does **not** install a kernel driver and does not use privileged mode.

## Build

```bash
docker build -t infocyph/llm-fastflow:latest .
```

The build verifies the SHA256 of the official FastFlow portable release before
installing it.

## Run with Compose

```bash
docker compose up -d
docker compose logs -f llm-fastflow
```

The standalone API is bound only to:

```text
http://127.0.0.1:52625
```

OpenAI-compatible base URL:

```text
http://127.0.0.1:52625/v1
```

The first start may download `qwen3.5:9b`. Models persist in:

```text
llm-fastflow-data -> /models
```

## Docker runtime contract

The service passes only the required NPU device:

```text
/dev/accel/accel0
```

and enables unlimited memlock for XDNA execution.

It does not require:

- `--privileged`;
- Docker socket access;
- `/dev/kfd`;
- `/dev/dri`;
- NVIDIA runtime.

## CLI

Inside the image:

```bash
llm-fastflow help
llm-fastflow version
llm-fastflow validate
llm-fastflow models
llm-fastflow pull qwen3.5:9b
llm-fastflow run qwen3.5:9b
llm-fastflow bench qwen3.5:9b
llm-fastflow flm version
```

The wrapper delegates model/runtime behavior to FastFlowLM and deliberately does not own
Docker lifecycle.

## Direct API check

Once the model server is healthy:

```bash
curl -fsS http://127.0.0.1:52625/v1/models | jq
```

OpenAI-compatible chat requests use `/v1/chat/completions`.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `LLM_FASTFLOW_MODEL` | `qwen3.5:9b` | Default FastFlow model |
| `LLM_FASTFLOW_VOLUME` | `llm-fastflow-data` | Persistent model volume |
| `LLM_FASTFLOW_NPU_DEVICE` | `/dev/accel/accel0` | Host NPU device |
| `FASTFLOW_PORT` | `52625` | Standalone host loopback port |
| `FLM_MODEL_PATH` | `/models` | In-container model store |
| `LLM_FASTFLOW_CONTEXT_LENGTH` | empty | Optional context override |
| `LLM_FASTFLOW_QUEUE_LENGTH` | `10` | Server request queue |
| `LLM_FASTFLOW_SOCKET_CONNECTIONS` | `10` | Server socket limit |

FastFlow update checks are disabled in the container with
`FLM_DISABLE_UPDATE_CHECK=1`; image refresh/publication will own runtime upgrades.

## LocalDevStack boundary

This repository only supplies the FastFlow provider image.

After the image is validated on the Ryzen AI 9 HX 370, LocalDevStack will detect a
compatible XDNA2 NPU and choose FastFlow automatically. Ollama remains the fallback for
CPU/NVIDIA/ROCm paths.

See:

```text
docs/plans/docker-llm-fastflow-xdna2-runtime-plan.md
```

for the implementation sequence.

## Upstream

Powered by [FastFlowLM](https://github.com/ROCm/FastFlowLM).

FastFlowLM upstream runtime/orchestration code is MIT licensed. Review upstream model
licenses individually for downloaded model weights.

## License

MIT
