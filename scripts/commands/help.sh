#!/usr/bin/env bash

command_main() {
  cat <<'EOF'
llm-fastflow - FastFlowLM runtime wrapper for AMD XDNA2 NPUs

Usage:
  llm-fastflow <command> [arguments]

Runtime:
  serve [model] [args...]    Start the OpenAI-compatible server
  run [model] [args...]      Run a model interactively
  validate [args...]         Validate XDNA2/NPU runtime access

Models:
  models [args...]           List FastFlowLM models
  pull [model] [args...]     Download a model
  check [model] [args...]    Verify downloaded model files
  remove <model> [args...]   Remove a downloaded model

Low level:
  flm [args...]              Invoke FastFlowLM directly
  version                    Show wrapper and FastFlowLM versions
  help                       Show this help

Defaults:
  model: qwen3.5:9b
  API:   http://127.0.0.1:52625/v1
  store: /models
EOF
}
