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
lookups reduce the cost but do not establish linear scaling. Canonical source facts
are reused across retries. The current candidate also avoids whole-text character
lists in boundary-edge and line-extent queries. It does not cache
accepted render pieces: their indentation and enclosing fit context can change.
Retain the 32/64/128-clause sample alongside routine measurements. Eliminating the
remaining repeated rendering requires a separate accepted-piece reuse contract;
do not guess columns or split fitting later joins.
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
add attribute exceptions. The audit found no duplicate completed-prefix replay
within one parse. Native snapshot reuse needs unchanged syntax and source positions;
it does not bypass the first changed declaration's required elaboration. Commands
can also inspect the complete file source. Reusing final command state in the
independent idempotency pass would weaken that check and is not allowed. No safe
general shortcut was identified. This cost is not a known formatting failure.

## Progress

### Current checkpoint: bounded boundary queries

Leading and trailing whitespace queries stop after the one or two newline
delimiters needed by the query. First-line width and last-line extraction scan
only the relevant slice instead of constructing complete character lists.
Unicode character widths, CRLF/CR handling, and horizontal whitespace semantics
are unchanged. No new cache, syntax rule, or rendering state is added.

Coverage compares the five queries with the previous character-list definitions
over 9,366 inputs: exhaustive short strings, mixed line endings, Unicode,
non-horizontal Unicode whitespace, long comments, and comment boundaries.
All 9,366 inputs passed. The complete local gate passed, including both unit-suite
runs, lint, fixture regeneration and dry check, self-format and dry check,
preservation, overflow, and idempotency. Fixtures and existing expectations are
unchanged; self-format touched only the new test. All 3,360 reference-renderer
comparisons passed. The independent 84-case ownership oracle preserved output
and syntax, elaborated, and converged idempotently. Lightweight external checks
and serial performance comparisons passed. The CSLib timing investigation below
records a contended outlier separately from the final comparison.

Lightweight external validation passed from pristine inputs with no diagnostic
failures, including Mathlib missing-rule checks. Every output is identical to
committed checkpoint `c9a7959`:

| Project | Scope | Formatter/check time | Changed output files |
| --- | --- | --- | --- |
| GraphQL | 280 files, width 90 | 45s | 0 |
| quantum | 20 owned files; 1 unowned skipped, width 90 | 43s | 0 |
| CSLib | 200 files, width 100 | 151s | 0 |
| Mathlib | 38 files, width 100 | 106.67s | 0 |

GraphQL and quantum used formatter builds compatible with Lean 4.33.0 and 4.32.0;
those build times are omitted above. Target-project builds and the complete
Mathlib sweep were omitted. No changed-module builds were needed because all
review patches are empty. This is a lightweight checkpoint, not the release gate.

Final serial measurements compared the candidate with `c9a7959` on identical
inputs. All width-512 cascading samples retained exact output and passed
exception and idempotency checks:

| Clauses | Before | After |
| --- | --- | --- |
| 32 | 261ms | 235ms |
| 64 | 578ms | 525ms |
| 128 | 1424ms | 1306ms |

An earlier run also improved the 128-clause sample from 1423ms to 1298ms.
Plain and fitting-comment controls were unchanged at 18ms and 20ms for 128 clauses.
Simultaneous-failure controls retained output and idempotency (128 clauses:
827ms before, 732ms after). Their deliberately overlong comments make them
performance controls, not a width gate.

Serial ABBA measurements on 13 Mathlib inputs reported mean user CPU of 70.750s
before and 69.995s after (-1.07%), with mean wall time of 32.765s before and
30.680s after. No routine regression was observed in this sample. A separate
100-file CSLib batch-2 comparison also passed every diagnostic check. Its first
candidate sample overlapped high-CPU Lean 4.33.0 compiler processes, so the four-run
wall-time mean cannot be used as an uncontended performance comparison. That
sample took 170.59s; a candidate repeat took 91.59s, versus 98.27s for the first
saved-formatter run.
The final saved-formatter run took 89.29s. Comparing the final candidate/baseline
pair, user CPU was 393.18s versus 391.24s (+0.50%), while summed per-file format
time was 377.047s versus 378.843s (-0.47%). No meaningful routine regression was
observed; the initial 151s CSLib validation total is retained above rather than
replaced with a favorable repeat.

### Remaining performance work

The immutable-facts contract is implemented. A prefix can retain its tokens while
its enclosing ancestor segment changes; current rules can inspect that entire
segment. Do not reuse partial output without specifying these rule dependencies
along with indentation, trailing fit context, comments, feedback, and traces.
Required prefix elaboration remains an explicit correctness constraint; further
work needs an audited native dependency API or a separately reviewed parser
contract change.

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

Current artifacts use `.scratch/retry-tail-*`. External source snapshots,
changed-file lists, patches, and logs are under
`.scratch/retry-tail-validation/`. The focused Mathlib sample contains the
36 existing safety-regression files plus both newly recovered proof examples.
Paired performance runs use the saved `c9a7959` executable and 13 identical
Mathlib sources. Final local results are in
`.scratch/retry-tail-check.log`; external results are in
`.scratch/retry-tail-external.log`. Stress evidence is under
`.scratch/retry-tail-stress/` and `.scratch/retry-tail-uniform/`. The sampled
call stacks motivating the bounded scans are in `.scratch/retry-tail-sample.txt`.
The extra CSLib batch-2 timing logs and identical pristine input list are under
`.scratch/retry-tail-cslib-performance/`.

The recorded full-build baselines and batch logs are under
`.scratch/external-validation-release/logs/`. They cover 200 CSLib files and
all 8,311 selected Mathlib files, followed by changed-module and aggregate builds.
They predate this candidate. External formatting changes must never be used as
the source of a formatter fix.
