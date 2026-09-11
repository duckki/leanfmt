# Version 0.4 plan

Rules must describe general syntax ownership. External paths and declaration
names are evidence for tests, never formatter conditions. Missing-rule coverage
is release-blocking only for Lean's standard library and Mathlib.

## Open Issues

### Parser replay cost

```lean
def orthogonal := ...
@[inherit_doc] scoped postfix:max "⫠" => orthogonal
```

Quiet parsing skips ordinary definitions. A later syntax declaration can then fail
to elaborate and require a full frontend retry. Keep that safety fallback: ignoring
replay errors can silently reinterpret compound keywords as infix expressions.
Two already-formatted CSLib samples rose from 82/395 ms to 17,178/9,118 ms of formatter
time; an independent repeat measured 116/663 ms versus 9,249/4,698 ms. Output is unchanged.
Mathlib batch 15 passed in 403 seconds, with `AlgebraicGeometry/Modules/Tilde.lean`
as its long-running worker; the full frontend makes formatting sensitive to proof cost.
Skipping temporary `open ... in` wrappers alone does not recover those timings because
later standalone `open` and notation commands also depend on skipped declarations.
Investigate dependency handling separately, without teaching layout rules about it.

### Frontend parser-metadata parity

```lean
    ( let descr := "description"
      let mono := `mono
      registerLabelAttr mono descr mono)
```

Full-frontend recovery drops let-body parser facts. The conservative missing-fact
default can round an attached `let` to the next indentation level, inserting a space
after `(` in `Mathlib/Tactic/Monotonicity/Attr.lean`. Restore facts using each command's
pre-command parser context, not the final environment. Keep the existing alignment
rules and test quiet/recovery parity, string preservation, and idempotency.

## Progress

### Next checkpoint: parser metadata and replay efficiency

Restore let-body metadata parity between quiet parsing and frontend recovery. Then
reduce full-frontend retries for local declaration dependencies without accepting
partially registered grammar or recovered parser errors. Establish a narrow parser-state
design first; preserve the CSLib output baseline and remeasure the two slow samples.

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

The parser-safety checkpoint passed the complete local gate with no fixture drift:
build, tests, development linter, self-formatting, preservation, actionable width,
and idempotency. Parser recovery errors are rejected; unrelated elaboration errors
remain tolerated. Local grammar producers and ignored-region chunks have focused
safety coverage, and grouped equation declarations share existing declaration rules.

Full width-100 CSLib validation passed all 200 files and both post-format builds.
Its output is byte-identical to the preceding formatted checkpoint. Formatter/check
batches took 60 and 77 seconds; changed-module and final builds took 70 and 11 seconds.

Full width-100 Mathlib validation passed all 8,311 files in 84 batches, with every
formatter diagnostic at zero. All 7,843 changed sources passed the required module
builds, followed by the 8,705-job full build. Formatting/checks took 6,939 seconds,
changed-module builds 3,220 seconds, and the final build 45 seconds. The complete
CSLib/Mathlib run took 10,794 seconds. Both checkpoint baselines are recorded under
`.scratch/external-validation/logs/`.

Mathlib differs from the preceding formatted output in 64 files: compound-token
repairs, equation-declaration ownership corrections, and the one extra space tracked
above. Two independent reviewers covered all 81 incremental hunks with no additional
findings. Build style warnings remain; reviewed warning lines are unchanged from the
preceding output, and the formatter reported no actionable overflow.
