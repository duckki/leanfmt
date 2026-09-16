# Version 0.4 plan

Rules describe general syntax ownership. External paths and declaration names
are evidence for tests, never formatter conditions. Missing-rule coverage is
release-blocking only for Lean's standard library and Mathlib.

## Open Issues

### Custom-command replay resource cost

```lean
theorem certificate_check : certificateValid = true := by
  expensiveProof
setup_benchmark runChecksum n => n * n
```

Hex's `bench/HexGFqField/Bench.lean` triggers complete-prefix replay at its first
`LeanBench.setupBenchmark` command (line 805). An isolated run reaches 6 GiB in
50s even with one worker. Full Hex formatter validation therefore remains blocked
in batch 7 of 9; no formatter diagnostic preceded the memory stop. Unknown handlers
must still receive the complete preceding declarations and proofs. This needs a
reviewed custom-command effect contract, not a project-specific skip rule.

## Progress

### Custom-command effect contract

Establish how external commands can safely expose parser effects before expanding
postponement beyond audited handlers. Preserve complete observer state, overridden
handler behavior, and independent idempotency parsing. Use the isolated Hex
benchmark file as the resource control, then resume complete Hex validation under
a compressed-inclusive memory bound.

### Release validation

Run the complete release gate after review of the parser-classification change.
Formatter-only Hex checks do not replace changed-module and post-format builds.
Retain `HexGF2/Clmul.lean` as an isolated performance control and compare with
identical inputs, exact imports, diagnostics, and worker limits. The old 469s
full-project timing covered a different file set and is not a comparable baseline.
A formatting or parser change requires a fresh release gate; earlier results do
not validate later changes.

## Deferred Optimization Opportunities

These opportunities remain deferred. They are performance costs, not known
formatting-correctness failures.

### Required prefix elaboration cost

```lean
theorem evidence : True := by trivial
attribute [local simp] evidence
```

Standalone attributes, deriving, and unaudited declaration metadata retain
complete-prefix replay. Hex's `HexGF2/Basic.lean` exercises
remaining `ext` and `inline` metadata costs. Audit active implementations before
extending the neutral-effect classifier; attribute spelling alone is insufficient.
Unknown handlers must still observe complete declarations, proofs, and attributes.
Native snapshots require unchanged syntax and positions, so do not share final
state with independent idempotency parses or guess source dependencies.

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
