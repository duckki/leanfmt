# Version 0.4 plan

This document is the forward-looking work list for the next release. Formatting
examples from external projects are evidence for general rules; project paths,
declaration names, and isolated token sequences must never become formatter
conditions.

Missing-rule coverage is release-blocking only for Lean's standard library and
Mathlib, which are leanfmt's first-class syntax-support targets. Missing-rule
diagnostics from GraphQL, quantum, Hex, and other external projects are useful
inventory, but do not block validation unless they coincide with an actual
preservation, formatting, convergence, overflow, or build problem.

## Known issues

- Fitting custom command suffixes can detach from their headers. Hex exposes
  this broadly through `setup_* ... where` commands: every observed header fits
  at width 100 with `where` attached, but the generic custom-syntax layout moves
  `where` onto a separate line.
- Long `opaque` declaration headers can put `:=` on a line by itself instead of
  keeping the assignment separator with the return type.
- Core suffix attachment is inconsistent under width pressure. Hex contains
  detached `then`, `else do`, and `← do` forms even though the suffix belongs to
  the preceding header or separator.
- A multiline `let` fallback can put `|` on an otherwise empty line. The
  fallback may need its own structural continuation base, but the bar must align
  with the owning `let` and remain attached to its first token or comment.
- Structural indentation can leak into horizontal whitespace after an infix
  operator, producing forms such as `&&  if`, `&&  let`, `++  if`, and `<|  if`.
- Nested infix and `<|` chains can accumulate indentation instead of sharing
  their expression base.
- A low-priority application can still leave `<|` alone before an ordinary
  application whose own first-line boundary is not represented as a movable
  original-child boundary. Comment-led and nonfitting protected operands retain
  the post-operator boundary intentionally.
- Declaration parameters and typeclass arguments can inherit the declaration
  name's ending column instead of the declaration's structural continuation
  base.
- Unknown generated syntax with multiple meaningful children intentionally
  reports a missing rule unless regrouping can prove a standard application,
  delimiter, infix, or declaration shape. Broadly treating such nodes as
  transparent would hide extension-owned layout.
- Source-authored calc text that Lean does not expose as parsed calc rows remains
  an original-layout island. Reindenting malformed or ambiguous rows without a
  structural owner risks changing syntax.
- Adjacent anonymous-constructor delimiters can accumulate one indentation level
  per delimiter. This is a style limitation, not a preservation or build blocker.
- A source break after `<|` can preserve two spaces before its operand. Changing
  that accepted shape requires a separate low-priority-infix style decision.
- Long indivisible lines are accepted when they start at the correct logical
  indentation. Formatter-created too-many-lines warnings are accepted when the
  surrounding formatting shape is sound.
- The local profiling guard is a same-machine comparison, so release review must
  still consider full external-validation timings when concurrency, import
  environments, or corpus size may dominate formatter cost.

Current Hex evidence is diagnostically complete for all 889 tracked Lean files.
The 886 native files pass preservation, overflow, fallback, and idempotency
checks at width 100, and the complete post-format Hex build passes. The three
CompPoly adapters pass the same formatter checks in a pinned Lean `v4.32.2`
companion environment, where their current blobs match the last compatible Hex
source revision exactly; both consumer equivalence targets and the comparator
target rebuild after formatting. Missing-rule reports are informational for
this corpus. Formatting review still finds the suffix, separator, fallback, and
horizontal-spacing issues listed above, including detached `where` and `{` in
the comparator's generated benchmark commands, so style closure is not
complete. Checking and rewriting the 886 native files took about 10 minutes 12
seconds; their complete post-format build took 13 minutes 39 seconds.

Current exact Mathlib formatter evidence is complete: all 84 formatter
batches covering 8,311 tracked files under `Mathlib` pass preservation,
overflow, missing-rule, fallback, and idempotency checks at width 100. The
complete post-format build covers all 8,705 targets. Review still finds the
fallback, low-priority-infix, declaration-base, and comment-owner issues listed
above, so this result is a diagnostic checkpoint rather than formatting
closure.

The latest complete Mathlib diff review makes the remaining groups concrete:
eight refutable-`let` fallbacks leave `|` alone. Thirty-five physical lines
contain a standalone `<|`, down from 51 in the preceding checkpoint after 16
movable operator-operand boundaries were coordinated. Review classifies most of
the remainder as comment-led or nonfitting protected operands with intentional
source boundaries; ordinary application and comment-owner cases remain
follow-up consistency work. Thirteen declaration or typeclass continuations
inherit declaration-name columns, and isolated lambda and
constructor-after-comment cases retain a nonstructural base. The two previously
misaligned `finprod` bodies now use their indexed relation's structural base;
focused formatting diagnostics and the affected Mathlib target build pass.
Checkpoint 6 separately validates every previously detached calc placeholder
row plus the affected proof-introducer, nested-binder, and quotation files; all
focused diagnostics and builds pass. Fresh GraphQL and quantum validation passes
before and after formatting. The preceding binder-sequence checkpoint aligns
GraphQL's quantifier continuations with their first binder instead of adding an
extra continuation level; the indexed-infix base propagation adds no further
GraphQL or quantum formatting delta.

