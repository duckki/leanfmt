#!/usr/bin/env bash

set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  printf 'Usage: scripts/validate-release-projects.sh\n'
  exit 0
fi
if (($# != 0)); then
  printf 'For individual targets or partial runs, use scripts/validate-external-projects.sh.\n' >&2
  exit 2
fi

validator="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/validate-external-projects.sh"

export LAKE_ARTIFACT_CACHE="${LAKE_ARTIFACT_CACHE:-true}"
export LAKE_RESTORE_ARTIFACTS="${LAKE_RESTORE_ARTIFACTS:-true}"
export MATHLIB_NO_CACHE_ON_UPDATE="${MATHLIB_NO_CACHE_ON_UPDATE:-1}"

LEANFMT_VALIDATION_LINE_WIDTH=100 "$validator" --toolchain-tag --files '*.lean' \
  'mathlib=https://github.com/leanprover-community/mathlib4.git::Mathlib' \
  cslib=https://github.com/leanprover/cslib.git

LEANFMT_VALIDATION_LINE_WIDTH=100 "$validator" --shallow-ref refs/heads/main --files '*.lean' \
  flare-lean=https://github.com/duckki/flare-lean.git

env -u LEANFMT_VALIDATION_LINE_WIDTH "$validator" --shallow-ref refs/heads/main --files '*.lean' \
  graphql-lean=https://github.com/duckki/GraphQL.lean.git
