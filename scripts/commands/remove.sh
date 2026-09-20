#!/usr/bin/env bash

command_main() {
  [[ $# -gt 0 ]] || die "remove requires a model"
  exec_flm remove "$@"
}
