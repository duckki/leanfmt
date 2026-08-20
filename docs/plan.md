# Version 0.4 plan

This is the forward-looking work list for the next release. External examples
justify general structural rules; project paths, declaration names, and isolated
token sequences must never become formatter conditions.

Missing-rule coverage is release-blocking only for Lean's standard library and
Mathlib, leanfmt's first-class syntax-support targets. Missing rules in other
external projects are useful inventory, but block validation only when they
coincide with preservation, formatting, convergence, overflow, or build issues.

## Progress

### Checkpoint 24: release validation

The light gate is complete for the release candidate: the local suite and fresh
GraphQL, quantum, Hex, and Mathlib formatter checkpoints pass with no exception,
idempotency, or material performance regression. The next checkpoint reruns the
complete external builds, reviews every final formatting delta, and accepts the
release only with no logical-layout blocker.

## Validation standard

Every checkpoint runs:

```sh
lake build
lake test
make lint
lake exe fmt-test --update-fixture Tests/Fixtures/*/*.leanfmt
lake exe fmt --check-exception --check-idempotent -r LeanFmt
lake build
lake test
lake exe fmt-test --update-fixture --check Tests/Fixtures/*/*.leanfmt
lake exe fmt --check --check-exception --check-idempotent -r LeanFmt
git diff --check
```

Generated fixture and self-format changes require visual review. External runs
use automatic worker counts; do not pass `--jobs`. GraphQL and quantum run their
complete validation because they are comparatively small. Hex and Mathlib run at
width 100 through `--checkpoint`, which reuses the exact revision, toolchain,
selected-source, ownership, and runtime baseline from their latest successful
complete validation. The checkpoint gate still formats every selected source with
exception and idempotency checks, but deliberately skips target-project builds.
Missing rules are hard failures only for Lean's standard library and Mathlib.

Mathlib validation uses a shallow clone of exact `v4.33.0` commit
`db584cd6d46c92f209a44c0f1c829460d327499d`, formats only `Mathlib` at width
100, and downloads the Lake cache. Checkpoints reuse its validated clone with
`--checkpoint`; Checkpoint 24 recreates the clone and runs the complete pre-format,
changed-module, and aggregate post-format builds. Hex follows the same split between
light checkpoints and the final complete release validation.
