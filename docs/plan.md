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

When restoring one nested base makes the next comment join overflow, complete
rendering repeats. A 64-clause synthetic case needs 33 attempts; preparation is
negligible compared with repeatedly emitting the tree. At width 512, 32/64/128
cascading clauses take 1.39/5.73/25.70s for formatting and diagnostic checks.
All pass preservation, width, fallback, and idempotency checks. Plain and fitting
comment chains remain fast, and the external performance sample is unchanged
within measurement variation. This is a worst-case retry cost, not a formatting
failure. Do not hide it by guessing columns or splitting fitting later joins.

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

### Current checkpoint: width-aware continuation ownership

Implemented the reviewed layout-feedback contract. `LayoutTree` marks optional
comment joins, and the renderer reports only splits in committed output.
Rendering retries from the original tree with those joins disabled. A disabled
join stays disabled within that pass, bounding attempts by the original guard
count plus one. Parsing and import state are reused; no rule API, break rule,
comment node, or renderer syntax test was added.

A split now moves the whole continuation, including branches and fallback, to
its nested base. Fitting comment joins and source-forced boundaries retain their
existing behavior. Diagnostics normalize parser-packed `doIf` continuations to
the exact nested sequence shape used by Lean's elaborator, without discarding
other statement wrappers. Term and tactic quotations remain strict.

The complete local gate passed: build, full unit suite, linter, fixture checks,
self-format checks, preservation, actionable overflow, and idempotency. Fixtures
are unchanged; self-format changes are confined to the new code. New coverage
includes 28 exact-output cases, six positive/negative preservation comparisons,
four elaborated definitional-equality checks, cascading joins, trace parity, and
probe feedback commit/discard behavior. An independent output-lexing oracle
agrees with production in all 84 cases at widths 60, 100, 120, and 160; all
elaborate, preserve code and syntax signatures, and are idempotent without fallback.

External validation uses pristine sources, with the previous formatted output
retained for comparison. All checks passed with zero new output differences,
exceptions, preservation fallbacks, actionable overflows, or idempotency failures.
Mathlib missing-rule checks also passed. This is a lightweight checkpoint, not
the release gate: target-project builds and the full Mathlib sweep were omitted.
There were no newly changed modules to build against the recorded baselines.

| Project | Scope | Formatter/check time | Changed output files |
| --- | --- | --- | --- |
| GraphQL | 280 files, width 90 | 45s | 0 |
| quantum | 20 owned files; 1 unowned skipped, width 90 | 41s | 0 |
| CSLib | 200 files, width 100 | 117s | 0 |
| Mathlib | 36 pristine files, width 100 | 100.28s | 0 |

A serial ABBA comparison on 13 identical Mathlib inputs measured mean user CPU
of 69.46s before and 69.685s after (+0.3%, with overlapping sample ranges).
At 128 clauses, plain-chain format/check time was 28ms before and 29ms after;
fitting-comment chains were 30ms and 31ms. Cascading joins are the exception:
the old formatter took 206ms but retained incorrect branch indentation, while
the corrected output takes 25.70s. The stress result remains an open performance
follow-up; successful correctness validation does not resolve that cost.

### Next checkpoint: retry efficiency

Prototype owner-local retry or reuse of accepted output before the affected owner,
so cascading joins do not repeatedly render the complete tree. Preserve actual
placement feedback, probe rollback, selective joins, and exact current outputs.
Do not add syntax-specific renderer tests, predicted-column heuristics, or new
break rules. Review the ownership/retry contract before implementation. Require
long-chain scaling measurements and the same local and external checkpoint gate.

### Following checkpoint: protected-proof width policy

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

Current artifacts use `.scratch/width-aware-*`. Source snapshots, changed-file
lists, patches, and formatter logs are under `.scratch/width-aware-validation/`.
The independent 84-case oracle is `.scratch/WidthConditionalOwnership.lean`;
its production comparison is `.scratch/width-aware-oracle.log`.
Performance compares the candidate with the saved `58dc375` executable.
The corrected stress inputs and before/after logs are under
`.scratch/width-aware-performance/`; `.scratch/PrepareWidthAwareStress.mjs`
generates them. `.scratch/width-aware-join-attempts.log` records the 64-clause
retry breakdown from `.scratch/ProfileJoinAttempts.lean`.

The recorded full-build baselines and batch logs are under
`.scratch/external-validation-release/logs/`. They cover 200 CSLib files and
all 8,311 selected Mathlib files, followed by changed-module and aggregate builds.
They predate this candidate; subsequent lightweight checkpoints do not replace
the required release gate. Original external clones remain available for review.
No external formatting change should be used as the source of a formatter fix.
