# Version 0.4 plan

Rules must describe general syntax ownership. External paths and declaration
names are evidence for tests, never formatter conditions. Missing-rule coverage
is release-blocking only for Lean's standard library and Mathlib.

## Open Issues

### Application continuation ownership

Later arguments can inherit an incidental function-name column after a tactic
suffix or a multiline peer:

```lean
simpa
  using! longFunctionName
          firstArgument secondArgument
```

Continuation runs should return to the application's structural base.

### Suffix and separator attachment

Fitting suffixes can detach from the header they complete, including `then`,
`:= do`, tactic `says`, and low-priority pipes:

```lean
discharger : TacticM Unit :=
  do
```

Existing suffix ownership should keep these tokens with their natural header
without adding token-specific renderer behavior.

### Delimiter ownership

Parenthesized tactic bodies and generated quotations can leave an opening or
closing parenthesis on a line by itself:

```lean
induction value with
  (
    ...
  )
```

Delimited trees should retain their delimiters while their contents use the
surrounding structural base.

### Command boundary spacing

When a compact macro becomes multiline, the following declaration can lose the
blank line that separates commands. Command spacing should depend on command
boundaries, not on whether a command happened to fit before formatting.

### Large-project validation latency

Hex's slowest formatter batch is about 298 seconds. The output is correct, but
the batch is close to the historical timeout and remains a performance target.

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

Add focused tests for detached parentheses and command spacing. Fix the shared
delimiter and command-sequence ownership, review complete external diffs, then
run the full GraphQL, quantum, Hex, and exact Mathlib `v4.33.0` release gate.

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
the Lake cache. The final gate recreates or resets the validation clone and runs
the clean, changed-module, and aggregate post-format builds.
