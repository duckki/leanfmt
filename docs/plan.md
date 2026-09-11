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
Bounded frontend recovery now avoids replaying the remaining file and earlier recovered
prefixes. CSLib's `WellFormed.lean` improved from 8,597 to 242 ms of formatter time.
`PhaseSemantics/Basic.lean` remains at 4,545 ms (previously 4,798 ms): ten notation
declarations require successive dependency windows through line 705. Both outputs are
unchanged. The audited Lean 4.33.1 APIs provide no source-dependency replay service. The theorem
header helper is private; `Elab.async` schedules complete proofs rather than avoiding
them. Parser-generating commands can inspect actual theorem bodies, as covered by
`assertParserReplayRetainsTheoremBodyDependencies`. Selective elaboration therefore
needs a separate design, not skipped proofs, ignored errors, or attribute exceptions.

### Repeated diagnostic parsing

```text
formatting -> parsed module -> output text -> diagnostics parse the same text again
```

The driver discards the modules already parsed during convergence. On formatted CSLib
`PhaseSemantics/Basic.lean`, formatting took 4,482 ms; adding preservation and idempotency
checks took 9,165 ms. Identical source and output need just one diagnostic module, but
even that module is currently rebuilt after formatting.

## Progress

### Proposed checkpoint: reuse per-file parse results

Carry original and converged modules into diagnostics within the same file operation.
Keep public text results, fallback behavior, ignore-region whole-file validation, and
the independent idempotency check unchanged. Do not add a global cache or reuse parser
environments between different source texts. Require unchanged formatter output and
fewer parser replays in focused tests and CSLib profiles. This proposal awaits review.

### Later checkpoint: selective dependency design

Review a source-dependency model only if the remaining single-parse cost warrants it.
It must preserve arbitrary command dependencies, declaration bodies, attributes,
namespace and option scopes, and parser error rejection. Lean's reserved-name actions
are not a general missing-source-declaration callback. Do not implement a scheduler or
cross-source cache without approving that design.

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

The dependency audit adds a passing theorem-body dependency regression test. It makes
no production formatter changes beyond the bounded-replay baseline below. The complete
local gate passed, including tests, linter, fixtures, self-formatting, preservation,
width, and idempotency. No new external formatter sweep was run for this test-only
audit. The performance issue remains open pending the next implementation checkpoint.

The bounded-replay follow-up restores let-body metadata parity and limits frontend
recovery to the needed prefix. Tests cover command-local scopes, repeated recovery,
quiet continuation, complete file-map visibility, full-tail parser recovery, terminal
commands, malformed tails, preservation, and idempotency. The complete local gate
passed: build, tests, development linter, self-formatting, preservation, actionable
width, and idempotency, with no fixture drift.

Full GraphQL and quantum validation passed on Lean 4.33.0 and 4.32.0 respectively.
Final formatter/check time was 41 seconds for GraphQL and 15 seconds for quantum. GraphQL's
13 changed files follow existing declaration and proof-layout rules; review found no
new regressions. Quantum's output is unchanged. Both post-format builds passed.

Full width-100 CSLib validation passed all 200 files with an unchanged output baseline
and successful final builds. The two runs took 95 and 85 seconds overall; formatter
checks varied from 56 to 70 seconds.

Mathlib's width-100 checkpoint passed all 8,311 files in 84 batches, with every
formatter diagnostic at zero. Formatter checks took 2,988 seconds; total checkpoint
time was 3,093 seconds. Only `Mathlib/Tactic/Monotonicity/Attr.lean` changed: `( let`
became `(let`, with the multiline string and surrounding layout preserved. The changed
module's 68-job build passed. Independent review found no new formatting issues.
The other 8,310 files are byte-identical to the baseline.

That corpus run preceded the final terminal-command guard. After the guard, the full
local, GraphQL, quantum, and CSLib gates passed again without further formatting
changes. Six Mathlib regression files passed focused preservation, width, missing-rule,
and idempotency checks. The full Mathlib formatter sweep was not repeated after the
guard.

Mathlib's recorded full-build baseline is parser-safety commit `a6c4545`: all 7,843
sources changed from pristine passed the required module builds, followed by the
8,705-job full build. This follow-up reuses that baseline and builds its changed module;
it does not repeat the aggregate release build. The warm, already-formatted checkpoint
timings are not a like-for-like comparison with the earlier full run. Baselines and
batch logs are under `.scratch/external-validation/logs/`.
