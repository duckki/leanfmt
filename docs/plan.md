# Version 0.4 plan

This document is the forward-looking work list for the next release. Formatting
examples from external projects are evidence for general rules; project paths,
declaration names, and isolated token sequences must never become formatter
conditions.

## Known issues

- No reproduced release-blocking external-corpus shape is open. Fresh GraphQL,
  quantum, and exact Mathlib validation passed at checkpoint 2; later formatter
  changes must repeat the affected corpus checks before release.
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
- Performance checks are currently manual. Profiling exists, but the repository
  has no stable representative baseline that detects a material regression in
  syntax-tree construction, rendering, or convergence.

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
- Validate exact Mathlib `v4.32.0` at width 100, formatting only `Mathlib` and
  using the Lake cache.
- Review every candidate-only formatting delta for missing or wrong line breaks,
  incorrect indentation, fallback, non-idempotence, preservation failures, and
  actionable overflow.
- Convert any blocker into a focused test and fix only its general syntax,
  line-break, spacing, source-emission, or renderer-state cause. Stop for design
  review if a finding requires a new rule API or a specialized exception.

Acceptance: all formatter batches and post-format builds pass, no release-blocking
formatting issue remains, and elapsed and CPU timings show no material regression.

## Checkpoint 3: performance and test hardening

Status: next.

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
must use automatic worker counts; do not pass `--jobs`. Mathlib validation uses
exact commit `81a5d257c8e410db227a6665ed08f64fea08e997`, formats only `Mathlib`
at width 100, downloads the Lake cache, skips the released commit's redundant
pre-format build, and always runs the complete post-format build.
