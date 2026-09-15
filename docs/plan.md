# Version 0.4 plan

Rules describe general syntax ownership. External paths and declaration names
are evidence for tests, never formatter conditions. Missing-rule coverage is
release-blocking only for Lean's standard library and Mathlib.

## Open Issues

### Overflow retry and suffix ownership

```lean
  <|
    show result by
      proof
```

The generic overflow retry can separate a protected operand from `<|`, even
when its first line fits. Restricting retries to rule breakpoints also exposes
actionable overflow in long proofless `:= calc firstTerm` headers. Such headers
can also detach without moving their row base:

```lean
  calc a * x
  _ = y := proof
```

The rows should be one level beneath the rendered `calc`. Comment-detached calc
blocks are fixed, but that does not repair this header-retry path. Design the
legal header/body boundaries and base propagation together before removing the
fallback; do not add a protected-operand exception. Evidence: `Multiplier`,
`Semiconj/Units`, and `Deriv/Slope` in Mathlib. The retained consistency fixes
pass the complete local gate and 13-file Mathlib diagnostic/idempotency checks;
a fresh full gate is still pending. This attachment-policy issue remains for
review.

## Progress

### Review suffix boundary ownership

Agree where a proofless calc header may wrap while keeping `calc` with its
initial term and moving its row base consistently. Add focused width and
protected-operand coverage, then restrict overflow retries to boundaries
represented by that policy. No new rule API or syntax-specific renderer branch
without design review.

### Release gate

Freeze the final candidate and fully validate pinned CSLib and all 8,311 selected
Mathlib files at width 100. Require exception and independent idempotency checks,
changed-module builds, complete post-format builds, and visual review. Earlier
full-gate results do not validate later formatter changes. Accept intact protected
lines at required indentation; investigate every new actionable overflow.

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

Review all generated fixture and self-format changes. Use automatic worker
counts; do not pass `--jobs`. Lightweight checkpoints use recorded GraphQL,
quantum, and CSLib build baselines plus pristine Mathlib safety regressions.
Report scope and omitted builds. Compare performance on identical inputs without
concurrent validation. Enable missing-rule checks for Mathlib only.

Use full validation, not checkpoint mode, for release. Mathlib is pinned to
v4.33.1 commit `0df444a360eaa60ab8c11dca51a86af692955474`; format only
`Mathlib/`, use width 100 and Lake cache. CSLib is pinned to
`98e395a701f2027a413ad24729e1a11a6c772eb4`, Lean v4.33.1, width 100.
The release gate includes clean, changed-module, and complete post-format builds.
Passing does not mean every protected physical line fits width 100.
