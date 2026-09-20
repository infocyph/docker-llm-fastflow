# docker-llm-fastflow — XDNA2 NPU Runtime Plan

Status: active implementation plan  
Target: first production-ready FastFlowLM provider image for Infocyph  
Primary hardware target: AMD Ryzen AI 9 HX 370 / Strix Point / XDNA2  
Branch: `fastflow-1.0/xdna2-runtime`

## 1. Goal

Build `infocyph/docker-llm-fastflow` as the FastFlowLM sibling of
`infocyph/docker-llm-ollama`.

The responsibility split is:

```text
docker-llm-fastflow -> AMD XDNA2 NPU / FastFlowLM
docker-llm-ollama  -> CPU / NVIDIA GPU / AMD ROCm GPU / Ollama
```

This repository owns only the FastFlowLM provider/runtime image and its standalone
Docker/Compose contract. LocalDevStack provider selection and automatic NPU detection
will be integrated only after this image is stable and published.

## 2. Primary hardware contract

The first supported runtime target is Linux/amd64 on AMD XDNA2 systems.

Primary validation target:

```text
AMD Ryzen AI 9 HX 370
Codename: Strix Point
NPU: XDNA2
NPU throughput: up to 50 TOPS
Device: /dev/accel/accel0
```

FastFlowLM currently supports XDNA2 Ryzen AI families including Strix Point. XDNA1 is
not part of this image contract.

Host responsibilities:

- supported XDNA2 hardware;
- current NPU firmware;
- `amdxdna` kernel driver;
- working `/dev/accel/accel0`;
- host kernel/driver combination supported by FastFlowLM;
- Docker with device passthrough.

Container responsibilities:

- FastFlowLM userspace runtime;
- bundled XRT/XDNA userspace libraries from the official portable release;
- provider API;
- model storage;
- health/runtime diagnostics;
- NPU memlock contract;
- no kernel driver installation.

Do not install `amdxdna-dkms` inside the container.

## 3. FastFlowLM source policy

Use the official ROCm/FastFlowLM stable release artifacts.

Current upstream stable baseline at plan creation:

```text
FastFlowLM: v1.0.6
Portable asset:
fastflowlm_1.0.6_linux.tar.gz
sha256:
99f1032656b3dd8135675ca3be4e3aa4169e732ecd2d5fb886b24570b0a80851
```

The portable archive is preferred over rebuilding FastFlowLM from source because it:

- is an official release artifact;
- bundles XRT/XDNA userspace libraries;
- includes the FLM wrapper, runtime binary, model catalog and xclbins;
- is much smaller and faster to consume than rebuilding the native stack;
- keeps our Docker image focused on packaging/integration rather than duplicating FLM CI.

Release publication must resolve the latest stable upstream FastFlowLM release at build
time, verify the release asset digest from GitHub, then pass the resolved version,
download URL and SHA256 into the Docker build.

The repository may keep the current stable version as the direct/local-build fallback,
but moving published `:latest` images must be refreshed from the newest stable upstream
release.

Prereleases must never move the stable `:latest` tag.

## 4. Base image

Use:

```text
debian:13-slim
```

Do not use Alpine for this provider.

Reason:

FastFlowLM's portable Linux package and its bundled XRT/XDNA userspace stack are
glibc-based native binaries. Using Alpine/musl would add compatibility complexity for
no useful benefit.

The project-wide Alpine-first rule therefore does not apply to this image family because
there is no suitable Alpine-native FastFlow/XRT runtime.

## 5. Default model decision

### Requested target

The desired product-level default was:

```text
qwen3:14b
```

FastFlowLM does not currently publish a `qwen3:14b` NPU2 model.

Do not fabricate or alias `qwen3:14b`.

### First runnable default

Use:

```text
qwen3.5:9b
```

for the first FastFlow image.

Why this is the best practical default for Ryzen AI 9 HX 370:

- newer Qwen generation than the available Qwen3 8B model;
- NPU2 format;
- Q4_K high-precision FastFlow weights;
- reasoning support;
- tool-calling support;
- vision support;
- approximately 8.7 GB model footprint;
- 32k default context;
- materially safer on common 32 GB HX 370 systems than the ~22.1 GB
  `qwen3.6-moe:35b-a3b` model.

