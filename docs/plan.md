# Version 0.4 plan

Rules describe general syntax ownership. External paths and declaration names
are evidence for tests, never formatter conditions. Missing-rule coverage is
release-blocking only for Lean's standard library and Mathlib.

## Open Issues

No known unresolved formatting blockers.

## Progress

### Release preparation

No further corrective checkpoint is scheduled. Review and commit the validated
candidate, then complete release packaging. Any subsequent formatter change
requires a fresh release gate; earlier results do not validate later changes.

## Deferred Optimization Opportunities

These are deferred beyond the current release gate. Neither is a known formatting
correctness failure; they do not block this release candidate.

### Cascading join retry cost

```lean
  else /- A near-width-limit comment. -/ if secondCondition then
    secondResult
  else /- Another near-width-limit comment. -/ if thirdCondition then
    thirdResult
```

Overlapping continuation tails can require repeated rendering when restoring one
nested base makes the next join overflow. Existing owner-local retries and cached
source facts reduce cost but do not establish linear scaling. Retain the
32/64/128-clause controls. Accepted-piece reuse needs a contract covering placement,
suffix fit, comments, feedback, and trace equivalence. This is a worst-case
performance issue, not a known formatting failure.

### Required prefix elaboration cost

```lean
theorem evidence : True := by trivial
attribute [local simp] evidence
```

Attributes, deriving handlers, wrappers, and unclassified commands need the
complete preceding source state. No duplicate completed-prefix replay was found
within one parse. Native snapshots require unchanged syntax and positions;
commands may inspect the complete file source. Do not guess dependencies, skip
proof bodies, add attribute exceptions, or share final command state with the
independent idempotency pass. No safe general shortcut has been identified.

### Future design review: accepted-piece reuse

Resolve the reuse contract before adding a render cache. Require equivalent
output, diagnostics, feedback, and traces across placement and suffix changes,
plus improved scaling in the stress controls. Prefix replay remains separately
blocked on an audited native API or a reviewed parser contract change.

## Validation Standard

Run focused checks, then the complete local gate:

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

Review all generated fixture and self-format changes. Normal validation uses
automatic worker counts. For memory-constrained validation or isolated profiling,
explicitly set `--jobs 1` or `LEANFMT_VALIDATION_FORMATTER_JOBS=1`; this does not
change the default. Serialize heavy runs and monitor compressed-inclusive memory.
Lightweight checkpoints use recorded GraphQL, quantum, and CSLib build baselines
plus pristine Mathlib safety regressions.
Report scope and omitted builds. Compare performance on identical inputs without
concurrent validation. Enable missing-rule checks for Mathlib only.

Use full validation, not checkpoint mode, for release. Mathlib is pinned to
v4.33.1 commit `0df444a360eaa60ab8c11dca51a86af692955474`; format only
`Mathlib/`, use width 100 and Lake cache. CSLib is pinned to
`98e395a701f2027a413ad24729e1a11a6c772eb4`, Lean v4.33.1, width 100.
The release gate includes clean, changed-module, and complete post-format builds.
Passing does not mean every protected physical line fits width 100.
