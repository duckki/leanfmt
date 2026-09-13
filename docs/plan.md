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
removes redundant source-break discovery and speeds up ASCII boundary scans.
The 128-clause stress case now takes 1.720s at width 512, down from 1.929s on
`66026ec`. Retain the 32/64/128-clause sample alongside routine measurements.
Reusing accepted pieces inside an owner requires a separate renderer contract;
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
add attribute exceptions. This cost is not a known formatting failure.

## Progress

### Current checkpoint: source-boundary query cost

Balanced layouts test whether any source break is retained without calculating
unused indentation for every break. Flow layouts query only their resolved break
points. Both paths share one boundary predicate. ASCII delimiter prechecks use
Lean's byte-array search; Unicode widths and comment semantics are unchanged.
No syntax rules, ownership policy, or partial-render cache are added.

Coverage compares direct queries with full source-break discovery across slices,
missing children, reordered and repeated break points, prefix policies, comments,
Unicode, and line endings. Byte searches are compared with character searches.
All 3,024 source-break query combinations passed. The complete local gate passed,
including both unit-suite runs, development lint, fixture regeneration and dry
check, self-format and dry check, preservation, overflow, and idempotency. Fixtures
and existing test expectations are unchanged; self-format touched only new code.
All 3,360 whole-tree retry comparisons passed. The independent 84-case ownership
oracle preserved output and syntax, elaborated, and converged idempotently.

Lightweight external validation passed from pristine sources with no diagnostic
failures, including Mathlib missing-rule checks. Every reviewed output is identical
to the preceding checkpoint:

| Project | Scope | Formatter/check time | Changed output files |
| --- | --- | --- | --- |
| GraphQL | 280 files, width 90 | 45s | 0 |
| quantum | 20 owned files; 1 unowned skipped, width 90 | 42s | 0 |
| CSLib | 200 files, width 100 | 112s | 0 |
| Mathlib | 38 files, width 100 | 101.39s | 0 |

GraphQL and quantum used formatter builds compatible with Lean 4.33.0 and 4.32.0;
those build times are omitted above. Target-project builds and the complete
Mathlib sweep were omitted. No changed-module builds were needed because all
review patches are empty. This is a validated lightweight checkpoint,
not the release gate.

Serial ABBA measurements on 13 identical Mathlib inputs compared the candidate
with `66026ec`. Mean user CPU was 69.54s before and 69.73s after (+0.27%); mean
wall time was 31.575s before and 30.185s after. No meaningful routine regression
was observed. Width-512 cascading samples improved as follows:

| Clauses | Before | After |
| --- | --- | --- |
| 32 | 311ms | 285ms |
| 64 | 718ms | 635ms |
| 128 | 1929ms | 1720ms |

Plain and fitting-comment controls remain at 19-21ms for 128 clauses. Simultaneous
failure controls also retain exact output and idempotency (128 clauses: 937ms to
816ms); their deliberately overlong comments make them a performance control,
not a width gate. All cascading samples passed exception and idempotency checks
with identical output. The deeper cascading retry issue remains open pending a
separate reuse contract.

### Retry reuse design

Establish which immutable layout facts can be reused when ownership changes,
before considering accepted-render-piece reuse. Keep alternative proof-island
policies and retry descriptors scoped correctly; cached facts must not retain
stale grouping or disabled joins. Require exact output parity, simultaneous-failure
controls, and cascading stress comparisons before adopting a larger cache.

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

Current artifacts use `.scratch/retry-query-*`. External source snapshots,
changed-file lists, patches, and logs are under
`.scratch/retry-query-validation/`. The focused Mathlib sample contains the
36 existing safety-regression files plus both newly recovered proof examples.
Paired performance runs use the saved `66026ec` executable and 13 identical
Mathlib sources. Final local results are in
`.scratch/retry-query-check.log`; external results are in
`.scratch/retry-query-external.log`. Stress evidence is under
`.scratch/retry-query-stress/` and `.scratch/retry-query-uniform/`.

The recorded full-build baselines and batch logs are under
`.scratch/external-validation-release/logs/`. They cover 200 CSLib files and
all 8,311 selected Mathlib files, followed by changed-module and aggregate builds.
They predate this candidate. External formatting changes must never be used as
the source of a formatter fix.