Current FastFlow benchmark reference for Qwen3.5 9B shows roughly:

```text
1k context decode:  ~9.9 tok/s
32k context decode: ~7.24 tok/s
1k prefill:          ~249 tok/s
32k prefill:         ~417 tok/s
```

The public benchmark system is Ryzen AI 7 350, not HX 370, so these are a reference,
not a promise for HX 370.

### Future Qwen3 14B rule

Keep the default model centralized in one explicit setting:

```text
LLM_FASTFLOW_MODEL=qwen3.5:9b
```

When FastFlowLM publishes a supported `qwen3:14b` NPU2 artifact, changing the product
default must require only:

1. model-default update;
2. runtime compatibility test update;
3. documentation update;
4. release validation.

No image architecture redesign should be required.

## 6. Model persistence

Use:

```text
FLM_MODEL_PATH=/models
```

with a named volume:

```text
llm-fastflow-data -> /models
```

Models must survive container recreation and image upgrades.

Do not mix this storage with Ollama's `/root/.ollama` store.

The first container start may download the default FLM model when it is not already
present. Do not bake a multi-gigabyte NPU model into the base image in the first release.

Reasons:

- keeps provider image small;
- model weights change independently from provider image;
- FLM may require weight refreshes across runtime releases;
- persistent model state is the correct lifecycle boundary;
- scheduled image refreshes should not republish ~9 GB of model data.

A future optional model-bearing image can be considered separately if offline-first
startup becomes a requirement.

## 7. Runtime API contract

FastFlowLM server:

```text
container port: 52625
OpenAI base:    http://llm-fastflow:52625/v1
health probe:   GET /v1/models
```

The container must start FastFlowLM with:

```text
--host 0.0.0.0
--port 52625
```

because upstream defaults to `127.0.0.1`, which is not reachable by other containers.

CORS should be disabled by default inside the provider container:

```text
--cors 0
```

Higher-level routing belongs to LocalDevStack/Nginx.

Standalone Compose should publish only:

```text
127.0.0.1:52625:52625
```

No wildcard host binding by default.

## 8. NPU Docker contract

Standalone Compose must pass:

```yaml
devices:
  - /dev/accel/accel0:/dev/accel/accel0

ulimits:
  memlock:
    soft: -1
    hard: -1
```

The image must not require:

- Docker socket access;
- `--privileged`;
- `/dev/kfd`;
- `/dev/dri`;
- NVIDIA runtime;
- host repository mounts.

If FastFlow runtime testing proves an additional device or capability is strictly
required, add only the narrowest required permission and document why.

## 9. Environment contract

Initial provider-facing values:

```text
LLM_FASTFLOW_MODEL=qwen3.5:9b
FLM_MODEL_PATH=/models
FLM_SERVE_PORT=52625
FLM_DISABLE_UPDATE_CHECK=1
LLM_FASTFLOW_VERSION=<release/build version>
```

Optional tuning values may include:

```text
LLM_FASTFLOW_CONTEXT_LENGTH=
LLM_FASTFLOW_QUEUE_LENGTH=10
LLM_FASTFLOW_SOCKET_CONNECTIONS=10
```

Do not expose knobs that FastFlowLM does not actually consume.

## 10. CLI contract

Provide a thin bundled wrapper:

```text
llm-fastflow
```

The wrapper should remain provider-focused and should not own Docker lifecycle.

Initial commands:

```text
help
version
validate
models
pull
remove
check
run
serve
bench
flm
```

Useful aliases:

```text
models -> flm list
rm     -> flm remove
```

The wrapper may add convenience API commands later, but should not reimplement
FastFlowLM's model/runtime logic.

No commands such as:

```text
start
stop
restart
logs
install
uninstall
```

belong inside the image CLI.

## 11. Dockerfile contract

The Dockerfile should:

1. use `debian:13-slim`;
2. install only required runtime utilities such as CA certs/curl/jq;
3. download the resolved official FastFlow portable archive;
4. verify its SHA256 before extraction;
5. install it under `/opt/fastflowlm`;
6. expose `flm` on PATH;
7. add the thin `llm-fastflow` wrapper;
8. add an entrypoint that launches the configured default model;
9. expose port 52625;
10. add an HTTP healthcheck against `/v1/models`;
11. use `STOPSIGNAL SIGTERM`;
12. contain no kernel-driver installation;
13. contain no Docker socket integration.

