# docker-llm-fastflow 1.0 — XDNA2 NPU Runtime Plan

Status: active implementation plan  
Primary branch: `fastflow-1.0/npu-runtime`  
Primary hardware target: AMD Ryzen AI 9 HX 370 / Strix Point / XDNA2  
Provider runtime: FastFlowLM  
Current default model: `qwen3.5:9b`

## 1. Product boundary

`docker-llm-fastflow` is the AMD XDNA2 NPU provider for the Infocyph local-AI stack.

Responsibility split:

```text
docker-llm-fastflow -> AMD XDNA2 NPU / FastFlowLM
docker-llm-ollama  -> CPU / NVIDIA GPU / AMD ROCm GPU / Ollama
```

This repository must stay provider-focused. It packages FastFlowLM, exposes its API,
persists its model state, and provides a small runtime CLI.

LocalDevStack owns automatic hardware detection and provider selection. Once this image
is published and validated, a compatible XDNA2 NPU should win automatically over the
Ollama CPU/GPU paths without requiring an end-user provider selector.

## 2. Hardware target

Primary validation system:

```text
AMD Ryzen AI 9 HX 370
Codename: Strix Point
NPU: XDNA2
NPU throughput: up to 50 TOPS
Linux device: /dev/accel/accel0
Architecture: linux/amd64
```

The host owns:

- supported XDNA2 hardware;
- compatible NPU firmware;
- compatible `amdxdna` kernel driver;
- working `/dev/accel/accel0`;
- kernel/firmware pairing supported by FastFlowLM;
- Docker device passthrough.

The container owns:

- FastFlowLM runtime;
- bundled portable XRT/XDNA userspace libraries;
- FastFlow model catalog and xclbins;
- model storage;
- server/API lifecycle;
- health diagnostics.

The container must never install `amdxdna-dkms` or otherwise replace the host kernel
driver.

## 3. FastFlowLM source policy

Consume the official stable portable Linux release from `ROCm/FastFlowLM`.

Current direct-build fallback at plan creation:

```text
FastFlowLM v1.0.6
asset: fastflowlm_1.0.6_linux.tar.gz
sha256: 99f1032656b3dd8135675ca3be4e3aa4169e732ecd2d5fb886b24570b0a80851
```

CI and publication must resolve the current stable FastFlowLM release dynamically,
obtain the official GitHub release-asset digest, and feed the resolved version/digest
into the image build.

Rules:

- stable upstream release may refresh the moving provider image;
- draft upstream releases are rejected;
- prereleases must never silently move stable `:latest`;
- release asset SHA-256 verification is mandatory;
- do not rebuild the full FastFlow native toolchain in this repository when the official
  portable artifact is available.

## 4. Base image policy

Use the current Debian stable slim image:

```text
debian:stable-slim
```

Publication/CI resolves it to a digest per build.

Do not use Alpine for this provider. FastFlowLM's portable Linux runtime and bundled
XRT/XDNA libraries are glibc-native. An Alpine/musl compatibility layer would add
complexity without improving the NPU runtime.

## 5. Default model

Desired original product target:

```text
qwen3:14b
```

FastFlowLM does not currently publish a compatible `qwen3:14b` XDNA2 model artifact.
Do not fabricate that model tag.

Current HX 370 default:

```text
qwen3.5:9b
```

Reasons:

- current-generation Qwen model available in FastFlowLM;
- XDNA2-native FastFlow artifact;
- Q4_K weights;
- reasoning support;
- tool-capable model behavior;
- vision support;
- approximately 8.7 GB model footprint;
- 32k default context;
- much safer default for common 32 GB HX 370 systems than the ~22 GB
  `qwen3.6-moe:35b-a3b` model.

The default must remain centralized through:

```text
LLM_FASTFLOW_MODEL=qwen3.5:9b
```

When FastFlowLM publishes a supported Qwen3 14B artifact, changing the product default
should only require model/default, contract-test, documentation, and runtime-validation
updates.

## 6. Model delivery and persistence

The provider image intentionally bakes the HX 370 default model.

Build-time requirements:

```text
flm pull "$LLM_FASTFLOW_MODEL"
flm check "$LLM_FASTFLOW_MODEL"
```

This makes first startup immediately usable and keeps the FastFlow provider behavior
aligned with the ready-to-run default-model policy used by the Ollama image.

Runtime storage:

```text
FLM_MODEL_PATH=/models
llm-fastflow-models -> /models
```

Docker seeds the new named volume from the image's `/models` content on first creation.
Additional models and later runtime model changes persist in the volume.

The model store must never be shared with Ollama's `/root/.ollama` format.

## 7. Runtime API contract

