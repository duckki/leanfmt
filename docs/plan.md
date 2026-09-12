# Version 0.4 plan

Rules must describe general syntax ownership. External paths and declaration
names are evidence for tests, never formatter conditions. Missing-rule coverage
is release-blocking only for Lean's standard library and Mathlib.

## Open Issues

### Conditional chains across comments

```lean
if firstCondition then
  firstValue
else
  -- This comment separates the nested condition.
  if let some value := optionalValue then
    secondValue
  else
    fallback
```

Plain `else if let` still gains an extra nesting level (`Lean/Expr/Basic.lean:407`).
Extending the existing flat chain to pattern conditions fixed that case but exposed
incorrect branch indentation across the comment in `Tactic/Translate/Core.lean:619`.
That extension was withdrawn. Preserve conditional header/body ownership across
unremovable comment breaks before generalizing chains; do not introduce comment
tokens into the tree or token-specific renderer exceptions. Both paths are relative
to `Mathlib/`. The comment-free and commented forms need joint regression coverage.

### Required prefix elaboration cost

```lean
theorem evidence : True := by trivial
attribute [local simp] evidence
```

Attributes, deriving handlers, wrappers, and unclassified commands still receive the
complete preceding source state, including declaration bodies. This required replay
dominates the targeted Mathlib timings; avoiding standalone option-command replay does
not materially reduce the sample's CPU cost. The remaining cost is not a known
formatting failure. Do not reduce it by skipping proof bodies, guessing dependencies,
or adding attribute exceptions. Lean 4.33.1 has no audited source-dependency replay API.

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

Authored multiline tactic text remains protected even when structural reindentation
makes a line exceed width 100. `CategoryTheory/DifferentialObject.lean:152` grows from
99 to 103 characters; a `simp_rw` continuation in `Algebra/Group/ForwardDiff.lean:281`
grows from 97 to 101. Both paths are relative to `Mathlib/`. These warnings also occur
in the previous full-build baseline, and are exempt from actionable-overflow checks.
The indentation follows the current design. Reflowing their bracketed lists requires
a protected-proof policy decision; do not add tactic-specific rules or indentation
exceptions to suppress the warnings.

## Progress

### Current checkpoint: scope effects and reviewed ownership consistency

Standard standalone `set_option` uses the existing scope path. Its audited handler
updates options and the cached recursion limit without observing deferred declarations.
Scoped wrappers and replaced handlers retain complete frontend replay.

The complete local gate, GraphQL and quantum lightweight checkpoints, and complete
CSLib and Mathlib validation passed for that candidate with unchanged output.
Controlled timings show no material performance change from the standalone-option
classification.

The subsequent 63-file design review found four existing consistency defects. Three
low-risk fixes reuse empty-header attachment, nonempty-child selection for optional
`try` clauses, and declaration-base inheritance for plain `suffices ... from`.
Three focused regressions cover those fixes. The conditional-chain extension was
withdrawn after its comment interaction surfaced. No renderer or rule API changes
are involved. The complete local gate passed again, with no fixture changes or final
self-formatting drift. Final follow-up checks passed with zero enabled diagnostics:

| Scope | Formatter time | Output review |
| --- | --- | --- |
| GraphQL, 280 files | 32s | Unchanged |
| quantum, 20 owned files, one skipped | 41s | Unchanged |
| CSLib, 200 files, width 100 | 82s | Unchanged |
| Mathlib, 36 pristine files, width 100 | 98.96s | Five reviewed improvements |

The small-project times are close to the previous checkpoint's 31s, 41s, and 82s;
they do not indicate a material regression, but are not controlled benchmarks.
Mathlib's five changed modules built successfully in 8.02s (2,895 jobs, mostly reused).
The additional changes in `SobolevInequality` correctly indent anonymous `have := calc`
bodies; `SetTheory/Lists` shares the `suffices` base fix. The other 31 sampled files
match the pre-review baseline, including both conditional files after withdrawal.
GraphQL, quantum, and CSLib used checkpoint mode without project builds. The complete
Mathlib sweep and aggregate build were not repeated after these three layout fixes.
This closes the lightweight follow-up checkpoint, not the final 0.4 release gate.

### Pre-review full gate: passed

The complete local gate passed again with no fixture or self-formatting drift.
Fresh clones under `.scratch/external-validation-release/` preserve the prior review
clones. Both projects use their pinned v4.33.1 revisions and width 100; only `Mathlib/`
is selected for Mathlib. Logs and review patches are under `.scratch/release-gate/`.

CSLib passed all 200 files and both post-format builds in 369 seconds. Its 173 changed
sources have byte-identical output to the preceding checkpoint. Formatter checks took
110 seconds, versus 137 in the earlier complete parser-safety run; these are full-run
observations, not controlled benchmarks. Existing custom-notation whitespace-linter
warnings remain non-blocking.

