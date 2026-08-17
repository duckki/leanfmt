# Version 0.4 plan

This is the forward-looking work list for the next release. External examples
justify general structural rules; project paths, declaration names, and isolated
token sequences must never become formatter conditions.

Missing-rule coverage is release-blocking only for Lean's standard library and
Mathlib, leanfmt's first-class syntax-support targets. Missing rules in other
external projects are useful inventory, but block validation only when they
coincide with preservation, formatting, convergence, overflow, or build issues.

## Open Issues

### Detached tactic bodies

Standalone `case ... =>` and parser-owned tactic suffixes such as `simp? ...
says` can leave their following tactic sequence outside the owner's structural
body. The same root cause appears in nested `next` bodies and parenthesized
elimination alternatives.

```lean
case branch =>
exact proof
```

### Conditional chain ownership

Multiline `else if` chains can split after `else`, and a wrapped `then` can
inherit its condition's incidental column instead of the conditional base.

```lean
else
  if condition then
    result
```

### Declaration continuation layout

Long declaration binders and continuation tokens can retain source-column
alignment or remain over width instead of using the declaration's structural
continuation indentation.

### Non-proof child rebasing

Preserved structure-field values and non-application wrappers can retain an
incidental source column after their surrounding layout changes. Parser-described
tactic applications now use the tactic and application structural bases.

```lean
field :=
          private fun x => value
```

### Delimiter and suffix attachment

Closing notation such as `:)`, a short operand after `<|`, or a proof argument
after an application head can detach even when the complete suffix fits.

```lean
function
<| shortOperand
```

## Progress

### Checkpoint 19: detached tactic bodies

Standalone tactic alternatives and parser-owned tactic suffixes own and indent
their following tactic sequences without renderer-specific syntax handling.

### Checkpoint 20: conditional chain ownership

`else if`, multiline `then`, and their branch bodies share one conditional base
without source-column inheritance or renderer token checks.

### Checkpoint 21: non-proof child rebasing

Remaining structure-field values and non-application wrappers use their logical
layout base without syntax-specific renderer behavior.

### Checkpoint 22: declaration continuation layout

Long binder groups and breakable signatures use the declaration's structural
continuation indentation and expose all required break opportunities.

### Checkpoint 23: delimiter and suffix attachment

Short low-priority operands, closing notation, and structural application
arguments remain attached whenever the complete group fits.

### Checkpoint 24: release validation

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
