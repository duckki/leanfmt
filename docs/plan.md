# Version 0.4 plan

Rules must describe general syntax ownership. External paths and declaration
names are evidence for tests, never formatter conditions. Missing-rule coverage
is release-blocking only for Lean's standard library and Mathlib.

## Open Issues

### Authoritative prefix cost

```lean
mutual
  theorem first ... := by ...
  theorem second ... := by ...
end
```

Environment-observing commands now receive the complete preceding source state even
when incomplete-state execution would succeed. Attributes, deriving handlers, and
unclassified commands can therefore require more elaboration than before. The completed
corpus runs show unchanged output but higher runtime. An isolated GraphQL comparison
increased from 18.68-20.72 to 73.61-74.03 seconds; aggregate user CPU time increased
from about 96.2 to 310.5 seconds. This is a real regression, not just validation overlap.
Mathlib's formatter phases increased from 2,667 to 3,679 seconds across the same
8,311 files; unlike the GraphQL comparison, these were not alternating isolated runs.
Do not recover speed by skipping proof bodies, guessing dependencies, or adding
attribute exceptions. Lean 4.33.1 has no audited source-dependency replay API.

## Progress

### Current checkpoint: authoritative parser-state boundaries

Implementation and the local, GraphQL, quantum, CSLib, and Mathlib formatter gates
are complete. External output is unchanged, with no preservation failures, actionable
overflow, fallbacks, or idempotency failures. No renderer or formatting-rule changes
are part of this checkpoint. This is a correctness checkpoint, not a performance-clean
release candidate; the measured replay cost remains open.

### Next checkpoint: replay cost review

Profile the measured regression before selecting an optimization. Prefer reducing
repeated work within a file operation. Declaration-only `mutual` blocks are a promising
audit target: `VisitedFragments.lean`, which contains two mutual blocks, took about
55 seconds in the controlled run. Any extension of the quiet path needs an audit
of the actual registered implementation, frontend-equivalence tests, and explicit
handling of replacements and wrappers. Preserve full-prefix replay for unknown effects;
do not add a dependency scheduler or cross-source cache.

### Release gate

Require complete CSLib and Mathlib validation, with all selected sources checked and
post-format builds passing. Close any newly found safety or formatting regressions
before release; checkpoint-only formatter sweeps do not replace these builds.

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
use automatic worker counts; do not pass `--jobs`. GraphQL and quantum run their
complete validation because they are comparatively small. Hex and Mathlib use
width 100 and checkpoint mode during iteration, with complete builds reserved
for the release gate.

Mathlib validation uses exact `v4.33.1` commit
`0df444a360eaa60ab8c11dca51a86af692955474`, formats only `Mathlib`, and uses
the Lake cache. The release gate recreates or resets the validation clone and
runs the clean, changed-module, and aggregate post-format builds. Later
formatter-only reviews may reuse that exact baseline when its revision,
toolchain, selector, and source manifest remain unchanged.

### Current baseline

This checkpoint is based on `b6126ab`. Parser commands are classified by audited
macro/elaborator implementation names rather than syntax names or `isBuiltin`, which
also marks some locally registered handlers. Unknown, replaced, and mixed-policy
handlers use the existing bounded frontend replay. Attributes and deriving hooks also
force replay. Complete prefixes advance monotonically; original file maps, command-local
parser facts, independent idempotency, and per-file module reuse are retained.

The conditional-notation reproducer now preserves `branch%`; both original and formatted
files compile with Lean. Focused tests cover direct, wrapped, generated, attributed,
and overridden commands, environment absence queries, source order, option scopes,
theorem-body dependencies, syntax parity with the complete frontend, and replay counts.

The complete local gate passed, including the post-self-format rebuild and tests,
development linter, dry fixtures, preservation, actionable width, and idempotency.
Fixtures are unchanged. Self-formatting changed only the new implementation and tests.

Full GraphQL (280 files), quantum (20 Lake-owned files; one unowned source skipped),
and width-100 CSLib (200 files) passed with successful post-format builds and
byte-identical output. Final batched formatter checks took 123, 40, and 136 seconds
respectively; GraphQL and CSLib overlapped local checks. CSLib's full run took 152
seconds. An alternating before/after GraphQL benchmark used the same 280 files, Lean
4.33.0, diagnostic flags, and automatic worker counts with no other validation running.
Both runs produced no changes; wall and CPU timings are recorded in the open issue.
`VisitedFragments.lean` and `Filter.lean` are prominent replay-cost hotspots. The new
width-100 Mathlib checkpoint passed all 8,311 files in 84 batches with zero diagnostics,
including missing-rule checks. Its complete patch is byte-identical to the preceding
checkpoint, and the validator recorded zero changed sources, so there are no newly
changed modules to build. Formatter checks took 3,679 seconds and the run took
3,786 seconds overall. Independent subagent comparisons covered every selected file
against a separate preserved source baseline: all 8,311 were byte-identical, with
no missing files, aliases, or new formatting findings.

The preceding width-100 Mathlib checkpoint at `b6126ab` passed all 8,311 files in
84 batches with unchanged output. It took 2,667 seconds for formatter checks and
2,781 seconds overall. This is the comparison baseline, not validation of the current
parser change.

Mathlib's recorded full-build baseline is parser-safety commit `a6c4545`: all 7,843
sources changed from pristine passed the required module builds, followed by the
8,705-job full build. The later one-space repair in `Mathlib/Tactic/Monotonicity/Attr.lean`
also passed its 68-job module build. The current checkpoint reuses that baseline; it
does not repeat the aggregate release build. Baselines and batch logs are under
`.scratch/external-validation/logs/`.
