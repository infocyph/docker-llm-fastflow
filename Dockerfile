FROM debian:stable-slim

ARG FASTFLOWLM_VERSION=1.0.6
ARG FASTFLOWLM_SHA256=99f1032656b3dd8135675ca3be4e3aa4169e732ecd2d5fb886b24570b0a80851
ARG FASTFLOW_MODEL=qwen3.5:9b
ARG LLM_FASTFLOW_VERSION=dev

LABEL org.opencontainers.image.source="https://github.com/infocyph/docker-llm-fastflow"
LABEL org.opencontainers.image.description="AMD XDNA2 NPU local LLM runtime powered by FastFlowLM"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.authors="infocyph,abmmhasan"
LABEL org.opencontainers.image.version="${LLM_FASTFLOW_VERSION}"
LABEL io.infocyph.llm.default-model="${FASTFLOW_MODEL}"

ENV DEBIAN_FRONTEND=noninteractive \
    FASTFLOWLM_VERSION="${FASTFLOWLM_VERSION}" \
    LLM_FASTFLOW_VERSION="${LLM_FASTFLOW_VERSION}" \
    LLM_FASTFLOW_MODEL="${FASTFLOW_MODEL}" \
    FLM_MODEL_PATH="/models" \
    FLM_SERVE_PORT="52625" \
    FLM_HOST="0.0.0.0" \
    FLM_DISABLE_UPDATE_CHECK="1" \
    PATH="/opt/fastflowlm:${PATH}"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
        libdrm2 \
        libgomp1 \
        libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

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
    rm -f /tmp/fastflowlm-ldd.txt; \
    /opt/fastflowlm/flm version

# Bake the HX 370 default model so first startup is immediately usable and
# does not depend on a multi-gigabyte first-run download.
RUN set -eux; \
    /opt/fastflowlm/flm pull "$LLM_FASTFLOW_MODEL"; \
    /opt/fastflowlm/flm check "$LLM_FASTFLOW_MODEL"; \
    /opt/fastflowlm/flm list --filter installed | tee /tmp/fastflowlm-models.txt; \
    grep -Fiq "$LLM_FASTFLOW_MODEL" /tmp/fastflowlm-models.txt; \
    rm -f /tmp/fastflowlm-models.txt

COPY scripts/llm-fastflow /usr/local/bin/llm-fastflow
COPY scripts/lib /usr/local/lib/llm-fastflow/lib
COPY scripts/commands /usr/local/lib/llm-fastflow/commands

RUN chmod 0755 /usr/local/bin/llm-fastflow \
    && chmod -R a+rX /usr/local/lib/llm-fastflow

EXPOSE 52625

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
    CMD curl --connect-timeout 2 -fsS http://127.0.0.1:52625/v1/models >/dev/null || exit 1

STOPSIGNAL SIGTERM

ENTRYPOINT ["llm-fastflow"]
CMD ["serve"]
