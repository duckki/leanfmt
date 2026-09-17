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
| Baseline `53a1091`: width-100 formatting, preservation, overflow, and independent idempotency | 136.3s | 9.270 GiB |
| Production lazy defaults, same checks | 133.8s | 7.122 GiB |

Both runs use the supported shared-runtime link configuration.
Both formatter runs pass every requested diagnostic and produce byte-identical
output, with the proof unchanged. Lazy loading reduces the measured peak by
2.148 GiB (about 23%), retaining exact imports and the direct path's
`leakEnv := false` policy. Memory returns to roughly 0.6-0.8 GiB between spikes
instead of 2.7-2.8 GiB, and system pressure stays normal; the baseline briefly
reached warning. Wall time is approximately unchanged. These are single-run
measurements, not a broad performance benchmark. The previous 6 GiB stops were
resource cutoffs, not completed-run peaks or proof failures.

Earlier command-by-command and isolated-proof controls located the spike in
`N32.packedCert_check`, before the replay-triggering `#guard`. On Hex
`9dcefd01ed70ac4ceb450554516e872b6d707033` / Lean `v4.33.0-rc1`, a separate copy
using `decide +kernel` built in 24.9s / 1.08 GiB and passed checked formatting
in 72.7s / 2.60 GiB. This remains a possible target-project improvement, not a
formatter transformation or a same-revision comparison with the current results.

The completed run covers one file, not all of current Hex or a post-format build.
Production output is under `.scratch/hex434-lazy-default/CrossCheck.lean`, with
the baseline under `.scratch/hex434-runtime-fixed/CrossCheck.lean`;
the Hex checkout remains unchanged. Old validator manifests, staging, and batch
logs belong to the previous revision and cannot resume this checkout's validation.

An imports-only control with `import HexGFq.Basic` drops from 6.5s / 2.371 GiB to
3.8s / 0.357 GiB through the production direct path, with unchanged exact imports,
native libraries, plugins, and checks. The default environment is now memoized on
first use; loader construction, classification, empty batches, and imported-only
runs leave it unloaded. Default-only scripts still receive the full environment.
The complete local gate and compatibility suites pass, including classification,
cache reuse, imported syntax, and real mixed default/exact workers. Worker counts
and process lifetime policy are unchanged.

## Progress

### Required replay memory checkpoint

Lazy default loading has passed the targeted checkpoint. Repeat current Hex's
whole-project validation with fresh manifests, width 100, and one formatter worker,
monitoring compressed-inclusive footprint and system pressure. CrossCheck still
peaks above native compilation (7.122 versus 6.383 GiB); profile remaining retained
state separately from required proof reduction if larger runs expose another
actionable cost. Review and retest `decide +kernel` in Hex only as an explicit
target-project change.
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
