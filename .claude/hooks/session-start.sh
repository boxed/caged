#!/bin/bash
# Installs the Elm toolchain (elm + elm-test) so `elm make` and `elm-test`
# work in Claude Code on the web sessions. This repo has no package.json —
# the compiler and test runner are installed globally via npm.
#
# NOTE: `elm make` / `elm-test` also need network access to
# package.elm-lang.org to resolve dependencies. That host is governed by the
# environment's egress policy; if builds still fail after this hook runs,
# allowlist package.elm-lang.org in the environment's network policy.
set -euo pipefail

# Only run in the remote (Claude Code on the web) environment.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Idempotent: skip if the toolchain is already on PATH.
if command -v elm >/dev/null 2>&1 && command -v elm-test >/dev/null 2>&1; then
  exit 0
fi

npm install -g elm elm-test
