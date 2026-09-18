# Version 0.4 plan

Rules describe general syntax ownership. External paths and declaration names
are evidence for tests, never formatter conditions. Missing-rule coverage is
release-blocking only for Lean's standard library and Mathlib.

## Open Issues

No currently reproduced formatting blocker remains from the tight-infix spacing
checkpoint. Fresh complete release validation remains pending below.

Hex is no longer a validation target or release blocker. Its incomplete runs
remain historical measurements, not evidence of a complete pass or a general
solution to concurrent-worker memory pressure.

## Progress

### Release validation

The tight-infix spacing fix passes the focused checkpoint recorded below. Next,
run the complete release gate on the current formatter, including Ephemeris and
Flare alongside GraphQL, quantum, CSLib, and Mathlib.
Hex is excluded. Formatter-only checkpoints do not replace changed-module and
post-format builds. Compare performance with identical inputs, exact imports,
diagnostics, and worker limits.
A formatting or parser change requires a fresh release gate; earlier results do
not validate later changes.

Restart Mathlib formatting from pristine sources. The fix preserves declared
source-tight notation such as `(W'⁄F)`; it intentionally does not remove spaces
from `(W' ⁄ F)` already produced by the previous formatter.

## Deferred Optimization Opportunities

These opportunities remain deferred. They are performance costs, not known
formatting-correctness failures.

### Aggregate worker memory

The last ordinary pinned-Hex run used ten automatic workers and stopped at the
12 GiB safety guard after 547.2s (12.064 GiB), not an observed OOM. The GFq
conformance worker used 7.013 GiB, the GFq benchmark worker 2.437 GiB, and the
remaining processes 2.614 GiB. All 658 comparable completed outputs matched the
preceding run; no source changes or post-format builds were applied.
Log: `.scratch/hex-inspection-normal.log`.

The user accepts up to 9 GiB for the isolated module and the remaining roughly
0.5 GiB formatter overhead. Memory-aware scheduling is deferred, not part of
the replacement checkpoint. Do not silently reduce normal worker counts or
raise the safety guard. Hex measurements below are historical controls only.

### Required prefix elaboration and evaluation cost

```lean
theorem evidence : True := by trivial
attribute [local simp] evidence
```

Standalone attributes, deriving, and unaudited declaration metadata retain
complete-prefix replay. Hex's `HexGF2/Basic.lean` exercises
remaining `ext` and `inline` metadata costs. Audit active implementations before
extending the neutral-effect classifier; attribute spelling alone is insufficient.
Unknown handlers must still observe complete declarations, proofs, and attributes.
Native snapshots require unchanged syntax and positions, so do not share final
state with independent idempotency parses or guess source dependencies.
Explicit parser-neutral contracts can avoid unnecessary replay but cannot bound
arbitrary proof elaboration that a later unaudited observer requires.
Hex's `conformance/HexNumberFieldTower/Conformance.lean` passes formatting and
diagnostics but takes 429s with one worker. A stack sample shows `#guard` expression
evaluation through Lean's IR interpreter during convergence replay, not layout
search. Establish a same-input baseline before calling this a regression; retain
independent parsing and complete state when investigating reuse.

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

### Future design review: accepted-piece reuse

Resolve the reuse contract before adding a render cache. Require equivalent
output, diagnostics, feedback, and traces across placement and suffix changes,
plus improved scaling in the stress controls. Prefix replay remains separately
subject to complete-state equivalence for commands without a neutral contract.

## Validation Standard

### Tight custom infix checkpoint

Parser-derived per-side spacing preserves source adjacency without symbol
exceptions, new line-break APIs, or renderer changes. Operator-owned facts survive
equal-precedence chain flattening; complex descriptors and formatter overrides
retain the previous spacing policy.

- Full local build, unit suite, development lint, fixture regeneration, and
  self-formatting pass. Final dry checks report no drift, preservation failures,
  actionable overflow, fallback, or non-idempotence. Fixtures are unchanged.
- Lean 4.33.1 compatibility passes, including private and exported import tests
  for tight, spaced, asymmetric, mixed-chain, comment, and fallback cases.
- All 42 Mathlib files containing `⁄` at revision `0df444a360eaa60ab8c11dca51a86af692955474`
  pass width-100 formatting diagnostics (including missing rules), compilation,
  and the actual whitespace linter. The old formatter reproduces the Point
  binder warning. Fourteen files differ from the old output: preserved `⁄` and
  local `𝖣` notation, plus resulting line fitting. Three missing dependency
  artifacts were rebuilt in scratch; the existing Mathlib checkout is untouched.
