ARG FASTFLOW_BASE_IMAGE=debian:stable-slim
FROM ${FASTFLOW_BASE_IMAGE} AS fastflow-base

ARG FASTFLOWLM_VERSION=1.0.6
ARG FASTFLOWLM_SHA256=99f1032656b3dd8135675ca3be4e3aa4169e732ecd2d5fb886b24570b0a80851
ARG DEBIAN_FRONTEND=noninteractive

# OS dependencies are independent from FastFlow/model/image-version inputs.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        jq \
        poppler-utils \
        libdrm2 \
        libgomp1 \
        libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

# Official portable FastFlow runtime. This layer changes only when the resolved
# upstream FastFlow release/digest changes.
RUN set -eux; \
    archive="/tmp/fastflowlm.tar.gz"; \
    curl -fL --retry 5 --retry-delay 2 \
      "https://github.com/ROCm/FastFlowLM/releases/download/v${FASTFLOWLM_VERSION}/fastflowlm_${FASTFLOWLM_VERSION}_linux.tar.gz" \
      -o "$archive"; \
    echo "${FASTFLOWLM_SHA256}  $archive" | sha256sum -c -; \
    mkdir -p /opt/fastflowlm /models; \
    tar -xzf "$archive" -C /opt/fastflowlm; \
    rm -f "$archive"; \
    test -x /opt/fastflowlm/flm; \
    test -x /opt/fastflowlm/flm-real; \
    ldd /opt/fastflowlm/flm-real | tee /tmp/fastflowlm-ldd.txt; \
    ! grep -q 'not found' /tmp/fastflowlm-ldd.txt; \
    for lib in libxrt_core.so.2 libxrt_coreutil.so.2 libxrt_driver_xdna.so.2; do \
      test -e "/opt/fastflowlm/lib/$lib"; \
      ldd "/opt/fastflowlm/lib/$lib" | tee -a /tmp/fastflowlm-ldd.txt; \
    done; \
    ! grep -q 'not found' /tmp/fastflowlm-ldd.txt; \
    rm -f /tmp/fastflowlm-ldd.txt; \
    FLM_DISABLE_UPDATE_CHECK=1 /opt/fastflowlm/flm version

# The model stage is deliberately independent from wrapper/image-version changes.
FROM fastflow-base AS fastflow-model

ARG FASTFLOW_MODEL=qwen3.5:9b

RUN set -eux; \
    FLM_MODEL_PATH=/models FLM_DISABLE_UPDATE_CHECK=1 \
      /opt/fastflowlm/flm pull "${FASTFLOW_MODEL}"; \
    FLM_MODEL_PATH=/models FLM_DISABLE_UPDATE_CHECK=1 \
      /opt/fastflowlm/flm check "${FASTFLOW_MODEL}"; \
    FLM_MODEL_PATH=/models FLM_DISABLE_UPDATE_CHECK=1 \
      /opt/fastflowlm/flm list --filter installed | tee /tmp/fastflowlm-models.txt; \
    grep -Fiq "${FASTFLOW_MODEL}" /tmp/fastflowlm-models.txt; \
    rm -f /tmp/fastflowlm-models.txt

# Lightweight runtime stage used by hardware-independent CI smoke tests.
FROM fastflow-base AS fastflow-runtime

ARG FASTFLOW_MODEL=qwen3.5:9b
ARG LLM_FASTFLOW_VERSION=dev

COPY scripts/llm-fastflow /usr/local/bin/llm-fastflow
COPY scripts/lib /usr/local/lib/llm-fastflow/lib
COPY scripts/commands /usr/local/lib/llm-fastflow/commands
COPY scripts/prompts /usr/local/lib/llm-fastflow/prompts

RUN chmod 0755 /usr/local/bin/llm-fastflow \
    && chmod -R a+rX /usr/local/lib/llm-fastflow

ENV FASTFLOWLM_VERSION="${FASTFLOWLM_VERSION}" \
    LLM_FASTFLOW_VERSION="${LLM_FASTFLOW_VERSION}" \
    LLM_FASTFLOW_MODEL="${FASTFLOW_MODEL}" \
    FLM_MODEL_PATH="/models" \
    FLM_SERVE_PORT="52625" \
    FLM_HOST="0.0.0.0" \
    FLM_CORS="0" \
    FLM_DISABLE_UPDATE_CHECK="1" \
    PATH="/opt/fastflowlm:${PATH}"

LABEL org.opencontainers.image.source="https://github.com/infocyph/docker-llm-fastflow" \
      org.opencontainers.image.description="AMD XDNA2 NPU local LLM runtime powered by FastFlowLM" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.authors="infocyph,abmmhasan" \
      org.opencontainers.image.version="${LLM_FASTFLOW_VERSION}" \
      io.infocyph.llm.default-model="${FASTFLOW_MODEL}"

EXPOSE 52625

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
    CMD curl --connect-timeout 2 -fsS "http://127.0.0.1:${FLM_SERVE_PORT:-52625}/v1/models" >/dev/null || exit 1

STOPSIGNAL SIGINT

ENTRYPOINT ["llm-fastflow"]
CMD ["serve"]

# Production image: same tested runtime plus the baked HX 370 default model.
FROM fastflow-runtime AS final

COPY --from=fastflow-model /models /models
