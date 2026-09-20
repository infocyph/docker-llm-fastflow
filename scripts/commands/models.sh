#!/usr/bin/env bash

command_main() {
  if [[ $# -eq 0 ]]; then
    exec_flm list --filter installed
  fi
  exec_flm list "$@"
}