- Ephemeris (28 files, default width 90) and Flare (61 files, width 100) pass
  checkpoint validation with automatic worker counts, no exceptions, and no
  formatting changes. These are formatter-only checks, not new project builds.

The identical-input Mathlib comparison took 81s for both binaries. Ephemeris took
17s and Flare 58s in checkpoint mode; a separate identical-input Flare control
took 73s with the old binary and 45s with the candidate, with identical output.
The historical 32s Flare timing was not reproduced by the old binary either;
these single runs do not establish a speedup. Peak monitored physical footprint
was 4.724 GiB for the Mathlib comparison/build/lint run and 4.589 GiB for the
Ephemeris/Flare checkpoint run.

A warmed local control using the same four profiling inputs and three timed
samples per binary has median format-total 14,392ms before versus 14,303ms after,
with render time 5,717ms versus 5,597ms. These controls show no observed performance
regression; they do not establish release-wide performance.

Logs: `.scratch/infix-local-{initial,final}.log`, `.scratch/infix-self-format.log`,
`.scratch/infix-compatibility.log`, `.scratch/infix-mathlib-validation.log`,
`.scratch/infix-external-checkpoints.log`, `.scratch/infix-flare-comparison.log`,
and `.scratch/infix-profile.log`.
The 42-file Mathlib check does not replace a complete fresh release gate.

### Ephemeris and Flare checkpoint

The allocator and audited print-command changes pass complete validation with
Lake cache, automatic worker counts, and default parser behavior. Ephemeris uses
the default width (90); Flare uses width 100:

- `~/work/formal-software-engineering/chebyshev-ephemeris`, commit
  `643689336add9cf5883012fe1c64fa2cdfd64531`, Lean 4.33.1.
- `~/work/formal-software-engineering/flare-lean`, commit
  `4b13508e1451a26fac7e7c07efa856b444a2ecfc`, Lean 4.33.1.

| Project | Width | Checked files | Format and diagnostics | Initial / changed / final build |
| --- | --- | ---: | ---: | --- |
| Ephemeris | default (90) | 28 | 12s | 68s / unchanged / 2s |
| Flare | 100 | 61 | 32s | 97s / unchanged / 2s |

Both projects pass preservation, actionable overflow, fallback, and independent
idempotency checks with no exceptions or formatting changes. Missing-rule checks
remain disabled for both projects. The fresh default-width Ephemeris run
supersedes its earlier width-100 result.
Flare's `Tests/ProofAudit.lean` was reported and skipped because it has no Lake
module target; all 61 owned sources, including `Lint.lean`, were checked.

The complete default-width Ephemeris run took 178s with 2.982 GiB peak
process-group physical footprint; log: `.scratch/ephemeris-default-checkpoint.log`.
Flare's result is in `.scratch/ephemeris-flare-checkpoint.log`; that earlier
466s combined run includes the superseded Ephemeris width-100 control and peaked
at 4.471 GiB. Memory pressure remained normal. These are new project baselines,
not same-input performance comparisons with Hex or an earlier formatter.
Both original checkouts remain clean.
Checkpoint manifests are recorded under
`.scratch/external-validation/logs/{chebyshev-ephemeris,flare-lean}/`.

```sh
env -u LEANFMT_VALIDATION_LINE_WIDTH scripts/validate-external-projects.sh \
  chebyshev-ephemeris=$HOME/work/formal-software-engineering/chebyshev-ephemeris
LEANFMT_VALIDATION_LINE_WIDTH=100 scripts/validate-external-projects.sh \
  flare-lean=$HOME/work/formal-software-engineering/flare-lean
```

Use `--checkpoint` with these same targets for subsequent lighter checks at the
recorded revisions. Serialize heavy work and monitor compressed-inclusive memory
with the 12 GiB aggregate safety guard; do not silently lower the normal worker
count. Require complete builds again for release.

### Inspection deferral and frontend overhead

With the allocator correction held fixed, audited print deferral formats the
same 51-file Hex proof-probe group in 8.4s / 0.441 GiB, versus 98.2s / 2.722 GiB
before deferral. Preservation, overflow, fallback, and independent idempotency
checks also pass (4.3s / 0.441 GiB with warm imports). Both outputs are
byte-identical to the allocator-only control. These are isolated exact-import
worker controls, not a full automatic-worker checkpoint.
The full local build/test/lint/fixture/self-format/dry-check gate passes in
198.5s / 4.051 GiB, with no fixture changes or diagnostic exceptions. The Lean
4.33.0-rc1 compatible build and smoke suite pass in 58.4s / 2.585 GiB, including
private/exported parser-effect checks and native-library proof replay. Hex's
source checkout remains clean; no whole-project post-format build ran.

