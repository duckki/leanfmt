# Version 0.4 plan

This is the forward-looking work list for the next release. External examples
justify general structural rules; project paths, declaration names, and isolated
token sequences must never become formatter conditions.

Missing-rule coverage is release-blocking only for Lean's standard library and
Mathlib, leanfmt's first-class syntax-support targets. Missing rules in other
external projects are useful inventory, but block validation only when they
coincide with preservation, formatting, convergence, overflow, or build issues.

## Open issues

### Parser-owned suffixes and low-priority pipes

Fitting suffixes such as `with`, `where`, `:= by`, `=> do`, and tactic argument
heads can detach from their owner. A broken `<|` application can also leave `<|`
on a line by itself even though neither adjacent boundary may break in that
shape. Anonymous `have :` headers expose the same ownership gap.

### Compact and protected layouts

Fitting semicolon tactic sequences, `if` expressions, proof applications, and
source-attached attributes can expand unnecessarily. Protected source-layout
islands such as braced `all_goals` blocks must retain their relative shape while
the surrounding base indentation changes.

## Progress

### Checkpoint 2: suffix and operator ownership

Add focused regressions for parser-owned trailing clauses, tactic proof/value
suffixes, anonymous `have` headers, and standalone `<|`. Generalize syntax-tree
ownership and existing suffix behavior so line-break rules only describe legal
boundaries. Validate locally and against the affected Mathlib files, then commit.

### Checkpoint 3: compact and protected consistency

Add focused regressions for fitting semicolon sequences, conditionals,
applications, attributes, and protected braced tactic blocks. Reconcile fit
selection with the existing compact-layout and original-island policies without
weakening width or preservation diagnostics. Run the full local gate and light
GraphQL, quantum, Hex, and Mathlib checkpoint validations, review performance and
formatting changes, then commit.

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
