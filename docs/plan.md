# Version 0.4 plan

Rules describe general syntax ownership. External paths and declaration names
are evidence for tests, never formatter conditions. Missing-rule coverage is
release-blocking only for Lean's standard library and Mathlib.

## Open Issues

### Whole-field proof-header attachment

```lean
left_inv f :=
  Subtype.ext <| funext <| Fin.forall_fin_two.2 <| by
    simp [← (show f.1 0 + f.1 1 = 1 by simpa using f.2.2)]
```

The inner proof header can stay intact, but the surrounding assignment still
breaks first. Keeping the whole field header inline needs a reviewed policy for
partial headers: lifting the proof to the assignment loses the value's base;
unconditional header flow changes assignment-first priority when declaration
parameters wrap. Keep the current priority and value ownership for this checkpoint.
No new rule API or renderer exception is approved for this remaining cosmetic case.

### Quoted continuation ownership

```lean
        if toDual then
          liftCommandElabM
          <| Command.elabCommand
          <| ←
        `(command| attribute [to_dual none] $(mkIdent tgt))
```

`Mathlib/Tactic/CategoryTheory/Reassoc.lean` still leaves the quotation at its
old source indentation when an enclosing match arm moves right. A core-only
reproduction confirms the same lost relative indentation. Review the layout
anchor shared by the `←` wrapper and protected quotation; preserve quotation
contents and comment boundaries. This is separate from the corrected fitting
quotation followed by `>>=`. The current checkpoint leaves this ownership change
for review, with its reproduction and trace in
`.scratch/visual-placement-final/quoted-pipe-trace.log`.

## Progress

### Checkpoint 1: tactic-header consistency (complete)

Keep configured tactic prefixes attached to their bracketed arguments. Recover
flowing collections through conversion sequences and distinguish collection row
separators from semicolons inside nested proofs. Reuse existing syntax ownership
and collection rules, without new rule APIs. Cover direct, configured, wrapped,
and indentation-recovery cases. The complete local gate passed, including all
fixtures, self-formatting, preservation, overflow, and idempotency checks.

Light validation passed on 280 GraphQL, 20 owned quantum, 200 CSLib, and 127
Mathlib files. GraphQL, quantum, and CSLib output is unchanged; all 12 Mathlib
differences are attached configured headers or flowing tactic collections.
GraphQL checks took 53s, quantum 42s, and CSLib 152s. Isolated Mathlib checks took
221.94s baseline and 234.04s candidate; user CPU increased from 1272.24s to
1291.72s (1.5%). These samples do not establish a speedup or a material CPU
regression. Mathlib missing-rule checks passed; quantum's one unowned file was
skipped. All changed Mathlib modules built successfully (3,345 Lake jobs including
dependencies); complete project builds are reserved for the final gate. Evidence
is in `.scratch/visual-headers-final/`.

### Checkpoint 2: protected placement and header fit (complete)

Preserve each protected fragment's relative indentation at its enclosing base.
Keep `have := calc` attached and distinguish leading source breaks from retained
interior breaks in whole-tree and sliced fit checks. Treat attached prefix groups
consistently during overflow recovery. Expose terminal infix proof headers without
moving their bodies out of the value's ownership. Preserve authored rewrite-arrow
breaks as an accepted source-layout compromise, with regression coverage.
Whole-field attachment and moved quotation ownership stop at the review questions
above. Complete the final CSLib/Mathlib release gate before closing visual review.

The complete local gate passed. Light checks passed on 280 GraphQL, 20 owned
quantum, 200 CSLib, and 127 Mathlib files. GraphQL and quantum output is unchanged.
All six CSLib and 35 Mathlib output differences were reviewed: attached `calc`
introducers, compact infix proof headers, required multi-tactic body breaks,
corrected protected indentation, and fitting quotation/infix expressions. Existing
fixtures are unchanged; a new fixture covers the corrected layouts. The explicit
semicolon-proof regression test added during external review passed the complete
local rerun. All changed Mathlib modules and dependencies built successfully
(3,341 Lake jobs). CSLib's changed-module build (1,689 jobs) and complete project
build (2,800 jobs) passed. GraphQL and quantum outputs are unchanged, so their
target-project builds were not rerun in this light gate.

| Project | Checkpoint 1 checks | Checkpoint 2 checks | Changed outputs |
| --- | --- | --- | --- |
| GraphQL | 53s | 48s | 0 / 280 |
| quantum | 42s | 37s | 0 / 20 owned |
| CSLib | 152s | 103s | 6 / 200 |
| Mathlib, paired pristine inputs | 192.27s | 189.68s | 35 / 127 |

Mathlib user CPU was 1189.73s versus 1211.00s (+1.8%); wall time was 1.3% lower.
These single comparisons show no material performance regression, not a controlled
speedup. All formatter safety checks passed, including Mathlib missing rules.
A character-width scan found three newly over-width Mathlib lines: two protected
`show` bodies in `Limits/Final.lean` (102 columns) and one intact proof line in
`Matrix/Nonsingular.lean` (105). They retain source code at its corrected owning
indentation and remain accepted protected-line overflows. CSLib has none.

The `Monoidal.induced` argument break matches an authored break before a multiline
record and is consistent with the application rule. Authored rewrite-arrow breaks
remain accepted and covered. Whole-field attachment and quoted-continuation
ownership remain open above; do not declare the visual review or release gate
complete. Evidence is in `.scratch/visual-placement-final/`.

### Validated candidate: comment processing cost

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
the complete Mathlib sweep were omitted from that light run; full results follow.

### Previous complete gate: 812f244

Committed candidate `812f244` passed the complete automated gate. Logs and output
comparisons are retained under `.scratch/release-812f244/`. The two checkpoints
above supersede its formatter output; their remaining issues are listed at the
top of this plan. These earlier full-build results do not validate later changes.

The fresh local gate and complete CSLib validation passed. CSLib checked all 200
files, rebuilt changed modules, and passed its complete post-format build in
277.40s. Its output exactly matches the previous baseline. Existing whitespace
warnings around third-party custom notation remain unchanged. Mathlib's Lake
cache, complete pre-format build, and all 84 formatter batches passed on 8,311
files. Preservation, actionable-overflow, fallback, independent idempotency,
and missing-rule checks passed. Staged output was applied, changed-module builds
passed, and the complete post-format build passed all 8,705 Lake jobs.

| Mathlib phase | Wall time |
| --- | --- |
| Formatter and checks, all 84 batches | 7,636s |
| Changed-module builds | 3,706s |
| Complete post-format build | 57s |
| Complete validator, including setup and application | 11,676.65s |

The complete comparison has 485 differences from the older full formatted
baseline, all covered by the 84 batch reviews. The candidate changes 7,843 files
from pristine upstream source. Read-only review, two focused Lean checks, and a
short renderer trace ran alongside validation; these full-run timings are not a
controlled before/after performance comparison.

The gate is not warning-free. Long comments, intact protected source lines, and
long-file warnings remain; sampled notation-whitespace warnings match the prior
formatted baseline. A character-width cross-check of all 485 changed outputs
found ten newly overflowing lines, all retained source lines or protected headers
at their new owning indentation. No new actionable overflow was identified.

Keep the final candidate fixed for complete validation on pinned CSLib and all
8,311 selected Mathlib files. Require exception and independent idempotency checks,
changed-module builds, complete post-format builds, and visual review.
Do not exempt new actionable overflows or detach comments and closing delimiters.
Intact protected source lines may exceed width after required indentation.
Stop for review if another fix needs a design change.

The earlier visual inventory and reproductions remain in
`.scratch/release-812f244/review-notes.md` and
`.scratch/release-812f244/mathlib-review/`. Resolved findings are no longer open
tasks; the current disposition is recorded in the two checkpoints above.

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
