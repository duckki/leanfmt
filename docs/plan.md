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
are reused across retries. Boundary-edge, line-extent, and comment-break queries
avoid whole-text character lists. Structural spacing context is queried only
when source-adjacent tokens need it. The renderer does not cache
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

### Current checkpoint: bounded performance pass

Comment-forced-break detection scans ASCII delimiters and nested block depth
without normalizing or reconstructing comment text. Structural spacing context
is deferred until an empty source boundary needs it; pending indentation and
ordinary trivia do not evaluate that query. No new cache, rendering state,
syntax rule, or layout policy is added.

Coverage compares comment detection with the previous implementation on 20,040
inputs, including nested and unterminated comments, CR/LF/CRLF, long Unicode
comments, and delimiter-like text inside blocks. Another 32 cases cover deferred
spacing. The existing 9,366 boundary-edge equivalence cases remain in the suite.
The complete local gate passed: build, unit tests, lint, fixture regeneration and
dry check, self-format and dry check, preservation, overflow, and idempotency.
Fixtures and existing expectations are unchanged; self-format touched only new
code and tests. All 3,360 reference-renderer comparisons passed. The independent
84-case ownership oracle retained output and syntax, elaborated, and converged
idempotently.

Lightweight external validation passed from pristine inputs, including Mathlib
missing-rule checks. Every output is identical to checkpoint `36c67fc`:

| Project | Scope | Formatter/check time | Changed output files |
| --- | --- | --- | --- |
| GraphQL | 280 files, width 90 | 46s | 0 |
| quantum | 20 owned files; 1 unowned skipped, width 90 | 40s | 0 |
| CSLib | 200 files, width 100 | 119s | 0 |
| Mathlib | 38 files, width 100 | 101.90s | 0 |

Compatible formatter builds passed on Lean 4.33.0 and 4.32.0; their build times
are omitted above. Target-project builds and the complete Mathlib sweep were
omitted. No changed-module builds were needed because all review patches are
empty. This is a lightweight checkpoint, not the release gate.

Serial ABBA comparisons against `36c67fc` passed exception and idempotency checks
at width 512. Mean checked-format times improved by 8-14%:

| Clauses | Before | After |
| --- | --- | --- |
| 32 | 233ms | 203.5ms |
| 64 | 506.5ms | 464ms |
| 128 | 1313ms | 1131ms |

Separate paired runs also retained exact output (128 clauses: 1290ms to 1148ms).
Plain and fitting-comment controls stayed at 18ms and 19-20ms. Simultaneous-failure
controls retained output and idempotency (128 clauses: 735ms to 674ms); their
deliberately overlong comments make them performance controls, not a width gate.
Maximum observed RSS for the 128-clause command was 1312.7 MiB before and
1311.5 MiB after, with no material increase.

On 13 identical Mathlib inputs, serial ABBA means were 69.645s before and 69.605s
after for user CPU, and 30.36s before and 30.76s after for wall time. Routine cost
was effectively unchanged in this sample; no meaningful regression was observed.
A process check during the paired runs found no competing active Lean build.

This checkpoint completes the low-risk query-overhead pass, not the elimination
of every repeated render. The two open costs above remain separately scoped
architectural follow-ups. Accepted-output reuse needs resolved rule dependencies,
incoming placement, suffix fit, comments, feedback, and trace equivalence. Prefix
replay needs an audited native dependency API or a reviewed parser contract change.
Neither belongs in an opportunistic cache or a weakened idempotency check.

### Next checkpoint: release gate

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

Current artifacts use `.scratch/retry-final-*`. External source snapshots,
changed-file lists, patches, and logs are under
`.scratch/retry-final-validation/`. The focused Mathlib sample contains the
36 existing safety-regression files plus both newly recovered proof examples.
Paired performance runs use the saved `36c67fc` executable and 13 identical
Mathlib sources. Final local results are in
`.scratch/retry-final-check.log`; external results are in
`.scratch/retry-final-external.log`. Stress evidence is under
`.scratch/retry-final-stress/` and `.scratch/retry-final-uniform/`. The sampled
call stacks are in `.scratch/retry-final-sample.txt`. The discarded byte-by-byte
prototype's mixed timings are retained under `.scratch/retry-final-initial-stress/`;
the candidate uses the standard library delimiter search instead.
The final ABBA stress and peak-RSS records are in
`.scratch/retry-final-resources/`; routine Mathlib comparisons are in
`.scratch/retry-final-performance/`.

The recorded full-build baselines and batch logs are under
`.scratch/external-validation-release/logs/`. They cover 200 CSLib files and
all 8,311 selected Mathlib files, followed by changed-module and aggregate builds.
They predate this candidate. External formatting changes must never be used as
the source of a formatter fix.
