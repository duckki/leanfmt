# Version 0.4 plan

Rules must describe general syntax ownership. External paths and declaration
names are evidence for tests, never formatter conditions. Missing-rule coverage
is release-blocking only for Lean's standard library and Mathlib.

## Open Issues

### Required prefix elaboration cost

```lean
theorem evidence : True := by trivial
attribute [local simp] evidence
```

Attributes, deriving handlers, and unclassified commands still receive the complete
preceding source state, including declaration bodies. Declaration-only `mutual` blocks
no longer force premature replay. GraphQL now takes 21.34-21.59 seconds versus
72.15-79.19 before this optimization, close to the older incomplete-state parser's
18.68-20.72 seconds. Aggregate user CPU time remains higher than that older parser:
about 113 versus 96 seconds. The remaining required replay cost is not a known
formatting failure. Do not reduce it by skipping proof bodies, guessing dependencies,
or adding attribute exceptions. Lean 4.33.1 has no audited source-dependency replay API.

## Progress

### Current checkpoint: defer ordinary declaration blocks

Implementation, the complete local gate, and lightweight external validation passed.
GraphQL, quantum, and CSLib output is byte-identical; the targeted Mathlib sample
has no formatting drift or diagnostics. The isolated GraphQL benchmark confirms
substantially lower wall and CPU time. No renderer, formatting-rule, or cache changes
are part of this checkpoint. A complete Mathlib sweep was not repeated.

### Next checkpoint: release gate

Require complete CSLib and Mathlib validation, with all selected sources checked and
post-format builds passing, output reviewed, and runtime recorded. Use those results
to decide whether any remaining replay hotspot needs further work. Close newly found
safety or formatting regressions before release; targeted checks and checkpoint-only
formatter sweeps do not replace these builds. Preserve authoritative replay for unknown
effects; do not add a dependency scheduler or cross-source cache.

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

### Current baseline

This change extends the authoritative-parser-state checkpoint based on `b6126ab`.
Handler lookup and syntax-dependent policy are separate. A `mutual` block can be
postponed only when its registered implementation and namespace/end handlers are
audited, every member is a standard declaration, and each member passes the existing
postponement policy. Preambles, custom member macros, attributes, deriving hooks, and
replaced handlers retain frontend replay. No command is executed speculatively on an
incomplete environment.

Focused tests cover deferred mutually recursive definitions, qualified theorem names,
actual theorem bodies visible to later observers, complete-frontend syntax parity,
and overridden block/member/scope handlers. The earlier conditional-notation,
source-order, parser-error, full-file-map, and replay-count regressions still pass.

The complete local gate passed, including the post-self-format rebuild and tests,
development linter, dry fixtures, preservation, actionable width, and idempotency.
Fixtures are unchanged. Self-formatting changed only the new implementation and tests.

Formatter-only checkpoints passed GraphQL (280 files), quantum (20 Lake-owned files;
one unowned source skipped), and width-100 CSLib (200 files). Every enabled diagnostic
was zero, and complete pre/post patches were byte-identical. Batched checks took
30, 40, and 77 seconds respectively. Project builds were deliberately omitted.

An alternating before/after GraphQL benchmark used the same 280 files, Lean 4.33.0,
diagnostic flags, and automatic workers with no concurrent builds or validation.
Wall time fell from 72.15-79.19 to 21.34-21.59 seconds, and aggregate user CPU time
from 305.13-305.41 to 112.89-113.06 seconds. `VisitedFragments.lean` formatting/checks
fell from 53.99-54.32 seconds to 240-301 ms; `Filter.lean` fell from 17.55-17.66 to
6.20-6.36 seconds. All benchmark output was unchanged.

The width-100 Mathlib sample included all 17 files containing a line-leading `mutual`
block, plus six existing parser/width regressions. Preservation, overflow, fallback,
missing-rule, and idempotency checks passed with no formatting drift. The one-pair
sample improved from 19.79 to 14.62 seconds; this is not a whole-corpus measurement.
The exact file list and logs are in `.scratch/mutual-replay-mathlib-sources` and
`.scratch/mutual-replay-*.log`. Hex was not rerun; its disposable clone is absent.

The pre-optimization authoritative-parser checkpoint passed all 8,311 Mathlib files
in 84 batches with zero diagnostics and byte-identical output. That full formatter
sweep took 3,679 seconds for checks and 3,786 seconds overall. It is the input baseline,
not full validation of the current optimization.

Mathlib's recorded full-build baseline is parser-safety commit `a6c4545`: all 7,843
sources changed from pristine passed the required module builds, followed by the
8,705-job full build. The later one-space repair in `Mathlib/Tactic/Monotonicity/Attr.lean`
also passed its 68-job module build. The current checkpoint reuses that baseline; it
does not repeat the aggregate release build. Baselines and batch logs are under
`.scratch/external-validation/logs/`.
