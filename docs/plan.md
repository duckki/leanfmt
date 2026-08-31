# Version 0.4 plan

This is the forward-looking work list for the next release. External examples
justify general structural rules; project paths, declaration names, and isolated
token sequences must never become formatter conditions.

Missing-rule coverage is release-blocking only for Lean's standard library and
Mathlib, leanfmt's first-class syntax-support targets. Missing rules in other
external projects are useful inventory, but block validation only when they
coincide with preservation, formatting, convergence, overflow, or build issues.

## Open issues

### Incidental continuation columns

Nested applications, named arguments, infix operands, and closing delimiters can
inherit a far-right token column instead of a stable structural base. This
produces staircases such as:

```lean
outer (inner longArgument
                         shortArgument
                           )
```

The same root shape can displace a tiny second infix operand or the first row of
a `calc` block while neighboring rows use the expected base.

### Detached suffix bodies

Some suffix-like owners can be stranded on a line before their body. Reviewed
examples include a refutable fallback `|`, low-priority `<|`, `suffices ... from`,
and extension syntax such as `says`:

```lean
let some value := source
|
  fallback
```

Movable code should stay with its suffix when it fits; a structural break should
otherwise establish one body base rather than inherit the suffix token column.

### Command header flow

Declaration binders, short local macro headers, and scoped notation modifiers
can break at incidental parser-wrapper boundaries. A fitting command header such
as `local macro "name" : tactic =>` should remain one flow, and a modifier should
not become an orphan line above its command.

## Progress

### Application ownership

Give nested applications, proof arguments, named arguments, infix operands, and
their closers one stable continuation base. Add representative Mathlib
regressions, verify that compact applications still fit, and run the local gate
plus GraphQL, quantum, and Mathlib checkpoint validation.

### Suffix body ownership

Unify the body boundary for refutable fallbacks, `<|`, `from`, and parser-defined
suffix forms without keyword-specific renderer logic. Cover fitting and broken
forms, then run the local gate and focused external validation.

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
