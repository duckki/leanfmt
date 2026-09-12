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

### Current checkpoint: fitting do conditionals

Fitting `do` conditionals remain inline unless the source supplies branch breaks.
Single `if/else` statements now use the same branch-owner representation as
chains, so width-driven or authored breaks balance both branches together.
Early returns without `else` also preserve authored breaks without forcing new
ones. Statement sequences retain their mandatory boundaries. Comment-separated
chain ownership from `ee92d52` is unchanged. No new rule API or renderer behavior
is introduced.

The 34 new exact-output checks cover ordinary, dependent, pattern, mixed, and nested
conditionals; semicolon bodies; following statements; line/block comments;
manually broken branches and chains; and width-driven balanced layout. Tests
check exact output, elaboration, syntax ownership, preservation, and idempotency.

The complete local gate passed: build, unit suite, lint, fixture and self-format
dry checks, preservation, actionable overflow, and idempotency. Fixtures are
unchanged; self-formatting only adjusted the new test code. Three existing
expectations now retain fitting inline conditionals. Renderer code is unchanged.

External checks started from pristine sources, not previous formatter output:
otherwise honoring authored breaks would conceal the newly optional boundaries.
Previous outputs are retained for comparison. All formatter diagnostics passed,
including missing rules for Mathlib only:

| Project | Scope | Formatter/check time | Changed output files |
| --- | --- | --- | --- |
| GraphQL | 280 files | 46s | 0 |
| quantum | 20 owned files; 1 unowned skipped | 41s | 0 |
| CSLib | 200 files, width 100 | 117s | 1 |
| Mathlib | 36 pristine files, width 100 | 99.93s | 9 |

CSLib's namespace linter retains two inline early returns. Mathlib changes retain
short inline branches and two conditional assignments. The longest added line is
92 characters. All nine changed Mathlib modules built in 20.02s, and the changed
CSLib module built in 1.24s. Existing protected-line warnings remain. Project-wide
builds and the full Mathlib sweep were omitted; this is not the release gate.

Code and visual reviews found no actionable issues. Review against each clone's
`HEAD` confirmed that every collapsed branch was already inline in the original
source; authored branch breaks remain preserved. A serial ABBA comparison against
`ee92d52` on 13 identical Mathlib inputs measured mean user CPU time of 71.435s
before and 69.72s after, with no observed performance regression. Pristine-source
timings above are not directly comparable to checkpoints that reformatted
previously formatted sources.

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

Current checkpoint artifacts use `.scratch/compact-do-*`. The preceding
conditional-ownership checkpoint at `ee92d52` passed the local gate,
GraphQL/quantum/CSLib checkpoints, and a 36-file pristine Mathlib sample with
three changed-module builds and effectively unchanged performance. Its artifacts
remain under `.scratch/conditional-chain-*`. Prior parser/layout evidence remains
under `.scratch/release-gate/consistency/`. Original external clones remain
available for review. No external formatting change should be used as the
source of a formatter fix.