## 12. Entrypoint behavior

Default container startup:

```text
flm serve $LLM_FASTFLOW_MODEL
  --host 0.0.0.0
  --port $FLM_SERVE_PORT
  --cors 0
```

If `LLM_FASTFLOW_CONTEXT_LENGTH` is set, append `--ctx-len`.

If queue/socket settings are set, append their matching supported flags.

The entrypoint must preserve explicit user commands.

Examples:

```bash
docker run ... infocyph/llm-fastflow:latest
docker run ... infocyph/llm-fastflow:latest validate
docker run ... infocyph/llm-fastflow:latest list --json
```

## 13. Compose contract

Repository root:

```text
compose.yml
```

Service key:

```text
llm-fastflow
```

No fixed `container_name`.

Named model volume:

```text
llm-fastflow-data
```

Standalone defaults:

- NPU device mapped;
- unlimited memlock;
- loopback-only port;
- restart unless-stopped;
- persistent model volume;
- default model env;
- update checks disabled.

An optional workspace overlay can be added only if a real provider command requires
direct file access. It is not needed for the initial server/provider runtime.

## 14. Image publication

Publish to:

```text
docker.io/infocyph/llm-fastflow
ghcr.io/infocyph/llm-fastflow
```

Tags:

```text
latest
<immutable project release>
```

Platform:

```text
linux/amd64
```

Do not claim arm64.

Publication workflow must:

- resolve latest stable project release source;
- resolve latest stable FastFlowLM upstream release;
- reject draft upstream releases;
- prevent prerelease upstream sources from silently moving stable latest;
- retrieve official portable asset URL and digest;
- build one validated candidate;
- include BuildKit provenance;
- include SBOM;
- publish to Docker Hub and GHCR;
- verify registry digests after push;
- verify linux/amd64 platform;
- keep immutable release tags immutable.

## 15. CI strategy

Normal GitHub-hosted CI has no AMD XDNA2 NPU.

Therefore split tests into two classes.

### Normal CI

Must validate:

- shell syntax/ShellCheck;
- Dockerfile structure;
- Compose rendering;
- device + memlock contract;
- upstream artifact resolution;
- SHA256 verification logic;
- image build;
- FLM binary version/help/list behavior that does not require NPU execution;
- CLI wrapper;
- entrypoint argument assembly;
- OpenAI port/health configuration;
- security boundaries;
- publication policy.

### NPU runtime gate

A real XDNA2 machine is required to validate:

- `/dev/accel/accel0`;
- `flm validate`;
- XRT device access;
- `qwen3.5:9b` pull;
- server startup;
- `/v1/models`;
- non-streaming chat completion;
- streaming completion;
- reasoning/tool-call path where practical;
- clean SIGTERM shutdown;
- persistence across container recreation.

Until a self-hosted NPU runner exists, provide a manually runnable runtime-smoke script
that can be executed directly on the HX 370 workstation.

Do not pretend NPU inference is validated on a normal GitHub runner.

## 16. Security/trust boundaries

The image must default to:

- local-only standalone host publication;
- no authentication claim;
- no Docker socket;
- no privileged mode;
- no project/workspace mount;
- no telemetry layer added by Infocyph;
- FastFlow update checks disabled;
- only the required NPU device passed;
- model downloads performed by FastFlowLM/Hugging Face as explicitly required.

LocalDevStack/Nginx will own any future externally reachable route.

## 17. Documentation requirements

README must include:

- what the image is;
- HX 370/XDNA2 target;
- host requirements;
- unsupported XDNA1 note;
- default model;
- why Qwen3.5 9B is used instead of requested Qwen3 14B;
- Docker Compose quick start;
- model persistence;
- first-start model download behavior;
- OpenAI API examples;
- direct `flm` and `llm-fastflow` CLI examples;
- runtime validation;
- troubleshooting for device, firmware, XRT and memlock;
- LocalDevStack integration boundary;
- source/upstream licensing acknowledgment.

