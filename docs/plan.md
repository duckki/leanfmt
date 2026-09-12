# Version 0.4 plan

Rules describe general syntax ownership. External paths and declaration names
are evidence for tests, never formatter conditions. Missing-rule coverage is
release-blocking only for Lean's standard library and Mathlib.

## Open Issues

### Width-induced inline-comment chain breaks

```lean
def longComment (a b : Bool) : Nat :=
  if a then
    1
  else /- This single line block comment occupies nearly all of the available space on this line. -/ if b then
    2
  else
    3
```

At width 100, the inline block comment above pushes `if` onto the next line,
while its branches still use the outer base. Source-forced comment breaks are
now handled separately; this case needs a width-aware continuation choice, not
a source-column estimate or an exception for long comments. Keep fitting inline
block comments joined.

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

### Current checkpoint: conditional ownership revision

The implementation retains complete conditional continuations in the syntax
tree. Layout preparation flattens uninterrupted runs, stopping at a line comment
or a block comment containing a newline between `else` and `if`. Each resulting
run uses the existing balanced rule and its own base. Ordinary, dependent, and
pattern clauses can chain together. No rule API, shared balance state, comment
nodes, or renderer indentation exceptions were added.

The focused suite adds 44 exact-output checks plus syntax ownership and token-order
assertions. Original and formatted examples elaborate, preserve code and syntax,
and converge idempotently. Existing conditional tests pass. Fixture regeneration
has no changes. Self-formatting joins a few existing pattern-condition chains;
Driver sources are unchanged.

The final local gate passed: build, unit suite, development linter, fixture and
self-format dry checks, preservation, actionable overflow, and idempotency.
External checks passed on the final implementation:

| Project | Scope | Formatter/check time | Output versus preceding checkpoint |
| --- | --- | --- | --- |
| GraphQL | 280 files | 31s | Unchanged |
| quantum | 20 owned files; 1 unowned skipped | 40s | Unchanged |
| CSLib | 200 files, width 100 | 83s | Unchanged |
| Mathlib | 36 pristine files, width 100 | 100.56s | 3 changed, 33 unchanged |

All formatter diagnostics passed, including missing rules for Mathlib. The three
Mathlib changes join pattern chains in `Lean/Expr/Basic.lean` and
`Tactic/ITauto.lean`, and restore comment-separated continuation ownership in
`Tactic/Translate/Core.lean`. Visual subagent review found no additional
regressions. All three changed modules built successfully; the final identical
output rerun reused those artifacts. Existing protected-line warnings remain.

A serial ABBA comparison on 13 identical Mathlib sources measured mean user CPU
time of 68.975s before and 69.02s after, effectively unchanged. Sharing unchanged
subtrees removed the first implementation's roughly 4% overhead. Synthetic
32/64/128/256-clause probes also showed no material slowdown.

GraphQL, quantum, and CSLib used checkpoint mode with target-project builds
omitted. The full Mathlib sweep and aggregate build were not repeated. Do not
treat this as a complete CSLib/Mathlib release gate. The comparison baseline is
`1c0d582`; original full-gate evidence is retained under `.scratch/release-gate/`.

### Next checkpoint: width-aware continuation review

Retain complete continuation ownership when a width-driven inline-comment break
moves `if`. Keep fitting inline block comments joined, and preserve the current
source-forced chain boundaries. Prototype a layout-time choice using actual
placement; do not make syntax regrouping or line-break rules read comment text
or guess rendered columns. Stop for review if this needs a new layout contract.

Require narrow and wide widths, nested parenthesis/application bases, and multiple
continuations, followed by the local gate and targeted external review. The full
release gate remains required before declaring the candidate ready.

### Later: protected-proof width policy

Decide whether authored multiline tactic lists should remain protected after
reindentation exceeds the requested width. Any policy change must express
ownership structurally and use general renderer recovery, with preservation,
indentation, and idempotency coverage. No `rw`/`simp_rw` rules or indentation
exceptions. Review the policy before implementation.

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

The full-build baselines and batch logs are under
`.scratch/external-validation-release/logs/`. The preceding full gate passed
200 CSLib files and all 8,311 selected Mathlib files, then changed-module and
aggregate builds. The retained three-fix follow-up at `1c0d582` passed the local
gate, GraphQL/quantum/CSLib checkpoints, and a 36-file pristine Mathlib sample
with five changed-module builds; the full Mathlib sweep was not repeated afterward.

Current checkpoint artifacts use `.scratch/conditional-chain-*` and
`.scratch/conditional-chain-validation/`. Prior parser/layout evidence remains
under `.scratch/release-gate/consistency/`. Original external clones remain
available for review. No external formatting change should be used as the
source of a formatter fix.
