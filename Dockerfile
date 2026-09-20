FROM debian:13-slim

ARG FASTFLOW_VERSION=1.0.6
ARG FASTFLOW_ASSET_URL=https://github.com/ROCm/FastFlowLM/releases/download/v${FASTFLOW_VERSION}/fastflowlm_${FASTFLOW_VERSION}_linux.tar.gz
ARG FASTFLOW_SHA256=99f1032656b3dd8135675ca3be4e3aa4169e732ecd2d5fb886b24570b0a80851
ARG LLM_FASTFLOW_VERSION=dev

LABEL org.opencontainers.image.source="https://github.com/infocyph/docker-llm-fastflow"
LABEL org.opencontainers.image.description="FastFlowLM provider runtime for AMD Ryzen AI XDNA2 NPUs"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.authors="infocyph,abmmhasan"
LABEL org.opencontainers.image.version="${LLM_FASTFLOW_VERSION}"

ENV LLM_FASTFLOW_VERSION="${LLM_FASTFLOW_VERSION}" \
    LLM_FASTFLOW_MODEL="qwen3.5:9b" \
    FLM_MODEL_PATH="/models" \
    FLM_SERVE_PORT="52625" \
    FLM_DISABLE_UPDATE_CHECK="1" \
    LLM_FASTFLOW_CONTEXT_LENGTH="" \
    LLM_FASTFLOW_QUEUE_LENGTH="10" \
    LLM_FASTFLOW_SOCKET_CONNECTIONS="10"

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      jq \
      libdrm2 \
      libgcc-s1 \
      libnuma1 \
      libstdc++6 \
      libudev1 \
      libuuid1; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    mkdir -p /opt/fastflowlm /models; \
    curl --fail --location --retry 5 --retry-delay 2 \
      "${FASTFLOW_ASSET_URL}" -o /tmp/fastflowlm.tar.gz; \
    printf '%s  %s\n' "${FASTFLOW_SHA256}" /tmp/fastflowlm.tar.gz | sha256sum -c -; \
    tar -xzf /tmp/fastflowlm.tar.gz -C /opt/fastflowlm; \
    rm -f /tmp/fastflowlm.tar.gz; \
    test -x /opt/fastflowlm/flm; \
    test -x /opt/fastflowlm/flm-real; \
    ln -s /opt/fastflowlm/flm /usr/local/bin/flm; \
    /opt/fastflowlm/flm version

COPY scripts/llm-fastflow /usr/local/bin/llm-fastflow
COPY scripts/entrypoint.sh /usr/local/bin/llm-fastflow-entrypoint

RUN chmod 0755 /usr/local/bin/llm-fastflow /usr/local/bin/llm-fastflow-entrypoint

VOLUME ["/models"]

EXPOSE 52625

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD-SHELL curl --connect-timeout 2 -fsS "http://127.0.0.1:${FLM_SERVE_PORT:-52625}/v1/models" >/dev/null || exit 1

STOPSIGNAL SIGTERM

ENTRYPOINT ["/usr/local/bin/llm-fastflow-entrypoint"]
