# Version 0.4 plan

Rules must describe general syntax ownership. External paths and declaration
names are evidence for tests, never formatter conditions. Missing-rule coverage
is release-blocking only for Lean's standard library and Mathlib.

## Open Issues

### Large-project validation latency

Hex's slowest formatter batch varied from 145 to 326 seconds across equivalent
checkpoint runs. Mathlib batches were usually 18 to 42 seconds, with one at 89
seconds. Output and diagnostics are correct, but tail latency remains a
performance target.

## Progress

### Checkpoint 1: structural headers and peer continuations

Complete macro pattern regrouping, anonymous declaration-header consistency,
and peer application continuation ownership. The exact Mathlib `v4.33.0` gate
completed with all formatter diagnostics at zero and both post-format builds
passing.

### Checkpoint 2: application and suffix consistency

Complete focused coverage for the reviewed application, local declaration,
conditional, tactic suffix, and low-priority-pipe examples. Shared ownership now
uses the existing application and suffix mechanisms. The complete local gate,
GraphQL, quantum, and width-100 Hex validation passed; quantum produced no
formatting changes, and Hex's previously slow failing batch passed in 126
seconds. Focused Mathlib probes passed. The Mathlib checkpoint was unavailable
because this selector has no recorded baseline, so the final full gate will
establish it.

### Checkpoint 3: delimiters, command boundaries, and release gate

Complete delimiter-closer rebasing, command-sequence spacing, modified
declaration ownership, compact `match_expr` alternatives, structural `using`
continuations, and parser-safe `initialize` operands. The complete local gate,
GraphQL, quantum, and width-100 Hex validation passed; quantum produced no
formatting changes. The exact Mathlib `v4.33.0` baseline formatted 8,311 files
with every diagnostic at zero and passed both post-format builds. A subsequent
width-100 checkpoint covered all 84 formatter batches. After a focused
`initialize` correction at batch 74, its failing file and batches 74 through 84
were rerun cleanly.

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
complete validation because they are comparatively small. Hex and Mathlib use
width 100 and checkpoint mode during iteration, with complete builds reserved
for the release gate.

Mathlib validation uses exact `v4.33.0` commit
`db584cd6d46c92f209a44c0f1c829460d327499d`, formats only `Mathlib`, and uses
the Lake cache. The release gate recreates or resets the validation clone and
runs the clean, changed-module, and aggregate post-format builds. Later
formatter-only reviews may reuse that exact baseline when its revision,
toolchain, selector, and source manifest remain unchanged.