Include the upstream attribution requested by FastFlowLM:

```text
Powered by FastFlowLM
```

## 18. Implementation batches

### Batch 1 — repository foundation

- license;
- gitignore/dockerignore;
- plan;
- base README;
- Dockerfile skeleton;
- Compose contract;
- CLI/entrypoint skeleton;
- static CI.

Exit condition:

- repository has a coherent provider contract;
- Compose renders;
- Dockerfile passes structural validation;
- shell/static tests pass.

### Batch 2 — official FastFlow portable runtime

- consume official portable tarball;
- verify SHA256;
- install under `/opt/fastflowlm`;
- verify `flm` binary/version/help;
- lock Debian/glibc runtime dependencies;
- validate no unnecessary native build toolchain remains.

Exit condition:

- image builds on GitHub-hosted amd64;
- `flm help` and non-NPU metadata commands work from the image.

### Batch 3 — model/runtime wrapper

- default `qwen3.5:9b`;
- model path/volume;
- server entrypoint;
- host 0.0.0.0;
- CORS off;
- context/queue/socket settings;
- `llm-fastflow` command wrapper.

Exit condition:

- startup command is deterministic;
- explicit commands bypass default server startup cleanly.

### Batch 4 — NPU Compose hardening

- `/dev/accel/accel0`;
- memlock unlimited;
- loopback port publication;
- diagnostics;
- clear actionable failures when NPU device is absent.

Exit condition:

- contract is minimal and does not require privileged mode.

### Batch 5 — provider API + health

- `/v1/models` healthcheck;
- OpenAI-compatible server docs/tests;
- non-NPU fake/static API contract where possible;
- runtime smoke script for real HX 370.

Exit condition:

- real NPU smoke procedure is reproducible.

### Batch 6 — release automation

- project releases;
- Docker Hub + GHCR;
- latest stable upstream resolver;
- GitHub asset SHA256 verification;
- immutable release tags;
- moving `latest`;
- provenance/SBOM;
- weekly upstream refresh.

Exit condition:

- published image is reproducible and registry-verifiable.

### Batch 7 — HX 370 runtime validation

Run on the Ryzen AI 9 HX 370 host:

- host driver/firmware/device checks;
- image pull;
- `flm validate`;
- model pull;
- server health;
- OpenAI chat;
- stream;
- persistence;
- restart;
- termination;
- resource observation.

Exit condition:

- NPU inference is proven inside Docker.

### Batch 8 — LocalDevStack integration preparation

Only after the provider image is ready:

- document stable service/API contract;
- define LocalDevStack NPU detection contract;
- NPU wins automatic runtime selection when compatible;
- `llm-fastflow` selected for NPU;
- `llm-ollama` retained for CPU/NVIDIA/AMD ROCm;
- no normal user-facing provider selector.

This batch belongs primarily in LocalDevStack and is not part of the first
`docker-llm-fastflow` release implementation.

## 19. Definition of done

The first `docker-llm-fastflow` release is ready when:

1. the image builds from the verified official FastFlow stable portable release;
2. it targets linux/amd64 and XDNA2 only;
3. the container requires only the NPU device and required memlock setting;
4. `qwen3.5:9b` is the runnable default;
5. model data persists outside the container;
6. server listens on 0.0.0.0:52625 inside Docker;
7. standalone exposure is loopback-only;
8. `/v1/models` health works;
9. OpenAI-compatible chat works on a real HX 370;
10. no Docker socket or privileged mode is required;
11. CLI and Compose contracts are tested;
12. Docker Hub and GHCR publication are digest-verified;
13. docs describe the real upstream constraints;
14. LocalDevStack can consume the provider without depending on repository internals.

## 20. Explicit non-goals for the first release

Do not add yet:

- CPU fallback inside this image;
- NVIDIA support;
- ROCm GPU support;
- XDNA1 support;
- arm64 publication;
- a second inference runtime;
- Ollama compatibility shims beyond what FastFlow itself provides;
- automatic LocalDevStack selection;
- browser UI;
- baked multi-gigabyte default model;
- privileged Docker execution.

Those belong elsewhere or require separate evidence.
