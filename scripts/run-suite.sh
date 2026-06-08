#!/usr/bin/env bash
# Run the vendored official test-suite against the library.
#   scripts/run-suite.sh                  -> check vs baseline (non-zero exit on regression)
#   scripts/run-suite.sh --update-baseline -> rewrite baseline from current passes
set -euo pipefail
cd "$(dirname "$0")/.."
eval "$(luarocks path --local)"
export LUA_PATH="./src/?.lua;./src/?/init.lua;./spec/?.lua;./spec/?/init.lua;${LUA_PATH:-};;"
exec luajit spec/support/suite_runner.lua "$@"
