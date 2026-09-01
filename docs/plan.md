# Version 0.4 plan

This is the forward-looking work list for the next release. External examples
justify general structural rules; project paths, declaration names, and isolated
token sequences must never become formatter conditions.

Missing-rule coverage is release-blocking only for Lean's standard library and
Mathlib, leanfmt's first-class syntax-support targets. Missing rules in other
external projects are useful inventory, but block validation only when they
coincide with preservation, formatting, convergence, overflow, or build issues.

## Open issues

### Application continuation tails

Later arguments can inherit the tail of a preceding multiline argument instead
of returning to the application base. The same ownership gap can leave the
closing `]` of a broken `simp` or `rw` lemma list on its own line. Continuations
and collection closers should return to their structural owners.

### Command header flow

Declaration binders, short local macro headers, and scoped notation modifiers
can break at incidental parser-wrapper boundaries. A fitting command header such
as `local macro "name" : tactic =>` should remain one flow, and a modifier should
not become an orphan line above its command.

## Progress

### Continuation and header consistency

Stabilize application tails and tactic-list closers through existing application
and collection ownership. Validate the focused GraphQL and Mathlib examples
without changing compact application behavior.

### Header consistency and release gate

Align declaration binders, macro headers, and command modifiers through existing
annotated-declaration and signature flows. After focused validation, run the full
GraphQL, quantum, Hex, and Mathlib release gate and review the complete formatting
diff before release.

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
