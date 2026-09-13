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
lookups reduce the cost but do not establish linear scaling. The current candidate
also reuses canonical source-layout facts across owner retries. It does not cache
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

### Current checkpoint: immutable retry facts

Source-derived layout facts are cached after an owner's first failed attempt.
Source spans select candidates, and complete tree equality checks grouping, kind,
tokens, and trivia. Same-span wrappers remain distinct. The bounded cache contains
no retry descriptors, alternative proof-island policies, output, or fit decisions.
Nested retries reuse it without adding entries, and owner exit restores the
enclosing cache. Fresh views attach fresh retry metadata. No formatting rule or
ownership policy changes.

Focused coverage checks regrouped same-span trees, changed tokens, missing nodes,
proof-island alternatives, fresh retry metadata, cache bounds, nested reuse, and
scope restoration. The complete local gate passed, including both unit-suite runs,
lint, fixture regeneration and dry check, self-format and dry check, preservation,
overflow, and idempotency. Fixtures and existing expectations are unchanged;
self-format touched only new code. All 3,360 reference-renderer comparisons passed.
The independent 84-case ownership oracle preserved output and syntax, elaborated,
and converged idempotently. External review and serial performance checks passed.

Lightweight external validation passed from pristine inputs with no diagnostic
failures, including Mathlib missing-rule checks. Every output is identical to
committed checkpoint `d3f35fd`:

| Project | Scope | Formatter/check time | Changed output files |
| --- | --- | --- | --- |
| GraphQL | 280 files, width 90 | 45s | 0 |
| quantum | 20 owned files; 1 unowned skipped, width 90 | 41s | 0 |
| CSLib | 200 files, width 100 | 115s | 0 |
| Mathlib | 38 files, width 100 | 101.43s | 0 |

GraphQL and quantum used formatter builds compatible with Lean 4.33.0 and 4.32.0;
those build times are omitted above. Target-project builds and the complete
Mathlib sweep were omitted. No changed-module builds were needed because all
review patches are empty. This is a lightweight checkpoint, not the release gate.

The final paired width-512 cascading samples against `d3f35fd` retained exact
output and passed exception and idempotency checks:

| Clauses | Before | After |
| --- | --- | --- |
| 32 | 285ms | 261ms |
| 64 | 649ms | 577ms |
| 128 | 1760ms | 1427ms |

An earlier paired run also improved the 128-clause case from 1750ms to 1387ms.
Plain and fitting-comment controls remain at 19-21ms for 128 clauses. Simultaneous
failure controls retained exact output and idempotency (128 clauses: 824ms before,
837ms after, +1.6%); their deliberately overlong comments make them performance
controls, not a width gate.

Serial ABBA measurements on 13 identical Mathlib inputs compared the candidate
with `d3f35fd`. Mean user CPU was 69.125s before and 69.355s after (+0.33%); mean
wall time was 30.295s before and 29.930s after. No meaningful routine performance
regression was observed. The cache reduces cascading retry cost by about 19% in
the final 128-clause sample, but does not eliminate repeated tail rendering.
A separate paired 128-clause resource measurement reported maximum RSS of
1,393,295,360 bytes before and 1,375,944,704 bytes after. This sample showed no
peak-memory increase; it is not a general memory bound beyond the cache's
structural entry-count limit.

### Remaining performance work

The immutable-facts contract is implemented. Do not extend it to partial output
without specifying how changed grouping, indentation, trailing fit context,
comments, feedback, and traces invalidate accepted pieces. Required prefix
elaboration remains an explicit correctness constraint; further work needs an
audited native dependency API or a separately reviewed parser contract change.

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

Current artifacts use `.scratch/retry-facts-*`. External source snapshots,
changed-file lists, patches, and logs are under
`.scratch/retry-facts-validation/`. The focused Mathlib sample contains the
36 existing safety-regression files plus both newly recovered proof examples.
Paired performance runs use the saved `d3f35fd` executable and 13 identical
Mathlib sources. Final local results are in
`.scratch/retry-facts-check.log`; external results are in
`.scratch/retry-facts-external.log`. Stress evidence is under
`.scratch/retry-facts-stress/` and `.scratch/retry-facts-uniform/`; paired resource
measurements are under `.scratch/retry-facts-memory/`.

The recorded full-build baselines and batch logs are under
`.scratch/external-validation-release/logs/`. They cover 200 CSLib files and
all 8,311 selected Mathlib files, followed by changed-module and aggregate builds.
They predate this candidate. External formatting changes must never be used as
the source of a formatter fix.
