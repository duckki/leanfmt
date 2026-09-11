# Version 0.4 plan

Rules must describe general syntax ownership. External paths and declaration
names are evidence for tests, never formatter conditions. Missing-rule coverage
is release-blocking only for Lean's standard library and Mathlib.

## Open Issues

### Interleaved parser dependencies

```lean
def orthogonal := ...
@[inherit_doc] scoped postfix:max "⫠" => orthogonal
```

Quiet parsing skips ordinary definitions; later syntax declarations can need them.
Bounded frontend recovery preserves these dependencies, but CSLib's
`PhaseSemantics/Basic.lean` still takes about 4.5 seconds for one parse: ten notation
declarations require successive dependency windows through line 705. Lean 4.33.1 has
no audited source-dependency replay API. Parser-generating commands can inspect actual
theorem bodies, as covered by `assertParserReplayRetainsTheoremBodyDependencies`.
Selective elaboration needs a separate design, not skipped proofs, ignored errors,
or attribute exceptions. This is a performance issue, not a known formatting failure.

## Progress

### Next checkpoint: dependency design decision

Review a source-dependency model only if the remaining single-parse cost warrants it.
It must preserve arbitrary command dependencies, declaration bodies, attributes,
namespace and option scopes, and parser error rejection. Lean's reserved-name actions
are not a general missing-source-declaration callback. Do not implement a scheduler or
cross-source cache without approving that design.

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

The per-file module checkpoint is based on `5cb7b6c`. Diagnostics consume original and
converged modules from one file operation, without a cross-source cache. Public text
results, fallback behavior, ignored-region whole-file validation, and independent
idempotency are unchanged. Inherited overflow is filtered before structural analysis,
using the existing exemption without bypassing code preservation.

Build, tests, development linter, fixtures, self-formatting, preservation, actionable
width, and idempotency passed. Replay-count tests cover unchanged, changed, normalized,
and ignored-region inputs; diagnostic tests cover inherited and newly introduced overflow.
Fixture output is unchanged; self-formatting changed only the new implementation and
test code. Because Apple's command-line tools became unavailable, the commands behind
`make check` were run directly with the bundled Git and Lean toolchain.

An initial matched profile of formatted CSLib `PhaseSemantics/Basic.lean` reduced
formatting plus diagnostic time from 8,715 to 4,526 ms, with identical output. The
single-parse dependency replay cost remains; this improvement removes duplicate work.

An alternating before/after comparison over GraphQL's 280 files on Lean 4.33.0 took
30.65-38.88 seconds before and 18.68-19.04 seconds after. Aggregate CPU user time fell
from about 162.5 to 95.9 seconds. The large proof-file diagnostic slowdown found during
development was eliminated by applying the existing inherited-overflow exemption first.

Full GraphQL (280 files), quantum (20 Lake-owned files; one unowned source skipped),
and width-100 CSLib (200 files) passed with successful post-format builds and
byte-identical output. Final batched formatter checks took 37, 52, and 69 seconds
respectively; the quantum timing overlapped local checks, and its isolated checkpoint
repeat took 19 seconds. CSLib's full validation took 82 seconds.

The width-100 Mathlib checkpoint passed all 8,311 files in 84 batches, with every
enabled diagnostic at zero and no changed sources. Formatter checks took 2,667 seconds;
total checkpoint time was 2,781 seconds, compared with 2,988 and 3,093 seconds in the
previous warm checkpoint. Two reviewers confirmed zero output changes through staged
comparisons and complete pre/post snapshots, with a fresh checkout diff matching the
snapshots. All 8,311 outputs are byte-identical to the pre-checkpoint baseline.

Mathlib's recorded full-build baseline is parser-safety commit `a6c4545`: all 7,843
sources changed from pristine passed the required module builds, followed by the
8,705-job full build. The later one-space repair in `Mathlib/Tactic/Monotonicity/Attr.lean`
also passed its 68-job module build. The current checkpoint reuses that baseline; it
does not repeat the aggregate release build. Baselines and batch logs are under
`.scratch/external-validation/logs/`.