Separate serialized controls use unchanged `conformance/HexGFq/CrossCheck.lean`
at Hex `9dcefd01`, Lean 4.33.0-rc1, module-specific native libraries/plugins,
default internal thread settings, and width 100 for formatting. Native compilation
emits `.olean`, `.ilean`, and C artifacts outside the checkout's build outputs.

| Control | Time | Peak process-group footprint |
| --- | --- | --- |
| Normal Lean compilation | 33.3s | 7.220 GiB |
| Lean compilation with full snapshots | 42.7s | 8.001 GiB |
| Formatter parsing/replay only, once | 45.5s | 7.078 GiB |
| Formatter parsing/replay twice, no rendering | 86.7s | 8.046 GiB |
| Ordinary formatting | 85.2s | 8.629 GiB |
| Formatting with exceptions and independent idempotency | 134.5s | 7.846 GiB |

Ordinary formatting therefore has measurable overhead even without validation.
Lean's normal compiler minimizes command snapshots; resumable parser replay
retains more state. Repeated parsing alone reproduces much of the extra cost,
and formatting reparses changed output for preservation and convergence. These
single-run peaks are not additive or necessarily monotonic: the remaining
approximately 0.58 GiB difference between two parses and formatting is not fully
attributed. Do not label it all renderer state or claim diagnostics alone caused
the overhead. Formatting with and without diagnostics produced identical output.
`#guard` remains on the frontend path, so print deferral does not remove this
GFq work. Logs are `.scratch/inspection-memory-*.log` and
`.scratch/inspection-proof-group-{plain,checked}.log`.

### Allocator diagnosis

On the same Hex `HexAddition64.lean` source and Lean 4.33.0-rc1, the version
before authoritative prefix replay (`b6126ab`) used 0.445 GiB / 7.4s, while
`72648eb` used 2.666 GiB / 11.5s. The older parser did not elaborate the pending
proof for `#print axioms`; the import-only control used 0.428 GiB. Restoring that
old parser shortcut would lose complete-prefix semantics and is not the fix.

The newer compatible binary also defined its own mimalloc symbols alongside
`libleanshared`. The link map identified `libleanrt.a(static.c.o)`; allocator
statistics showed separate allocation domains. Waiting for frontend child tasks,
using one internal Lean thread, and aggressive allocator purging did not cure the
growth. None of those experiments is retained in production.

The 51-file exact-import proof-probe group exceeded 8 GiB after 33.3s before the
fix. A shared-only linkage control completed all 51 in 99.5s / 2.721 GiB. The
production correction completed the same group in 98.2s / 2.722 GiB, with
byte-identical output, without changing parser policy. Its normal ten-worker run
completed this group at about 2.6 GiB, then reached a separate GFq concurrency
cutoff. The isolated production control is recorded in
`.scratch/hex-memory-allocator-proof-group.log`.
The full-run log is `.scratch/hex-9dcefd01-shared-allocator-normal.log`; partial
output is `hex/.lake/leanfmt-normal.SRx9Lw/`. All 660 rewritten files are
byte-identical to the archived formatting output. This does not establish a full
formatting, diagnostic, or post-format-build pass.

### Historical Hex evidence

The ordinary-formatting control used formatter `72648eb` on the pinned older
checkout, one invocation over 873 original input copies, width 100, automatic
workers, no diagnostic flags, and no parser integration. It reused the project's
ordered native libraries/plugins and freshly built import artifacts. The guard
stopped it after 197.0s at 12.003 GiB.
The log is `.scratch/hex-9dcefd01-normal-format.log`, and partial output is in
`hex/.lake/leanfmt-normal.sDcyLe/` within the external-validation directory.
This is not a normal-formatting pass, nor a controlled diagnostic-overhead
comparison: the validator also changes batching and enables the audited adapter.

The pinned-revision run used formatter `72648eb`, automatic worker counts, width
100, and the audited LeanBench integration. Its dependency cache restored 8,595
artifacts in 69.6s at a peak process-group footprint of 0.642 GiB. The compatible
formatter built in 29s, the default Hex build passed in 870s, and Lake source
resolution passed in 674s. Of 889 selected files, 873 were Lake-owned; 16 unowned
files were reported and skipped, matching the earlier checkout's scope.

