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

## Progress

### Current checkpoint: protected lines and flowing delimiters

A retained protected span protects its complete shared physical source line.
Recovery must not wrap only the final argument of an inline sequence such as
`obtain result := proof; refine next; rw [h]`. Required indentation may leave
that line over width; this is accepted protected layout. Semicolon regrouping
and new separator rules are not planned. Source-preservation planning rejects
partial recovery while keeping recovery on separate source lines available.

Focused tests cover protected neighbors on either side, a separate-line control,
the moved Mathlib-shaped sequence, accepted overflow diagnostics, preservation,
and idempotency. A protected theorem equation arm also keeps its authored line
and relative continuation layout. The complete local gate passed after
self-formatting, with no fixture changes or remaining formatting drift.

The staged probe-placement changes remain intact. The additional rule fix gives
flowing parser-owned collections the existing closing-delimiter attachment
contract. Fit probes reserve the closer's width, so the final item wraps with
`]` instead of leaving it on a separate line. Balanced collections retain their
existing shape, and line-breaking comments still force a boundary.

Coverage includes a proof moved into a deeper alternative, a closing bracket
after a line comment, fitting semicolon runs, preservation, and idempotency.
No renderer change, syntax-specific exception, or rule API is added.

Final light checks passed on pristine inputs with automatic worker counts:

| Project | Scope | Formatter/check time | Changes from delimiter candidate |
| --- | --- | --- | --- |
| GraphQL | 280 files, width 90 | 53s | 0 |
| quantum | 20 owned files; 1 unowned skipped, width 90 | 41s | 0 |
| CSLib | 200 files, width 100 | 132s | 0 |
| Mathlib | 98 files, width 100 | 191.37s | 16 |

Preservation, actionable-overflow, idempotency, and fallback checks passed;
Mathlib missing-rule checks also passed. All 16 Mathlib policy-change diffs were
reviewed: every added line matches an authored source line apart from indentation.
Protected tactic runs, headers, and continuations retain their source layout.
`Mathlib/Algebra/Module/PID.lean:199` keeps its complete semicolon line at 102
characters, with no formatting exception. Its surrounding fitting header also
stays protected. The earlier flowing-delimiter improvements remain intact.

An isolated before/after/after/before comparison on pristine `PID.lean` passed
all checks. Mean user CPU time was 8.33s before and 8.52s after, a 2.3% difference.
Wall samples were 17.20s/10.84s/10.79s/10.63s; the first baseline run dominates
the wall average, so these do not establish a speedup or project-wide scaling.

Target-project builds and the complete Mathlib sweep were omitted in this final
light gate. Mathlib has 40 differences from the older build baseline, rather
than just the 16 policy-change differences above. Do not treat either
interrupted full validation attempt as a completed release gate.

### Next checkpoint: complete release gate

Run complete validation on pinned CSLib and all 8,311 selected Mathlib files with
the final candidate. Require exception and independent idempotency checks,
changed-module builds, complete post-format builds, and visual review.
Do not exempt new actionable overflows or detach comments and closing delimiters.
Intact protected source lines may exceed width after required indentation.
Stop for review if another fix needs a design change.

### Later checkpoint: accepted-piece reuse

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

## Evidence

The staged snapshot remains `.scratch/release-probe-placement/staged.patch`,
SHA256 `b84a7cb1e783a26ebbe2456e3c885b6b942b41aead20a5c9cb54cb9b8a4a5001`.
Its rebuilt formatter under `.scratch/recovery-staged-baseline/` exactly matches
SHA256 `91928d3987f91bcf8df929f8250ffddd58f30efffd4326725115f163f8979ba3`.

The delimiter-only comparison baseline is `.scratch/bracket-checkpoint-fmt`, SHA256
`43fe39228410c8561417dc4320bcd82d736e27f1e714e70edb8d08192194b571`.
The final formatter is frozen as `.scratch/protected-lines-fmt`, SHA256
`4e20c39fe1ae940d589b5555ccad99a12c946ad2f27c2a7fa4263cafc4ab95fa`.
The complete local gate is recorded in `.scratch/protected-lines-check-final.log`;
fixture regeneration and self-format checks are in
`.scratch/protected-lines-fixtures.log` and `.scratch/protected-lines-self.log`.
External logs and review patches are under `.scratch/protected-lines-validation/`.
Its Mathlib `bracket-comparison/review.patch` isolates the shared-line policy
change from the delimiter-only candidate. Mathlib output remains staged under
`.scratch/external-validation-release/mathlib/.lake/leanfmt-protected-lines/`.
Isolated timing logs are under `.scratch/protected-line-performance/`.

Interrupted full-gate logs, output snapshots, and review patches are under
`.scratch/release-probe-placement/` and `.scratch/release-recovery-consistency/`.
The latter candidate's semicolon changes were withdrawn; its timings and full
CSLib build do not by themselves validate the final subset.
The semicolon reproduction and trace are
`.scratch/ReviewSemicolonRecovery.lean` and
`.scratch/release-probe-placement/semicolon-peer-review.log`.
External formatting output is never the source of a formatter fix.
