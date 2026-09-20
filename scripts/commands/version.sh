#!/usr/bin/env bash

command_main() {
  printf 'llm-fastflow %s\n' "$VERSION"
  if [[ -x "$FLM_BIN" ]]; then
    "$FLM_BIN" version
  fi
}