FastFlowLM server contract:

```text
container port: 52625
OpenAI base:    http://llm-fastflow:52625/v1
health:         GET /v1/models
```

FastFlow defaults its host binding to localhost, so the container wrapper must force:

```text
--host 0.0.0.0
--port 52625
```

Standalone Compose publishes only:

```text
127.0.0.1:52625:52625
```

No wildcard host publication by default.

LocalDevStack/Nginx will own the higher-level user-facing route.

## 8. NPU Docker contract

Standalone Compose must use the narrow hardware contract:

```yaml
devices:
  - /dev/accel/accel0:/dev/accel/accel0

ulimits:
  memlock:
    soft: -1
    hard: -1
```

Do not require:

- `--privileged`;
- Docker socket;
- `/dev/kfd`;
- `/dev/dri`;
- NVIDIA runtime;
- arbitrary host mounts.

If real HX 370 validation proves another capability is required, add only that specific
capability/device and document the evidence.

## 9. Environment contract

Provider-facing defaults:

```text
LLM_FASTFLOW_MODEL=qwen3.5:9b
FLM_MODEL_PATH=/models
FLM_SERVE_PORT=52625
FLM_HOST=0.0.0.0
FLM_DISABLE_UPDATE_CHECK=1
LLM_FASTFLOW_VERSION=<image/release version>
```

Do not expose configuration knobs unless FastFlowLM actually consumes them.

## 10. CLI contract

Bundled CLI:

```text
llm-fastflow
```

Supported commands:

```text
serve [model] [args...]
run [model] [args...]
validate [args...]
models [args...]
pull [model] [args...]
check [model] [args...]
remove <model> [args...]
flm [args...]
version
help
```

The wrapper delegates to FastFlowLM and must not own Docker lifecycle.

Do not add image-internal commands such as:

```text
start
stop
restart
logs
install
uninstall
```

## 11. Dockerfile contract

The final Dockerfile must:

1. resolve from `debian:stable-slim`;
2. contain only required runtime packages;
3. download the official FastFlow portable archive;
4. verify the release SHA-256;
5. install it under `/opt/fastflowlm`;
6. verify the portable dynamic-library closure;
7. expose FastFlow on PATH;
8. bake and verify `qwen3.5:9b`;
9. install the `llm-fastflow` wrapper;
10. expose port 52625;
11. healthcheck `/v1/models`;
12. use FastFlow's graceful stop signal;
13. contain no kernel-driver installation;
14. contain no Docker socket access.

## 12. Compose contract

Root Compose service:

```text
service: llm-fastflow
image: infocyph/llm-fastflow:latest
```

Required behavior:

- XDNA2 device mapping;
- unlimited memlock;
- loopback-only API publication;
- persistent `/models` volume;
- default-model environment;
- update checks disabled;
- restart unless-stopped;
- no fixed `container_name`;
- no privileged mode.

## 13. CI strategy

GitHub-hosted runners do not expose AMD XDNA2 NPUs.

CI is therefore split into two layers.

### Hardware-independent CI

Must verify:

- Bash syntax;
- ShellCheck;
- CLI registry/contracts;
- Compose rendering;
- NPU device/memlock contract;
- current stable FastFlowLM release resolution;
- official release-asset digest;
- presence of `qwen3.5:9b` in the resolved upstream model catalog;
- Debian stable base resolution to a digest;
- Dockerfile BuildKit checks;
- full provider-image build;
- baked model integrity;
- FastFlow version execution;
- XRT/XDNA shared-library dependency closure;
- image metadata/environment contract.

### Real NPU gate

A real XDNA2 host must execute:

```bash
bash scripts/ci/npu-smoke.sh infocyph/llm-fastflow:latest
```

The smoke test must validate:

- host NPU device exists;
- container device access;
- `flm validate`;
- server health;
- `/v1/models`;
- real non-streaming chat inference;
- clean runtime shutdown.

A future self-hosted HX 370 runner may automate this gate. Until then, do not fake NPU
inference on GitHub-hosted CI.

## 14. Publication contract

Publish:

```text
docker.io/infocyph/llm-fastflow
ghcr.io/infocyph/llm-fastflow
```

Tags:

```text
latest
<immutable repository release>
```

Platform:

```text
linux/amd64
```

Publication must:

- build from an exact repository release source;
- resolve current stable FastFlowLM;
- verify upstream asset digest;
- resolve Debian stable to a digest;
- build one validated candidate;
- publish Docker Hub and GHCR;
- keep immutable release tags immutable;
- allow moving stable `:latest`;
- generate BuildKit provenance;
- generate SBOM;
- generate registry attestations;
- verify post-push digest/platform.

