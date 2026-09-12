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

When restoring one nested base makes the next comment join overflow, overlapping
continuation tails still require repeated rendering. Owner-local retries avoid
replaying the complete module, but do not establish linear scaling. Keep the
32/64/128-clause stress sample alongside routine performance measurements. This
still takes 9.54s at 128 clauses and width 512. It is a worst-case retry cost,
not a known formatting failure. Do not hide it by
guessing columns or splitting fitting later joins. Further prefix reuse needs a
separate, reviewed renderer contract; preparation caching alone does not address
the measured rendering cost.

### Required prefix elaboration cost

```lean
theorem evidence : True := by trivial
attribute [local simp] evidence
```

Attributes, deriving handlers, wrappers, and unclassified commands still receive
the complete preceding source state, including declaration bodies. This required
replay dominates targeted Mathlib timings. Do not skip proof bodies, guess
dependencies, or add attribute exceptions. Lean 4.33.1 has no audited
source-dependency replay API. This cost is not a known formatting failure.

### Preserved multiline tactic width

```lean
  inv :=
    ⟨
      f.inv,
      by
        rw [← Functor.mapIso_inv, Iso.comp_inv_eq, Category.assoc, Iso.eq_inv_comp, Functor.mapIso_hom,
          hf]
    ⟩
```

Authored multiline tactic text remains protected when structural reindentation
makes a line exceed width 100. `CategoryTheory/DifferentialObject.lean:152` grows
from 99 to 103 characters; a `simp_rw` continuation in
`Algebra/Group/ForwardDiff.lean:281` grows from 97 to 101. Both paths are relative
to `Mathlib/`. These warnings already occur in the full-build baseline and are
exempt from actionable-overflow checks. Reflowing their lists requires a
protected-proof policy decision, not tactic-specific indentation exceptions.

## Progress

### Current checkpoint: retry efficiency

The width-aware ownership change is committed as `b0a3fa4`. The current candidate
adds sparse original-owner descriptors to the prepared view and cached layout
facts. A complete owner retries from the same incoming render state, retaining
accepted earlier output. Nested owners resolve their own joins; partial segments
cannot change topology. The bounded module retry remains the fallback for flat
probes that bypass complete-owner rendering. No formatting rule, syntax node,
rule API, or diagnostic policy changed.

The complete local gate passed: build, full unit suite, linter, fixture checks,
self-format checks, preservation, actionable overflow, and idempotency. Fixtures
are unchanged, and self-formatting touched only new code. New tests check local
cascade resolution, retained earlier feedback, restored guard scopes, sibling
owners, and the absence of retry descriptors on plain chains. Existing exact
output, elaboration, preservation, trace, and probe-rollback tests remain intact.

All 3,240 generated placement comparisons and 120 protected-proof comparisons
match the previous whole-tree retry algorithm exactly. The independent 84-case
output-lexing oracle also agrees with production; all cases elaborate, preserve
code and syntax signatures, and are idempotent without fallback.

External validation passed from pristine sources, with previous formatted output
retained for comparison. There were zero new output differences, exceptions,
preservation fallbacks, actionable overflows, or idempotency failures. Mathlib
missing-rule checks passed. Target-project builds and the complete Mathlib sweep
were omitted at this lightweight gate; no output changed against the recorded
build baselines, so there were no newly changed modules to build.

| Project | Scope | Formatter/check time | Changed output files |
| --- | --- | --- | --- |
| GraphQL | 280 files, width 90 | 42s | 0 |
| quantum | 20 owned files; 1 unowned skipped, width 90 | 37s | 0 |
| CSLib | 200 files, width 100 | 103s | 0 |
| Mathlib | 36 pristine files, width 100 | 90.16s | 0 |

Serial ABBA comparison against the saved `b0a3fa4` executable used 13 identical
Mathlib inputs with no concurrent validation workload. Mean user CPU was 64.935s
before and 64.72s after (-0.3%, with overlapping sample ranges): no meaningful
routine regression. At 128 clauses, plain-chain format/check time stayed 28ms and
fitting-comment chains stayed 30ms.

| Cascading clauses, width 512 | Before | After |
| --- | --- | --- |
| 32 | 1.398s | 0.612s |
| 64 | 5.603s | 2.241s |
| 128 | 25.077s | 9.542s |

All nine stress inputs passed preservation, width, fallback, and idempotency
checks before and after, with byte-identical output. The largest case improved
by 2.6 times, but overlapping tails remain an open scaling issue. This checkpoint
is validated; it does not replace the full release gate.

### Next checkpoint: protected-proof width policy

Decide whether authored multiline tactic lists should remain protected after
reindentation exceeds the requested width. Any policy change must express
ownership structurally and use general renderer recovery, with preservation,
indentation, and idempotency coverage. No `rw`/`simp_rw` rules or indentation
exceptions. Review the policy before implementation.

### Release gate

Rerun complete CSLib and Mathlib validation on the final candidate, including
changed-module and aggregate builds. Review formatter diagnostics, output changes,
and performance. Keep acceptable protected-line and too-many-lines warnings
distinct from actionable formatting failures.

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
and CSLib build baselines, then select pristine Mathlib sources covering the changed
path and existing safety regressions. Keep missing-rule checks enabled for Mathlib
only. Report exact sample size, omitted builds, and changed-module build results.
Compare performance on identical sources with no concurrent validation workload.

Use full validation, not checkpoint mode, for the release gate. Mathlib is pinned
to v4.33.1 commit `0df444a360eaa60ab8c11dca51a86af692955474`; format only
`Mathlib/`, use width 100 and Lake cache. CSLib is pinned to
`98e395a701f2027a413ad24729e1a11a6c772eb4` with Lean v4.33.1 and width 100.
The release gate runs clean, changed-module, and complete post-format builds.
Protected tactic/comment overflows and new too-many-lines warnings may be
acceptable under the current design; successful validation does not mean every
physical line fits width 100.

## Evidence

Current artifacts use `.scratch/retry-efficiency-*`. Source snapshots, changed-file
lists, patches, and formatter logs are under `.scratch/retry-efficiency-validation/`.
The independent 84-case oracle is `.scratch/WidthConditionalOwnership.lean`;
its latest production comparison is `.scratch/retry-efficiency-oracle-final.log`.
`.scratch/RetryEfficiencyExperiment.lean` compares local and whole-tree retries
with identical rendering rules, including protected-proof contexts. Performance
compares the candidate with the saved `b0a3fa4` executable. Stress outputs and
before/after logs are under `.scratch/retry-efficiency-performance/`;
`.scratch/ProfileRetryEfficiencyStress.sh` checks exact output parity as well as
preservation, width, fallback, and idempotency. The previous width-aware checkpoint
artifacts remain available under `.scratch/width-aware-*`.

The recorded full-build baselines and batch logs are under
`.scratch/external-validation-release/logs/`. They cover 200 CSLib files and
all 8,311 selected Mathlib files, followed by changed-module and aggregate builds.
They predate this candidate; subsequent lightweight checkpoints do not replace
the required release gate. Original external clones remain available for review.
No external formatting change should be used as the source of a formatter fix.
