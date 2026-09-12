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
replaying the complete module. The current checkpoint stops invalid retry tails,
reuses source-boundary facts, and removes full-list scans from nearest-content
lookups. These reduce repeated work but do not establish linear scaling. Keep
the 32/64/128-clause stress sample alongside routine performance measurements.
The 128-clause case now takes 1.945s rather than 9.739s at width 512. This is a
worst-case retry cost, not a known formatting failure. Do not hide it by guessing
columns or splitting fitting later joins. Reusing accepted pieces inside an
owner still needs a separate, reviewed renderer contract.

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

### Current checkpoint: cascading retry cost

The owner-local retry checkpoint is committed as `68f8516`. This candidate keeps
its initial attempt complete to collect simultaneous failures. A later balanced
retry may stop at the first newly broken join; its incomplete output returns only
to the retry boundary and cannot enter a fit comparison. Children, flow candidates,
and fit probes still finish normally. No formatting rule, syntax node, rule API,
or diagnostic policy changed.

A module-local cache shares physical comment facts between layout preparation
and layout-fact rebuilding. Keys contain both UTF-8 source endpoints; no column,
indentation, or fit decision is cached. Nearest-content queries scan directly
toward the requested neighbor without allocating and scanning every child index.

The complete local gate passed: build, full unit suite, linter, fixture checks,
self-format checks, preservation, actionable overflow, and idempotency. Fixtures
are unchanged, and self-formatting touched only new code. New coverage checks
neighbor lookup equivalence across segment bounds and empty children, cached
comment classification, early retry exit, retained feedback, and complete fitting
attempts. Existing ownership, elaboration, trace, and probe-rollback coverage remains.

All 3,240 generated placement comparisons and 120 protected-proof comparisons
match the whole-tree retry reference exactly. The independent 84-case output-lexing
oracle agrees with production; all cases elaborate, preserve code and syntax
signatures, and converge idempotently without fallback.

Lightweight external validation passed from pristine sources. There were zero
new output differences, exceptions, preservation fallbacks, actionable overflows,
or idempotency failures. Mathlib missing-rule checks passed. Target-project builds
and the complete Mathlib sweep were omitted. No output changed against the recorded
build baselines, so there were no newly changed modules to build.

| Project | Scope | Formatter/check time | Changed output files |
| --- | --- | --- | --- |
| GraphQL | 280 files, width 90 | 45s | 0 |
| quantum | 20 owned files; 1 unowned skipped, width 90 | 41s | 0 |
| CSLib | 200 files, width 100 | 115s | 0 |
| Mathlib | 36 pristine files, width 100 | 98.30s | 0 |

Serial ABBA comparison against `68f8516` used 13 identical Mathlib inputs with no
concurrent validation workload. Mean user CPU was 69.245s before and 69.43s after
(+0.27%); mean wall time was 29.995s before and 29.96s after. These samples show no
meaningful routine regression. At 128 clauses, plain-chain format/check time
improved from 29ms to 19ms and fitting-comment chains from 30ms to 21ms.

| Cascading clauses, width 512 | Before | After |
| --- | --- | --- |
| 32 | 0.620s | 0.309s |
| 64 | 2.269s | 0.714s |
| 128 | 9.739s | 1.945s |

All nine stress inputs passed preservation, width, fallback, and idempotency
checks before and after, with byte-identical output. The largest case improved
by 5 times, but scaling is not linear. A separate simultaneous-failure negative
control also retained exact output and did not slow down. Its deliberately
oversized comments make it a performance/idempotency check, not a width gate.

This checkpoint is validated. The next implementation needs
review of the protected-proof policy; required prefix elaboration remains an
upstream API limitation. This checkpoint does not replace the full release gate.

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

Current artifacts use `.scratch/join-scaling-*`. Source snapshots, changed-file
lists, patches, and formatter logs are under `.scratch/join-scaling-validation/`.
The independent 84-case oracle is `.scratch/WidthConditionalOwnership.lean`;
its latest production comparison is `.scratch/join-scaling-oracle-final.log`.
`.scratch/RetryEfficiencyExperiment.lean` compares local and whole-tree retries
with identical rendering rules, including protected-proof contexts. Performance
compares the candidate with the saved `68f8516` executable. Stress outputs and
before/after logs are under `.scratch/join-scaling-performance/`;
`.scratch/ProfileJoinScalingStress.sh` checks exact output parity as well as
preservation, width, fallback, and idempotency. The previous checkpoint artifacts
remain available under `.scratch/retry-efficiency-*`.
The complete run is recorded in `.scratch/join-scaling-gate.log`, with local gate
output in `.scratch/join-scaling-check-final.log`. The simultaneous-failure control
is `.scratch/CheckJoinScalingUniform.mjs`, with output under
`.scratch/join-scaling-uniform/`.

The recorded full-build baselines and batch logs are under
`.scratch/external-validation-release/logs/`. They cover 200 CSLib files and
all 8,311 selected Mathlib files, followed by changed-module and aggregate builds.
They predate this candidate; subsequent lightweight checkpoints do not replace
the required release gate. Original external clones remain available for review.
No external formatting change should be used as the source of a formatter fix.