Quantum validates with the same current leanfmt source under Lean `v4.32.0`.
The external validator now detects the target toolchain, refreshes an incremental
compatible formatter build under its scratch directory, and invokes that binary
from Quantum's `lake env`. This removes the executable ABI mismatch without
mutating either repository or introducing a formatter-rule exception.

## Checkpoint 1: layout ownership

Status: complete.

- Make command and extension-tactic context explicit in the syntax tree so
  diagnostics, regrouping, and source-island policy do not infer ownership from
  namespaces.
- Reuse one declaration-header group for local declarations and `initialize`,
  including `:=` and `←` value boundaries.
- Give generated spaced applications and attached generated suffixes ordinary
  application ownership only when their parser shape proves that interpretation.
- Keep applications on their local base, including ordinary infix,
  pipe-projection, and `<|` operands, and group `return` with its application
  head so prefixed arguments do not inherit an incidental inline column.
- Apply structural bases consistently to structure-field defaults, quotations,
  protected proofs, and moved comments.
- Keep physical comment-boundary indentation separate from the renderer's
  logical segment base.
- Classify comment token fragments by lexical boundaries so comment-looking text
  inside multiline strings remains byte-preserved.

Acceptance: focused reproductions, the complete local gate, the focused Mathlib
issue set, and review of all fixture and self-format deltas.

## Checkpoint 2: external corpus closure

Status: complete.

- Validate fresh GraphQL and quantum clones with automatic formatter workers.
- Validate exact Mathlib at width 100, formatting only `Mathlib` and using the
  Lake cache.
- Review every candidate-only formatting delta for missing or wrong line breaks,
  incorrect indentation, fallback, non-idempotence, preservation failures, and
  actionable overflow.
- Convert any blocker into a focused test and fix only its general syntax,
  line-break, spacing, source-emission, or renderer-state cause. Stop for design
  review if a finding requires a new rule API or a specialized exception.

Acceptance: all formatter batches and post-format builds pass, no release-blocking
formatting issue remains, and elapsed and CPU timings show no material regression.

## Checkpoint 3: performance and test hardening

Status: complete.

- Record a small representative profiling baseline that exercises syntax-tree
  regrouping, original-layout emission, layout search, and convergence without
  depending on an external checkout.
- Remove repeated tree scans where an existing contextual node or cached fact can
  answer the same question, without changing formatting behavior.
- Add regression coverage for every issue discovered during corpus closure,
  including preservation, fallback, and idempotency assertions where source
  layout is involved.
- Run the complete local and external release gates once more after any
  performance-oriented change.

Acceptance: the profiling baseline is documented and repeatable, test coverage
represents all accepted corpus fixes, all release gates pass, and the v0.4
candidate has no known exception, build, or performance blocker.

## Checkpoint 4: Hex corpus closure

Status: validation complete; known layout blockers remain.

- Treat registered borrowed syntax as the same general unary-prefix structure
  as other prefix terms; do not specialize a rule to a declaration or project.
- Recognize extension-owned single-operand tactic terms as ordinary spaced
  applications only when their parsed children prove that shape. A direct
  tactic-sequence entry retains tactic ownership while its final term child
  uses ordinary application flow, covering term-taking core and extension
  tactics without a keyword list. Preserve the missing-rule diagnostic for
  genuinely opaque extension syntax.
- Keep a `let`-else fallback bar on its structural continuation base and apply
  the existing suffix mechanism to `else do`; do not add renderer conditions
  for either spelling.
- Propagate break opportunities through long application, optional-access,
  defaulting, and projection chains so width enforcement can choose an earlier
  structural boundary.
- Add focused reproductions for each issue before changing grouping or break
  behavior, then review the complete generated Hex diff at width 100.

Acceptance: the complete local gate passes under the current Lean toolchain;
GraphQL and quantum remain clean; every Hex formatter batch passes preservation,
overflow, fallback, and idempotency checks at width 100; the post-format Hex
build passes; and review finds no logical layout regression or material
performance regression. Hex missing-rule diagnostics are recorded but do not
affect acceptance.

## Checkpoint 5: external-environment validation

Status: complete.

- Select or build a formatter binary compatible with each target project's Lean
  toolchain instead of loading a release-toolchain binary into an incompatible
  `lake env`. Retain one disposable build per target toolchain, refresh it from
  the current leanfmt source, and let Lake reuse unchanged build artifacts.
  Invoke the compatible binary from the target's `lake env` without mutating
  either repository. Keep one formatter source and one validation behavior.