Formatter batches 1-6 passed in 122/113/66/163/128/90s respectively (682s total).
The guard stopped batch 7 at 12.081 GiB after 2,345.1s for the full attempt.
No formatter diagnostic preceded the resource cutoff. All 600 completed outputs
are byte-identical to the archived prior staging, but that earlier run was also
incomplete. There is no whole-project formatting time or post-format build pass.
The full log is `.scratch/hex-9dcefd01-72648eb-full-validation.log`.

The whole-project attempt used formatter `72648eb`, Hex
`237ad74f70ab885fb4c168a64c948f4d16810196`, width 100, one formatter worker,
`LEAN_NUM_THREADS=1`, and a 12 GiB guard. Lake cache supplied all 8,908 requested
dependency artifacts. The run stopped during the initial native build;
it provides no whole-project formatter timing, diagnostic pass, or formatting
regression verdict. The log is `.scratch/hex-72648eb-full-validation.log`.
Old logs and staging were preserved in
`.scratch/hex-before-72648eb-validation.tar.gz`; they do not validate this revision.

Completed controls on the same Hex revision and Lean 4.34.0 remain valid:

| CrossCheck run | Time | Peak process-group footprint |
| --- | --- | --- |
| Native build, dependencies already built | 31.3s | 6.383 GiB |
| Formatter `53a1091`, width 100 and all requested diagnostics | 136.3s | 9.270 GiB |
| Formatter `72648eb`, identical settings | 133.8s | 7.122 GiB |

The formatter outputs are byte-identical and pass preservation, actionable
overflow, fallback, and independent idempotency checks. Lazy defaults reduce the
measured peak by 2.148 GiB (about 23%); wall time is approximately unchanged.
These single-file controls do not include a post-format build or replace the
whole-project gate. Output is in `.scratch/hex434-lazy-default/CrossCheck.lean`,
with the baseline in `.scratch/hex434-runtime-fixed/CrossCheck.lean`.
The imports-only `import HexGFq.Basic` control drops from 6.5s / 2.371 GiB to
3.8s / 0.357 GiB with unchanged exact imports, libraries, plugins, and diagnostics.

### Local and release gates

The allocator correction passes the complete current-toolchain local gate
(211.4s / 4.053 GiB), with no fixture drift or diagnostic exceptions, and the
Lean 4.33.0-rc1 compatibility suite (24.5s / 2.608 GiB). The new symbol check
rejects the previous binary with an embedded `_mi_malloc_small` definition.
Only the new runtime test needed self-formatting.

Five measured samples after a warmup, using the same representative input and
three formatter/test source files, gave median total formatting time
13,904 -> 13,987ms (+0.6%). Rendering alone was 5,232 -> 5,488ms (+4.9%);
parsing was 7,990 -> 7,846ms. Output is byte-identical. The zeroing allocator
entry point has a small measured rendering cost, not a demonstrated total-time
improvement. Logs are `.scratch/allocator-profile-{before,after}.log`.

The native plugin startup fix links `fmt` against `libleanshared` through Lake's
`moreLinkArgs`. The new direct/worker regression reproduces exit 139 without that
setting and passes with it. The lazy-loading change passes the full local gate
without fixture drift (237.3s / 4.049 GiB), and all compatibility suites pass on
Lean 4.30.0, 4.31.0, 4.32.0, and 4.33.1 (serially, 204.5s / 2.722 GiB).
These are local macOS results;
the added macOS CI job and existing Linux CI still need remote execution.

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

Review all generated fixture and self-format changes. Normal validation uses
automatic worker counts. For memory-constrained validation or isolated profiling,
explicitly set `--jobs 1` or `LEANFMT_VALIDATION_FORMATTER_JOBS=1`; this does not
change the default. Serialize heavy runs and monitor compressed-inclusive memory.
Lightweight checkpoints use recorded GraphQL, quantum, CSLib, Ephemeris, and Flare
build baselines plus pristine Mathlib safety regressions. Hex is excluded.
Report scope and omitted builds. Compare performance on identical inputs without
concurrent validation. Enable missing-rule checks for Mathlib only.

Use full validation, not checkpoint mode, for release. Mathlib is pinned to
v4.33.1 commit `0df444a360eaa60ab8c11dca51a86af692955474`; format only
`Mathlib/`, use width 100 and Lake cache. CSLib is pinned to
`98e395a701f2027a413ad24729e1a11a6c772eb4`, Lean v4.33.1, width 100.
The release gate includes clean, changed-module, and complete post-format builds.
Passing does not mean every protected physical line fits width 100.