Do not claim arm64 support before FastFlow publishes/supports a corresponding native
runtime and hardware contract.

## 15. Security boundary

Default image/service security contract:

- no Docker socket;
- no privileged mode;
- no host kernel-driver installation;
- no cloud-provider fallback;
- no wildcard host publication;
- no automatic project/workspace mount;
- update checks disabled inside the runtime;
- only the explicit XDNA2 accelerator device is passed.

## 16. Documentation contract

README must cover:

- provider split with Ollama;
- Ryzen AI 9 HX 370/XDNA2 target;
- host driver/firmware/device requirements;
- XDNA1 exclusion;
- `qwen3.5:9b` rationale;
- current lack of FastFlow Qwen3 14B;
- quick start;
- model seeding/persistence;
- OpenAI-compatible API;
- CLI;
- real NPU smoke testing;
- security boundaries;
- LocalDevStack automatic-selection contract;
- publication behavior;
- upstream attribution.

Include:

```text
Powered by FastFlowLM
```

## 17. Implementation batches

### Batch 1 — repository/runtime foundation

Status: implemented.

- Dockerfile;
- Compose contract;
- CLI wrapper;
- model/runtime boundary;
- README;
- static contracts.

### Batch 2 — portable FastFlow hardening

Status: implemented, final CI verification pending.

- official portable release;
- SHA-256 verification;
- runtime dependencies;
- dynamic-library closure checks;
- current stable upstream resolution.

### Batch 3 — HX 370 default model

Status: implemented, final CI verification pending.

- `qwen3.5:9b`;
- build-time pull/check;
- persistent model volume;
- current upstream model-catalog validation.

### Batch 4 — XDNA2 runtime hardening

Status: implemented.

- `/dev/accel/accel0`;
- memlock unlimited;
- no privileged mode;
- loopback-only standalone API.

### Batch 5 — provider API and NPU smoke

Status: implemented, real HX 370 execution still required.

- `/v1/models` healthcheck;
- OpenAI-compatible chat contract;
- real NPU smoke script.

### Batch 6 — release automation

Status: implemented, release publication dry-run/final verification pending.

- Docker Hub;
- GHCR;
- current FastFlow stable resolver;
- current Debian stable resolver;
- immutable release tags;
- moving latest;
- provenance/SBOM;
- digest verification;
- scheduled refresh.

### Batch 7 — final branch hardening

Status: active.

- add this authoritative plan;
- run current branch CI to green;
- inspect/fix any remaining image/runtime contract failures;
- validate publication workflow semantics;
- re-audit current FastFlow upstream requirements;
- ensure README and code agree;
- keep all fixes on `fastflow-1.0/npu-runtime`.

### Batch 8 — HX 370 real runtime validation

Status: pending hardware execution.

On the Ryzen AI 9 HX 370 host:

- verify firmware/driver/device;
- pull/build image;
- run `flm validate`;
- verify default model;
- start API;
- verify `/v1/models`;
- run chat completion;
- verify volume persistence;
- restart;
- verify graceful stop;
- observe NPU utilization.

### Batch 9 — LocalDevStack integration

Status: deferred until provider image is ready.

LocalDevStack behavior:

```text
compatible XDNA2 NPU -> llm-fastflow
NVIDIA GPU           -> llm-ollama
AMD ROCm GPU         -> llm-ollama
otherwise            -> llm-ollama CPU
```

No normal user-facing provider selector is required.

## 18. Definition of done

The provider is ready to integrate when:

1. plan is tracked on `fastflow-1.0/npu-runtime`;
2. current branch CI is fully green;
3. image builds against current stable FastFlowLM;
4. upstream asset SHA-256 is verified;
5. current Debian stable is resolved deterministically per build;
6. dynamic runtime libraries resolve completely;
7. `qwen3.5:9b` is baked and verified;
8. model data persists under `/models`;
9. Compose passes only the required XDNA2 device plus memlock;
10. API listens on container port 52625;
11. standalone host publication is loopback-only;
12. `/v1/models` healthcheck is present;
13. no privileged mode/Docker socket/kernel-driver install exists;
14. real NPU smoke procedure is reproducible;
15. Docker Hub/GHCR publication policy is validated;
16. PR #1 is the only active implementation PR for this work;
17. provider is ready for LocalDevStack automatic NPU selection.

## 19. Explicit non-goals

Do not add to this provider:

- CPU fallback;
- NVIDIA support;
- AMD ROCm GPU support;
- XDNA1 support;
- arm64 publication without upstream support;
- a second inference runtime;
- Ollama runtime logic;
- browser UI;
- LocalDevStack detection logic;
- privileged execution.

Those remain separate concerns.