- Represent tracked adapter sources that require a companion project as an
  explicit validation target, not as exceptions in syntax, line-break,
  diagnostics, or rendering code.
- Establish a pinned CompPoly environment compatible with the current Hex
  adapters and validate all three adapter sources with preservation, overflow,
  fallback, and idempotency checks. Record missing-rule diagnostics as
  informational syntax inventory.
- Rerun GraphQL, quantum, and all 889 Hex files, then review formatting and
  timing deltas before resuming Mathlib formatting work.

Acceptance: GraphQL and Hex validate through the standard script; quantum uses
the same current formatter source under its target Lean toolchain; the three
CompPoly adapters parse and build in their declared environment; no target
requires a formatter-rule exception; and no material performance regression
appears.

## Checkpoint 6: structural attachment consistency

Status: complete.

- Keep a calc placeholder attached to its relation without specializing the
  rule to a particular relation token.
- Apply the existing suffix mechanism consistently to fitting `by` and `do`
  introducers after `:=`, `=>`, and equivalent value boundaries.
- Make paired delimiters return to their structural opener and keep nested
  binder punctuation on the binder's established continuation base.
- Add focused reproductions before changing regrouping or line-break behavior;
  do not add syntax-specific renderer conditions.

Acceptance: focused tests cover each attachment invariant, self-formatting has
no regression, GraphQL and quantum pass, and the affected Mathlib files format
and build cleanly.

## Checkpoint 7: structural base propagation

Status: complete.

- Audit the reported match-arm, ordinary-lambda, proof-comment, and multiline
  block-comment cases against the current structural ownership tests. The
  architecture migration already gives these forms their parent's base.
- Recognize a documented inductive constructor as the same body child as a
  constructor beginning directly with `|`, then let the constructor own its
  internal marker boundary. Documentation and `|` consequently move together
  on the inductive body's structural base.
- Investigate adjacent low-priority-pipe breaks without adding a token or
  renderer exception. Keeping `<|` with a fitting structural operand already
  works; coordinating it with a child whose own first line must break requires
  layout-search support and remains a known issue for a later checkpoint.

Acceptance: focused preservation and idempotency tests establish constructor
base ownership, the complete local gate passes, and fresh GraphQL, quantum, and
exact Mathlib validation has no release-blocking formatting finding.

## Checkpoint 8: low-priority boundary coordination

Status: complete.

- Let a non-suffix low-priority operator-operand group format its original
  child's leading boundary, using the existing boundary policy rather than a
  token-specific renderer condition or a new rule API.
- Keep `by`, `do`, `calc`, and other established suffix operands on the existing
  suffix path so protected proof indentation remains source-relative.
- Reuse the existing structural fallback for protected delimited operands when
  attaching their first line to the operator. Do not generalize that fallback
  to proof applications or other original-layout islands.
- Validate that coordinated parent and child plans no longer fire both adjacent
  boundaries while preservation, idempotency, and internal island indentation
  remain unchanged.

Acceptance: focused tests cover a chained low-priority application ending in a
protected structure and the existing suffix controls; the complete local gate
passes; GraphQL and quantum remain clean; exact Mathlib validation at width 100
reduces the standalone-operator issue without introducing an exception, build
failure, logical indentation regression, or material performance regression.

## Checkpoint 9: binder-operator body bases

Status: complete.

- Give a binder operator on an indexed-infix RHS the relation's structural base,
  including when one tight delimiter wraps the operator.
- Reuse the same base propagation already used by direct lambda bodies; do not
  add notation names, renderer conditions, or a new rule API.
- Keep binder-sequence continuations aligned with the first binder without an
  extra nesting level, while the post-comma body remains one level inside the
  shared operator base.

Acceptance: focused tests cover direct and parenthesized structural RHS terms;
the complete local gate passes; the two affected Mathlib `finprod` bodies align
with their indexed relation; and focused Mathlib formatting and build checks
pass without preservation, overflow, fallback, missing-rule, or idempotency
failures. Fresh GraphQL and quantum validation also passes. A same-machine
three-sample comparison against the preceding checkpoint reports 5,226 ms total
formatting versus 5,216 ms, with no material performance regression.

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
must use automatic worker counts; do not pass `--jobs`. Hex runs at width 100
before Mathlib and must pass every formatter batch and its complete post-format
build apart from informational missing-rule reports. Missing rules are hard
review failures only for Lean's standard library and Mathlib. Mathlib validation
uses a shallow clone of exact `v4.33.0` commit
`db584cd6d46c92f209a44c0f1c829460d327499d`, formats only `Mathlib` at width
100, downloads the Lake cache, skips the released commit's redundant pre-format
build, and always runs the complete post-format build.
