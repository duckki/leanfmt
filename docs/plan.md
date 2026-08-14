# Version 0.4 plan

This is the forward-looking work list for the next release. External examples
justify general structural rules; project paths, declaration names, and isolated
token sequences must never become formatter conditions.

Missing-rule coverage is release-blocking only for Lean's standard library and
Mathlib, leanfmt's first-class syntax-support targets. Missing rules in other
external projects are useful inventory, but block validation only when they
coincide with preservation, formatting, convergence, overflow, or build issues.

## Open Issues

### Extension command suffix ownership

```lean
setup_generator sample
  where
    { field := value }

run_meta
  do
    action
```

Generated command clauses and bodies can detach from their headers. An optional
command wrapper alone does not distinguish a parser-owned clause from an
optional direct term, so attachment must wait for explicit parser-category
ownership rather than inferring it from tokens or spaces.

### Try clause bases

```lean
try
  action
  catch error => fallback
```

`catch` can inherit the `try` body's indentation after its enclosing declaration
moves. Peer `catch` and `finally` clauses should align with `try`.

### Parser-owned `do` suffix attachment

```lean
for item in items
do
  action item

catch error =>
  do
    fallback error
```

Direct `do` and `by` suffixes are grouped for several structural headers, but
some term-level loops, alternatives, assignments, and tactic clauses still
detach their introducer. Their parser-owned header and body must be exposed by
the syntax tree before the shared suffix and body-base policies can apply.

### Refutable fallback attachment

```lean
let some value ← action
|
  throwError
    "long fallback message"
```

The fallback bar now aligns with its owning `let`, but a protected multiline
fallback can still leave `|` alone. When the first fallback token can accept the
boundary, it should remain attached to the bar without changing the fallback's
internal layout.

### Infix horizontal spacing

```lean
ready &&  if enabled then available else waiting
```

Structural indentation can leak into horizontal trivia after an infix operator.
Inline operator boundaries should emit exactly one separating space.

### Infix continuation bases

```lean
first
  ++ second
    ++ third
```

Nested infix and `<|` chains can staircase. Operators in one logical chain
should share the expression's structural continuation base.

### Low-priority operand attachment

```lean
transform
  <|
  build value
```

An avoidable standalone `<|` remains when an ordinary operand does not expose a
movable first-line boundary. Protected and comment-led boundaries remain valid.

### Declaration continuation bases

```lean
def veryLongDeclarationName
                           (value : Nat) :=
  value
```

Some declaration parameters and typeclass arguments inherit the declaration
name's ending column instead of the command's structural base. This also affects
long `opaque` signatures.

### Nested match ownership

```lean
match
    match value with
    | none => false with
| false => fallback
```

An outer `with` can stay on the final inner branch line, obscuring which `match`
owns the following alternatives. Nested match suffixes and bodies should move
with their parser-owned match node.

### Comment-owned structural bases

```lean
  /-- Explanation. -/
    | constructor
```

A leading comment and its lambda or constructor case can use different bases.
Both should move with the same structural owner. Source-significant diagnostic
comment payloads must retain their relative indentation as one protected block.

### Protected inline body bases

```lean
wrapper (by
          exact proof)

replay := fun context =>
  if h :
      longCondition context then
    result
```

Some inline `by` and `match` bodies retain the introducer's source column after
their owner moves. A proof-bearing structure instance can also protect an entire
field value, preventing an otherwise grouped named condition from replacing a
source break after `:`. Protected bodies should use the nearest structural base,
and proof islands should expose non-proof surrounding syntax to structural rules.

### Tactic continuation bases

```lean
simpa [lemmas] using
                     proof

refine goal <;>
| branch => exact result
```

Operands after tactic introducers and branches after tactic combinators can
inherit a distant source column. They should use the tactic's structural
continuation base without treating tactic names as generic prefix operators.

### External validator project environments

```text
import all Project.Module
external declaration 'Project.nativeParser'
```

Formatting an imported source in an earlier batch can invalidate private object
data needed by a later `import all`. Projects with native parser extensions can
also require symbols that an externally built formatter executable does not
link. The validator needs a target-project-aware execution path and a
dependency-safe artifact policy; these are infrastructure failures, not missing
formatting rules in third-party syntax.

## Progress

### Checkpoint 12: expression bases

Infix spacing is stable, nested chains share one base, and `<|` is not left alone
when an ordinary operand can accept the break. Refutable fallback bars attach to
their first movable token, and comment-owned and protected inline bodies use
structural bases without weakening source preservation. `try`, `catch`, and
`finally` retain one peer clause base when their owner moves.

### Checkpoint 13: declaration and proof ownership

Extension command suffixes, declaration continuations, nested matches, and
tactic continuations use explicit parser ownership. Remaining parser-owned `do`
suffixes obey their grouped structure. No renderer policy or token spelling
substitutes for missing syntax-tree structure.

### Checkpoint 14: external validation environments

The validator can run against project-native parser extensions and preserve
usable `import all` artifacts across batches. Target-toolchain fallback remains
automatic, and the project-aware path does not penalize ordinary Mathlib-style
validation.

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
