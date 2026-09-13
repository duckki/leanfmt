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

### Current checkpoint: comment processing cost

Keep the committed protected-line and delimiter behavior unchanged. Trivia
normalization scans ASCII delimiters and retains UTF-8 comment slices, avoiding
character-list allocation and reconstruction on every probe and retry. It adds
no cache, rule, renderer state, or parser shortcut. Independent character-based
tests cover nested and unterminated comments, Unicode, mixed line endings, and
both preserved-line and inline whitespace normalization.

Isolated before/after/after/before runs use `ac5b1db` as the baseline, width 512,
exception checks, and independent idempotency checks. All 36 outputs match:

| Cascading clauses | Baseline formatter time | Candidate formatter time | Reduction |
| --- | --- | --- | --- |
| 32 | 230.5ms | 183.5ms | 20.4% |
| 64 | 518.5ms | 428ms | 17.5% |
| 128 | 1,245ms | 1,093ms | 12.2% |

Values are means of two samples per binary, excluding environment startup.
Ordinary and short-comment controls remain within 2ms of the baseline means.
The larger chain still grows faster than linearly; this checkpoint does not
close cascading retry cost. Native prefix replay advances its completed
checkpoint, but still collects info trees. That flag is observable to command
elaborators; disabling it is not automatically semantics-preserving. Lean's
minimal command-line snapshots discard syntax, parser state, and command scope
needed by our parser, so they are not a compatible bookkeeping shortcut either.
Required prefix elaboration remains unchanged, not an optimization claimed here.

The complete local gate passed: build, unit suite, linter, fixture regeneration,
self-formatting, and final dry checks. Generated fixtures are unchanged; reviewed
self-format edits affect only the new code. The added info-state observer agrees
with Lean's frontend, preserves code, elaborates, and remains idempotent.

Light validation passed on pristine inputs with automatic worker counts:

| Project | Scope and width | Baseline checks | Candidate checks | Output differences |
| --- | --- | --- | --- | --- |
| GraphQL | 280 files, width 90 | 53s | 54s | 0 |
| quantum | 20 owned files, width 90 | 41s | 42s | 0 |
| CSLib | 200 files, width 100 | 132s | 116s | 0 |
| Mathlib | 98 files, width 100 | 191.37s | 174.49s | 0 |

Preservation, actionable-overflow, idempotency, and fallback checks passed;
Mathlib missing-rule checks also passed. Quantum's one unowned source remains
skipped. All four comparison patches are empty, including Mathlib's comparison
against the committed protected-line output. Protected shared lines and flowing
delimiters retain exactly that baseline's formatting.

Project times cover formatter/check phases, excluding compatible-formatter builds
and checkpoint setup. Mathlib user CPU was 929.39s versus 964.81s previously.
These single project runs show no regression, but are not controlled speedup
measurements like the alternating stress runs above. Target-project builds and
the complete Mathlib sweep were omitted; the release gate below remains open.

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

The committed baseline is `ac5b1db`, frozen as
`.scratch/protected-lines-fmt`, SHA256
`4e20c39fe1ae940d589b5555ccad99a12c946ad2f27c2a7fa4263cafc4ab95fa`.
The candidate is `.scratch/trivia-cost-fmt`, SHA256
`a3a5ab5766d011a9786ff88df06e54403b1a0f2d69e8ec7d59e9941a87c37105`.

The alternating stress runner is `.scratch/ProfileTriviaCost.sh`; its pristine
inputs, formatted outputs, and phase/wall/CPU logs are retained under
`.scratch/trivia-cost-performance/`. Local logs are
`.scratch/trivia-cost-unit.log`, `.scratch/trivia-cost-local.log`, and
`.scratch/trivia-cost-final.log`.

Light external logs and review patches are under
`.scratch/trivia-cost-validation/`. Compare Mathlib against
`.scratch/external-validation-release/mathlib/.lake/leanfmt-protected-lines/`,
not the older build baseline. The current output remains staged under
`.scratch/external-validation-release/mathlib/.lake/leanfmt-trivia-cost/`.
The empty `mathlib/protected-lines-comparison/review.patch` is the checkpoint
comparison; the default Mathlib review patch still compares against the older
build baseline and contains its existing 40 differences.

Interrupted full-gate logs remain under `.scratch/release-probe-placement/`
and `.scratch/release-recovery-consistency/`. Neither is a completed release
gate for this candidate. External output is never the source of a formatter fix.
