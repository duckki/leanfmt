# Version 0.4 plan

Rules describe general syntax ownership. External paths and declaration names
are evidence for tests, never formatter conditions. Missing-rule coverage is
release-blocking only for Lean's standard library and Mathlib.

## Open Issues

### Hex certificate proof memory

```lean
private theorem packedCert_check :
    GF2Poly.checkIrreducibilityCertificate packedModulus packedCert = true := by
  decide
```

Current Hex `237ad74f70ab885fb4c168a64c948f4d16810196`, Lean 4.34.0, retains plain
`decide` in `conformance/HexGFq/CrossCheck.lean:998`. Completed single-worker runs
with a 12 GiB ceiling and critical-pressure/low-disk safeguards show:

| Run | Time | Peak process-group footprint |
| --- | --- | --- |
| Native `lake build +HexGFq.CrossCheck`, dependencies already built | 31.3s | 6.383 GiB |
| Production width-100 formatting, preservation, overflow, and independent idempotency | 136.3s | 9.270 GiB |
| Same checks, scratch control omitting the unused default import | 126.7s | 7.255 GiB |

The production run uses the supported shared-runtime link configuration.
Both formatter runs pass every requested diagnostic and produce byte-identical
output, with the proof unchanged. Omitting only the unused default environment
reduces the measured peak by 2.015 GiB (about 22%). The control retains the direct
path's exact imports and `leakEnv := false` policy. Memory returns to roughly
0.9 GiB between spikes instead of 2.7-2.8 GiB, and system pressure stays normal;
the production run briefly reaches warning, not critical. These are single-run
measurements, not a broad performance benchmark. The previous 6 GiB stops were
resource cutoffs, not completed-run peaks or proof failures.

Earlier command-by-command and isolated-proof controls located the spike in
`N32.packedCert_check`, before the replay-triggering `#guard`. On Hex
`9dcefd01ed70ac4ceb450554516e872b6d707033` / Lean `v4.33.0-rc1`, a separate copy
using `decide +kernel` built in 24.9s / 1.08 GiB and passed checked formatting
in 72.7s / 2.60 GiB. This remains a possible target-project improvement, not a
formatter transformation or a same-revision comparison with the current results.

The completed run covers one file, not all of current Hex or a post-format build.
Production output is under `.scratch/hex434-runtime-fixed/CrossCheck.lean`, with
the matching control under `.scratch/hex434-no-default/CrossCheck.lean`;
the Hex checkout remains unchanged. Old validator manifests, staging, and batch
logs belong to the previous revision and cannot resume this checkout's validation.

An imports-only control with `import HexGFq.Basic` takes 6.5s / 2.371 GiB through
the production direct path, versus 3.1s / 0.357 GiB when a scratch launcher omits
only the unused default `Lean` import. Both use the same exact import policy,
native libraries, plugins, and checks. The direct path currently constructs both
environments eagerly; exact workers already omit the default environment. The
control is not a production memory fix: make the default environment lazy and
memoized per loader, preserving exact-header selection and the existing worker
lifetime policy. Do not substitute an empty environment for default-only scripts.

## Progress

### Required replay memory checkpoint

Lean 4.34.0 is installed, and the formatter's build, unit tests, linter, fixture,
preservation, overflow, and idempotency checks pass without fixture changes.
The 4.33.1 compatibility smoke also passes with its import-heavy groups isolated
in sequential processes (2.41 GiB peak; the combined runner exceeded 6 GiB).
Current CrossCheck passes checked formatting with the supported executable, but
the eager default import adds approximately 2 GiB in the controlled comparison.
Implement lazy default-environment loading first, with tests for unused defaults,
default-only scripts, exact imports, and mixed workers. Repeat the local gate and
the same CrossCheck comparison; require unchanged output and diagnostics. The
control still peaks above native compilation (7.255 versus 6.383 GiB), so continue
profiling remaining retained state separately from required proof reduction. Review
and retest `decide +kernel` in Hex only as an explicit target-project change.
Do not rewrite proofs during parsing, disable info trees, or add a blanket `#guard`
exemption: unknown handlers must still observe
complete preceding declarations and proofs. Keep independent idempotency parsing.
The full Hex checkpoint remains incomplete until its selected source revision
passes the complete gate with the supported executable and agreed memory bound.

### Release validation

Run the complete release gate after review of the parser-classification change.
Formatter-only Hex checks do not replace changed-module and post-format builds.
Use `LEANFMT_VALIDATION_PARSER_INTEGRATION=lean-bench` only for the audited
dependency version. Current Hex pins LeanBench
`8a37daf1074c3bdbd0da479b55538bad4a0022db`, which has not been audited; leave
the adapter disabled unless its implementations and fingerprints are reviewed.
The adapter is explicit and is not enabled by default.
Retain `HexGF2/Clmul.lean` as an isolated performance control and compare with
identical inputs, exact imports, diagnostics, and worker limits. The old 469s
full-project timing covered a different file set and is not a comparable baseline.
A formatting or parser change requires a fresh release gate; earlier results do
not validate later changes.

## Deferred Optimization Opportunities

These opportunities remain deferred. They are performance costs, not known
formatting-correctness failures.

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

The native plugin startup fix links `fmt` against `libleanshared` through Lake's
`moreLinkArgs`. The new direct/worker regression reproduces exit 139 without that
setting and passes with it. The full local gate passes without fixture drift
(220.3s / 4.055 GiB), and all compatibility suites pass on Lean 4.30.0, 4.31.0,
4.32.0, and 4.33.1 (serially, 179.6s / 2.407 GiB). These are local macOS results;
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
Lightweight checkpoints use recorded GraphQL, quantum, and CSLib build baselines
plus pristine Mathlib safety regressions.
Report scope and omitted builds. Compare performance on identical inputs without
concurrent validation. Enable missing-rule checks for Mathlib only.

Use full validation, not checkpoint mode, for release. Mathlib is pinned to
v4.33.1 commit `0df444a360eaa60ab8c11dca51a86af692955474`; format only
`Mathlib/`, use width 100 and Lake cache. CSLib is pinned to
`98e395a701f2027a413ad24729e1a11a6c772eb4`, Lean v4.33.1, width 100.
The release gate includes clean, changed-module, and complete post-format builds.
Passing does not mean every protected physical line fits width 100.
