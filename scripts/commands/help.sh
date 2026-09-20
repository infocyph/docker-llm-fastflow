#!/usr/bin/env bash

command_main() {
  cat <<'EOF'
llm-fastflow - FastFlowLM runtime + developer CLI for AMD XDNA2 NPUs

Usage:
  llm-fastflow <command> [arguments]

Developer:
  ask [-m model] <prompt>               Ask once
  chat [model]                          Start interactive chat
  prompt [options] <prompt>             Generic prompt with files/images/PDF context
  code [options] <task>                 Generate or improve code
  review [options] [file...] [focus]    Review code from files/stdin
  json [options] <prompt>               Request and validate JSON output
  ai-commit [options]                   Generate commit message from a Git diff

Runtime:
  serve [model] [args...]               Start the OpenAI-compatible server
  run [model] [args...]                 Run a model interactively
  validate [args...]                    Validate XDNA2/NPU runtime access

Models:
  models [args...]                      List FastFlowLM models
  pull [model] [args...]                Download a model
  check [model] [args...]               Verify downloaded model files
  remove <model> [args...]              Remove a downloaded model

Low level:
  flm [args...]                         Invoke FastFlowLM directly
  api <path> [curl-args...]             Raw FastFlow HTTP API call
  version                               Show wrapper and FastFlowLM versions
  help                                  Show this help

Common options:
  -m, --model <model>                   Override model
  -f, --file <path>                     Add text file context

prompt attachments:
  --attach <path>                       Auto-detect text/image/PDF
  --image <path>                        Add PNG/JPEG image
  --pdf <path>                          Extract PDF text
  --pdf-vision <path>                   Render PDF pages as PNG vision input

Defaults:
  model: qwen3.5:9b
  API:   http://127.0.0.1:52625/v1
  store: /models
EOF
}
