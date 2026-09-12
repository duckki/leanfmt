# Version 0.4 plan

Rules describe general syntax ownership. External paths and declaration names
are evidence for tests, never formatter conditions. Missing-rule coverage is
release-blocking only for Lean's standard library and Mathlib.

## Open Issues

### Cascading join retry cost

```lean
  else /- A near-width-limit comment. -/ if secondCondition then
    secondResult
  else /- Another near-width-limit comment. -/ if thirdCondition then
    thirdResult
```

Overlapping continuation tails still require repeated rendering when restoring
one nested base makes the next comment join overflow. Owner-local retries,
early exit from invalid retries, cached source boundaries, and direct neighbor
lookups reduce the cost but do not establish linear scaling. The last measured
128-clause stress case took 1.945s at width 512. Retain the 32/64/128-clause stress
sample alongside routine measurements. Reusing accepted pieces inside an owner requires
a separate renderer contract; do not guess columns or split fitting later joins.
This is a worst-case performance issue, not a known formatting failure.

### Required prefix elaboration cost

```lean
theorem evidence : True := by trivial
attribute [local simp] evidence
```

Attributes, deriving handlers, wrappers, and unclassified commands still receive
the complete preceding source state, including declaration bodies. Required
replay dominates targeted Mathlib timings. Lean 4.33.1 has no audited
source-dependency replay API. Do not skip proof bodies, guess dependencies, or
add attribute exceptions. This cost is not a known formatting failure.

## Progress

### Current checkpoint: moved proof argument width

The approved policy permits narrow structural recovery when moving a protected
proof right newly overflows a previously fitting physical source line. It covers
both first lines and later authored continuations. The source-line width includes
comments and uses character columns, not UTF-8 byte offsets. Already-overlong
source lines do not trigger this argument recovery.

`OriginalTree` selects an affected application or delimited argument, opens its
ancestor path, and retains neighboring source regions. Parser tactic wrappers
inside the selected argument may reflow; nested protected islands retain their
plans. Existing rules determine the resulting layout, including balanced lists.
There are no `rw`/`simp_rw` exceptions, new break rules, rule APIs, or renderer
changes. The existing renderer selects the alternative only when it reduces
the overflow count.

Focused checks reproduce and remove the overflows in
`Mathlib/CategoryTheory/DifferentialObject.lean` and
`Mathlib/Algebra/Group/ForwardDiff.lean`. The former overflowed its first list
line; the latter overflowed a later continuation. Neighboring tactics retain
their source layout. Internal coverage checks exact output, indentation,
fitting and already-overlong controls, Unicode, CRLF and EOF, comment-inclusive
source width, enclosing suffixes, opaque barriers, elaboration, preservation,
and idempotency. A nested-record reproducer checks consistent field indentation
and the proof body's base after recovery.

The complete local gate passed, including the post-self-format build and unit
suite, development linter, fixture dry check, self-format dry check, preservation,
actionable overflow, and idempotency. Fixtures are unchanged; self-formatting
touched only new code. Two earlier test expectations were updated: moved rewrite
lists and proof equation applications now wrap instead of retaining induced
overflow. No unrelated fixture or self-format churn was accepted.

Lightweight external checks passed from pristine sources. All exception,
preservation, actionable-overflow, fallback, and idempotency checks passed;
Mathlib missing-rule checks passed. Output changes were reviewed against the
recorded formatted baselines.

| Project | Scope | Formatter/check time | Changed output files |
| --- | --- | --- | --- |
| GraphQL | 280 files, width 90 | 93s | 1 |
| quantum | 20 owned files; 1 unowned skipped, width 90 | 52s | 0 |
| CSLib | 200 files, width 100 | 229s | 0 |
| Mathlib | 38 pristine files, width 100 | 142.89s | 5 |

These wall times overlapped local checks and are not a performance comparison.
Serial ABBA timing against `ef09f1e`, with no other validation running, used
13 identical Mathlib inputs. Mean user CPU was 71.205s before and 71.240s after
(+0.05%); mean wall time was 33.290s before and 32.305s after. This sample shows
no meaningful routine regression.

GraphQL's changed `Queue.lean` module builds successfully. Its recovered record
arguments and nested proof bases were reviewed. The five changed Mathlib modules
also build successfully, including their dependency rebuilds (2,188 Lake jobs).
Their changes wrap overflowing arguments and lists. Existing warnings in
unchanged dependency files remain; no build failures occurred.
Quantum and CSLib output is unchanged. Aggregate project builds and the complete
Mathlib sweep were omitted. This checkpoint is validated but does not replace
the release gate.

### Release gate

Rerun complete CSLib and Mathlib validation on the final candidate, including
changed-module and aggregate builds. Review diagnostics, output changes, and
performance. Lightweight checkpoints do not replace this gate. Already-overlong
protected text and new too-many-lines warnings may remain acceptable when their
formatting shape follows the design.

## Validation Standard

Run focused checks while developing, then:

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

Review generated fixture and self-format changes. Use automatic worker counts;
do not pass `--jobs`. For lightweight checkpoints, use recorded GraphQL, quantum,
and CSLib build baselines, then select pristine Mathlib sources covering the
changed path and existing safety regressions. Keep missing-rule checks enabled
for Mathlib only. Report sample size, omitted builds, and changed-module build
results. Compare performance on identical sources without concurrent validation.

Use full validation, not checkpoint mode, for the release gate. Mathlib is pinned
to v4.33.1 commit `0df444a360eaa60ab8c11dca51a86af692955474`; format only
`Mathlib/`, use width 100 and Lake cache. CSLib is pinned to
`98e395a701f2027a413ad24729e1a11a6c772eb4` with Lean v4.33.1 and width 100.
The release gate runs clean, changed-module, and complete post-format builds.
Successful validation does not mean every protected physical line fits width 100.

## Evidence

Current artifacts use `.scratch/protected-width-*`. External source snapshots,
changed-file lists, patches, and logs are under
`.scratch/protected-width-validation/`. The focused Mathlib sample contains the
36 existing safety-regression files plus both newly recovered proof examples.
Paired performance runs use the saved `ef09f1e` executable and 13 identical
Mathlib sources. Final local results are in
`.scratch/protected-width-check-post-format.log`; external results are in
`.scratch/protected-width-external-final.log`. Changed-module builds are recorded
in `.scratch/protected-width-graphql-build.log` and
`.scratch/protected-width-mathlib-build.log`. Prior retry stress evidence remains under
`.scratch/join-scaling-*`.

The recorded full-build baselines and batch logs are under
`.scratch/external-validation-release/logs/`. They cover 200 CSLib files and
all 8,311 selected Mathlib files, followed by changed-module and aggregate builds.
They predate this candidate. External formatting changes must never be used as
the source of a formatter fix.
