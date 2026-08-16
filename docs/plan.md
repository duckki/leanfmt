# Version 0.4 plan

This is the forward-looking work list for the next release. External examples
justify general structural rules; project paths, declaration names, and isolated
token sequences must never become formatter conditions.

Missing-rule coverage is release-blocking only for Lean's standard library and
Mathlib, leanfmt's first-class syntax-support targets. Missing rules in other
external projects are useful inventory, but block validation only when they
coincide with preservation, formatting, convergence, overflow, or build issues.

## Open Issues

### Proof body rebasing

Some preserved proof bodies still inherit incidental source columns after
constructs such as `from by`, `else by`, and nested `<| by` applications.

```lean
suffices condition from by
            exact proof
```

### Arm body indentation

A preserved body after a multiline `match` arm can align with the arm marker
instead of being indented beneath it.

```lean
match i with
  | 0 =>
  exact result
```

### Declaration continuation layout

Long declaration binders and continuation tokens can retain source-column
alignment or remain over width instead of using the declaration's structural
continuation indentation.

### Non-proof child rebasing

Preserved structure-field values and wrapped tactic arguments can retain an
incidental source column after their surrounding layout changes.

```lean
field :=
          private fun x => value
```

### Validation rebuild cost

Mathlib's changed-source validation rebuilds add substantial overhead before the
required aggregate post-format build. Preserve equivalent coverage while
reducing redundant rebuild work.

## Progress

### Checkpoint 17: protected proof and arm bodies

Preserved proofs and bodies after multiline `match` and `cases` arms apply their
existing structural indentation consistently across equivalent owners.

### Checkpoint 18: non-proof child rebasing

Structure-field values and wrapped tactic arguments use their logical layout
base without syntax-specific renderer behavior.

### Checkpoint 19: declaration continuation layout

Long binder groups and breakable signatures use the declaration's structural
continuation indentation and expose all required break opportunities.

### Checkpoint 20: validation efficiency

External validation retains complete formatter and post-format build coverage
while avoiding redundant Mathlib rebuild work.

### Checkpoint 21: release validation

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