Mathlib cache retrieval, the pristine 8,705-job build, and source resolution passed.
All 8,311 selected files passed the 84 formatter batches with zero diagnostics. The
complete output is byte-identical to the preceding checkpoint, including the integral,
valuation, scoped-notation, widget-token, and annotation-comment regressions. Checks
took 7,381 seconds versus 6,939 in the earlier fresh-source parser-safety run, about
6% higher. This is not comparable to the faster already-formatted checkpoint sweeps.
All 7,843 changed modules built successfully in 3,574 seconds, followed by the
8,705-job aggregate build in 50 seconds. Complete Mathlib validation took 11,306
seconds. Three read-only reviews covered 63 changed files: 22 complete diffs in
parser/tactic/data areas, 20 complete diffs in category/ring/geometric areas, and
seven complete diffs plus selected hunks in 14 algebra/analysis-related files.
Their four consistency findings are tracked above; both protected-tactic width
examples were confirmed consistent with the current design. This was a sampled
design review, not an exhaustive manual inspection of all 7,843 changed files.
Build-time width warnings must be distinguished from formatter diagnostic failures:
preserved tactic and comment lines can exceed 100 characters under the current policy.
The build logs contain 538 distinct long-line warnings and 20 long-file warnings;
successful validation does not mean every physical line is within width 100.

### Next checkpoint: conditional ownership design review

Make ordinary, dependent, and pattern conditionals consistent without flattening
away the owner of a branch after a comment-forced header break. Evaluate explicit
header/body ownership within chain clauses before changing renderer base handling.
Require comment-free, line-comment, and multiline-comment cases together, followed
by the complete CSLib/Mathlib release gate. Stop for review before implementing this
structural change.

### Later: review protected-proof width policy

Decide whether authored multiline tactic lists should remain protected after
reindentation exceeds the requested width. If that policy changes, express ownership
in the tree and use general renderer recovery, with focused tests for preservation,
indentation, and idempotency. Do not add `rw`/`simp_rw` rules or indentation exceptions.
The decision requires review before implementation. Required prefix replay remains
authoritative; further performance work must not skip observable declaration bodies.

## Validation standard

Every checkpoint runs:

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

Generated fixture and self-format changes require visual review. External runs
use automatic worker counts; do not pass `--jobs`. Routine GraphQL and quantum runs
use complete validation. When lightweight validation is requested, use `--checkpoint`
with their recorded build baselines and CSLib's width-100 baseline, then select Mathlib
files covering the changed parser/layout path and existing safety regressions. Keep
missing-rule checks enabled for Mathlib only. Report the exact sample and omitted
builds; do not extrapolate sample timings to the whole corpus. Hex and Mathlib use
width 100, with complete builds reserved for the release gate.

Mathlib validation uses exact `v4.33.1` commit
`0df444a360eaa60ab8c11dca51a86af692955474`, formats only `Mathlib`, and uses
the Lake cache. The release gate recreates or resets the validation clone and
runs the clean, changed-module, and aggregate post-format builds. Later
formatter-only reviews may reuse that exact baseline when its revision,
toolchain, selector, and source manifest remain unchanged.

### Candidate and evidence

The input baseline is `5ef1051` (deferred ordinary mutual declarations), following
`896f11b` (authoritative prefix replay). The parser change adds Lean's standard
standalone option handler to the existing scope classification. Its implementation
was audited in Lean 4.32.0, 4.33.0, and 4.33.1. Registered handler lookup still guards
the quiet path; no opaque command is executed speculatively on an incomplete environment.

Tests cover option state and replay parity plus all three retained layout fixes.
Controlled scope-option benchmarks showed stable user CPU: GraphQL used
114.36-114.49s before and 114.19-114.51s after; a 13-file Mathlib sample used
68.61-69.63s before and 68.31-68.77s after. These preceded the layout follow-ups;
their artifacts use `.scratch/scope-options-*`. An older incomplete-state parser is
not an equivalent correctness baseline. Hex was not rerun; its clone is absent.

The new full-build baselines and formatter batch logs are under
`.scratch/external-validation-release/logs/`. CSLib is pinned to
`98e395a701f2027a413ad24729e1a11a6c772eb4` with Lean v4.33.1. Release logs,
before/after review patches, phase summaries, and the pre-review formatter source
patch against `5ef1051` are under `.scratch/release-gate/`. Follow-up logs, the 36-file
source list, five-module build list, reviewed diff, and final source snapshot are
under `.scratch/release-gate/consistency/`. Each snapshot was checked against the
source used for its validation. Original clones under `.scratch/external-validation/`
remain intact; the new release Mathlib clone includes the five reviewed improvements.
