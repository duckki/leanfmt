# Version 0.4 plan

Rules describe general syntax ownership. External paths and declaration names
are evidence for tests, never formatter conditions. Missing-rule coverage is
release-blocking only for Lean's standard library and Mathlib.

## Open Issues

### Required command replay memory

```lean
private theorem packedCert_check : certificateValid = true := by decide
-- More certificate definitions follow.
#guard checkCertificate certificate = true
```

Hex's `conformance/HexGFq/CrossCheck.lean` still exceeds the 6 GiB validation
budget. An isolated parser trace reaches 6.16 GiB in 18.8s during the prefix replay
from line 974 through the `#guard` at line 1110. The resumed formatter stops in
batch 9 of 9; the other 72 files pass independently. Source files remain untouched
and output remains staged. No formatter
diagnostic precedes the resource stop. `#guard` and unknown handlers still receive
complete preceding declarations and proofs. Do not bypass them or substitute
incomplete proof state to claim a passing validation.

## Progress

### Required replay memory checkpoint

Profile the remaining cross-check prefix against native Lean elaboration to
separate unavoidable proof cost from retained frontend state. Reduce retention only
with equivalent observer state and independent idempotency parsing. Any broader
effect classification needs a separate audit; do not add a blanket `#guard`
exemption. Complete batch 9 under a compressed-inclusive memory bound before
claiming the Hex checkpoint.

### Release validation

Run the complete release gate after review of the parser-classification change.
Formatter-only Hex checks do not replace changed-module and post-format builds.
Use `LEANFMT_VALIDATION_PARSER_INTEGRATION=lean-bench` for the audited Hex
dependency version; the adapter is explicit and is not enabled by default.
Retain `HexGF2/Clmul.lean` as an isolated performance control and compare with
identical inputs, exact imports, diagnostics, and worker limits. The old 469s
full-project timing covered a different file set and is not a comparable baseline.
A formatting or parser change requires a fresh release gate; earlier results do
not validate later changes.

## Deferred Optimization Opportunities

These opportunities remain deferred. They are performance costs, not known
formatting-correctness failures.

### Required prefix elaboration and evaluation cost

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
Explicit parser-neutral contracts can avoid unnecessary replay but cannot bound
arbitrary proof elaboration that a later unaudited observer requires.
Hex's `conformance/HexNumberFieldTower/Conformance.lean` passes formatting and
diagnostics but takes 429s with one worker. A stack sample shows `#guard` expression
evaluation through Lean's IR interpreter during convergence replay, not layout
search. Establish a same-input baseline before calling this a regression; retain
independent parsing and complete state when investigating reuse.

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
subject to complete-state equivalence for commands without a neutral contract.

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
