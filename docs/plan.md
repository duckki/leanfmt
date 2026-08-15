# Version 0.4 plan

This is the forward-looking work list for the next release. External examples
justify general structural rules; project paths, declaration names, and isolated
token sequences must never become formatter conditions.

Missing-rule coverage is release-blocking only for Lean's standard library and
Mathlib, leanfmt's first-class syntax-support targets. Missing rules in other
external projects are useful inventory, but block validation only when they
coincide with preservation, formatting, convergence, overflow, or build issues.

## Open Issues

### External validator project environments

```text
import all HexBerlekamp.DelayedKernel
unknown module prefix 'HexLLLBench'
external declaration 'MD4Lean.parse' has no code
```

Formatting an imported source invalidates `.olean` files needed by later files,
including later files in the same formatter invocation. Hex also has bench-only
module roots outside its default environment and native parser or external
symbols, such as `MD4Lean.parse` and `Hex.ZMod64.inv`, that an externally built
formatter executable does not link. The validator needs a target-project-aware
execution path and a dependency-safe artifact policy. These are infrastructure
failures, not missing formatting rules in third-party syntax.

## Progress

### Checkpoint 14: external validation environments

The validator can run against project-native parser extensions and preserve
usable imported artifacts while formatting source files. It discovers all
requested module roots, builds or runs the formatter in the target project when
native parser code requires it, and rebuilds invalidated dependencies at safe
boundaries. Target-toolchain fallback remains automatic, and the project-aware
path does not penalize ordinary Mathlib-style validation.

### Checkpoint 15: release validation

The complete local gate and fresh GraphQL, quantum, Hex, and Mathlib validations
pass. Every formatting delta is reviewed, timings show no material regression,
and the release has no exception or logical-layout blocker.

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
use automatic worker counts; do not pass `--jobs`. Hex runs at width 100 before
Mathlib and must pass every formatter batch and its complete post-format build,
apart from informational missing-rule reports. Missing rules are hard failures
only for Lean's standard library and Mathlib.

Mathlib validation uses a shallow clone of exact `v4.33.0` commit
`db584cd6d46c92f209a44c0f1c829460d327499d`, formats only `Mathlib` at width
100, downloads the Lake cache, and always runs the complete post-format build.
