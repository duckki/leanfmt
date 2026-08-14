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

### Named conditional conditions

```lean
if h :
  start < n then
```

A fitting dependent condition can break after `h :`. It should use the same
complete-header grouping policy as named `cases` targets and `match` inputs.

### Structural header suffixes

```lean
if longCondition
  then do
    action
else
  if anotherCondition then fallback

for item in items
do
  action item

field :=
  by
    exact proof
```

`then` or `then do` can be stranded after a condition wraps. The suffix should
stay with the condition's final line and return to the conditional base.
Likewise, an `else if` chain should remain a peer chain instead of gaining a
new nested conditional base. Parser-owned `do` and `by` introducers after loop,
alternative, and assignment headers should follow the same suffix policy.

### Do statement separator bases

```lean
do
  IO.println message;
      pure result
```

A statement after `;` can inherit the preceding expression's continuation
column. It should remain inline when it fits or return to the peer statement
base when it breaks.

### Try clause bases

```lean
try
  action
  catch error => fallback
```

`catch` can inherit the `try` body's indentation after its enclosing declaration
moves. Peer `catch` and `finally` clauses should align with `try`.

### Refutable let fallbacks

```lean
let some value ← action
|
  return none
```

Eight Mathlib cases leave `|` alone. The bar should align with its `let` and
remain attached to the fallback's first token or leading comment.

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
```

Some inline `by` and `match` bodies retain the introducer's source column after
their owner moves. Protected bodies should use the nearest structural base.

### Lambda body bases

```lean
fun value => do
action value

fun value =>
result value
```

A lambda body can retain its old source column when the lambda moves, leaving
the body level with `fun` or `=> do`. The body should use the lambda's structural
base, and a direct `do` or `by` introducer should remain attached to `=>`.

### Suffices proof body bases

```lean
suffices veryLongProposition by
                              exact proof
```

The proof after `suffices ... by` can retain the proposition's ending column.
It should use the tactic's structural proof-body base.

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

## Progress

### Checkpoint 10: suffix ownership

Opaque declaration `:=` and structurally proven core suffixes stay attached when
they fit. Terminal delimited operands keep their opener with term-taking tactics,
while direct function and command arguments retain application layout. `else do`
is grouped only in its direct clause wrapper, preserving refutable-fallback
ownership. The implementation uses existing syntax ownership and suffix grouping
without a renderer policy. The complete local gate and GraphQL, quantum, Hex,
and Mathlib validations pass. The final Mathlib review closed a
terminal-delimiter gap under attached tactic-sequence wrappers without finding
a new checkpoint blocker.

### Checkpoint 11: structural headers

Generated command suffixes receive explicit parser-category ownership. Named
conditional conditions stay together when they fit. Wrapped conditions, `then`
suffixes, loop and assignment introducers, `try` peers, refutable fallbacks,
statement separators, lambda bodies, `suffices` proofs, and declaration
continuations use their owning construct's base. Direct `do` and `by`
introducers remain attached to loop, alternative, assignment, and lambda
headers.

### Checkpoint 12: expression bases

Infix spacing is stable, nested chains share one base, and `<|` is not left alone
when an ordinary operand can accept the break. Comment-owned and protected
inline bodies use structural bases without weakening source preservation.

### Checkpoint 13: release validation

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
