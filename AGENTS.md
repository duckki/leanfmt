# leanfmt repository guide

This file is the repository-local operational memory for agents working on
leanfmt. Run commands from the repository root. The detailed documentation
linked below remains the source of truth when this summary and the code diverge.

## Repository layout

- `LeanFmt.lean` is the public library entry point.
- `LeanFmt/SyntaxTree.lean` parses Lean source into the lossless tree and performs
  syntax regrouping.
- `LeanFmt/Formatter.lean` exposes the formatting API and drives convergence.
- `LeanFmt/Formatter/SpaceRules.lean` owns horizontal token spacing.
- `LeanFmt/Formatter/LayoutTree.lean` prepares the rendering view from source-boundary
  facts while leaving the lossless syntax tree unchanged. Keep comment-dependent
  chain joining here, not in syntax regrouping or line-break rules.
- `LeanFmt/Formatter/LineBreakRules.lean` owns syntax-specific break rules and
  the complete rule dispatch table.
- `LeanFmt/Formatter/OriginalTree.lean` classifies protected source-layout islands
  and plans their indentation-preserving source emission.
- `LeanFmt/Formatter/Renderer.lean` owns layout state, fit checks, indentation,
  and text emission. Keep syntax-specific decisions out of the renderer.
- `LeanFmt/Formatter/Diagnostics.lean` checks code preservation, actionable line
  overflow, and missing rules; `Trace.lean` supports renderer debugging.
- `LeanFmt/Cli.lean` implements the public `fmt` executable.
- `LeanFmt/LeanEnvironment.lean` is the narrow adapter to Lean's exact
  header/import-environment APIs; worker batching and caches stay in
  `LeanFmt/Driver/`. Keep direct and incrementally reused import paths equivalent;
  the direct path is the compatibility fallback for Lean upgrades.
- `LeanFmt/Tests/Suite.lean` contains the unit-style suites executed through
  `#eval`; `LeanFmt/Tests/Cli.lean` implements the fixture/test CLI and
  `LeanFmt/Tests/Main.lean` is its executable entry point.
- `Tests/Fixtures/<category>/*.leanfmt` contain input above the separator and
  generated expected output below it. Do not hand-edit the generated half.
- `scripts/validate-external-projects.sh` validates the formatter against fresh
  clones of external Lean projects.
- `tools/linter/` is a separate development-only Lake package that pins
  Batteries and runs environment linters without adding Batteries to leanfmt's
  released dependency graph.
- `lakefile.toml`, `lake-manifest.json`, and `lean-toolchain` define the released
  package, executables, and canonical Lean version. The root package depends
  only on Lean. `.lake/` is generated.
- `.scratch/external-validation/` contains disposable external-validation clones
  and must remain untracked.

## Documentation layout

- `README.md` is the user-facing overview, installation/usage guide, project
  status, and external-validation entry point.
- `docs/design.md` is the normative formatting style and examples.
- `docs/architecture.md` documents pipeline boundaries, invariants, tree shape,
  rules, renderer behavior, and diagnostics.
- `docs/development.md` is the contributor guide for building, tests, fixtures,
  tracing, profiling, and adding rules.

Update the relevant document when a change alters user-visible formatting,
module responsibilities, diagnostics, CLI behavior, or validation commands.

## Required branch and PR validation

Every branch or PR should pass this review gate. Run focused checks while
developing, then run the complete sequence before requesting review.

1. Build, run the unit-style suite, and run the development linter:

   ```sh
   lake build
   lake test
   make lint
   ```

2. Regenerate every fixture after an intentional formatter change:

   ```sh
   lake exe fmt-test --update-fixture Tests/Fixtures/*/*.leanfmt
   ```

   Review `git diff -- Tests/Fixtures` immediately. Confirm each generated
   output change is intended, structure-preserving, and represented by focused
   coverage. Never accept fixture churn merely because it was generated.

3. Self-format all formatter and test sources while running the exception and
   idempotency checks:

   ```sh
   lake exe fmt --check-exception --check-idempotent \
     -r LeanFmt
   ```

   This invocation writes formatting changes only for files without exceptions.
   `--check-exception` checks non-whitespace code preservation and actionable line
   overflow; `--check-idempotent` performs a second formatting pass. Review
   `git diff -- LeanFmt` after it runs, including
   mechanically generated changes.

4. If fixture or self-formatting output changed Lean sources, rerun `lake build`
   and `lake test`. Then run the final dry checks:

   ```sh
   lake exe fmt-test --update-fixture --check Tests/Fixtures/*/*.leanfmt
   lake exe fmt --check --check-exception --check-idempotent \
     -r LeanFmt
   git diff --check
   ```

   With diagnostic options present, `--check` is a dry-run switch: files that
   merely need formatting are reported, while diagnostic exceptions determine
   failure. The final run should report neither formatting drift nor exceptions.

Summarize the build, test, fixture, preservation, overflow, and idempotency results
for review. Do not commit generated or handwritten changes
until the reviewer explicitly asks for a commit.

Serialize heavy validation, baseline/candidate profiling, and test-suite runs.
On memory-constrained machines, start import-heavy formatting with `--jobs 1`
(or `LEANFMT_VALIDATION_FORMATTER_JOBS=1` in the validator), including temporary
input copies. This still isolates every exact import group in a fresh worker.
`lake test` runs groups in sequential subprocesses; keep that lifetime boundary.
On macOS, monitor physical footprint including compressed memory, not RSS alone.

## Commit messages

Use a single-line summary, followed by a blank line and a few bullet points.
Describe only what changed. Omit motivation, rationale, and validation results;
report validation separately in the review summary.

## External release validation

Run the complete external release gate with:

```sh
scripts/validate-release-projects.sh
```

The release gate uses four fresh shallow checkouts. Mathlib and CSLib use their
upstream tags for this repository's `lean-toolchain`, and their toolchain files
must match it. Flare and GraphQL use GitHub's `main` branches with their own
toolchains. Use width 100 for Mathlib, CSLib, and Flare and the default width for
GraphQL. Mathlib formats only `Mathlib/`. Use automatic formatter worker counts
unless the run requires an explicit memory limit.

For iteration, use `scripts/validate-external-projects.sh` with explicit
`GIT_REPO` or `NAME=GIT_REPO` arguments. It accepts local paths and remote URLs.
Use `--files FILE_SELECTOR` or append `::FILE_SELECTOR` to select a subset.
A directory selector includes every tracked `.lean` file under it:

```sh
LEANFMT_VALIDATION_LINE_WIDTH=100 scripts/validate-external-projects.sh \
  --toolchain-tag --files Mathlib/Combinatorics \
  mathlib=https://github.com/leanprover-community/mathlib4.git
```

For each project the script builds leanfmt, creates a fresh clone under
`.scratch/external-validation/`, optionally downloads the project's Lake cache,
and runs one complete build before formatting. It resolves selected sources through
Lake, builds non-default module targets, reports and skips sources without Lake module
ownership, and formats staged copies with `--check-exception --check-idempotent`
under the target project's `lake env`. The project named `mathlib` additionally uses
`--check-missing-rules`; other projects may contain unsupported custom syntax. The
project-wide set of native libraries and
parser plugins declared by Lake setup files is loaded in Lake's required order.
After every requested formatter batch succeeds, the validator applies the staged output, builds changed
modules, and runs one complete project build. A formatter failure leaves project
sources untouched and stops validation without running that build. It times every
phase and returns failure when any required phase fails. A missing build-cache
executable is only an optional-phase skip. Pass `--skip-final-build` during
formatter-only iteration to apply successful output without the changed-module and
complete builds while retaining the initial clean build. To resume an existing
scratch clone and staging tree after a successful batch, combine `--start-batch N`,
`--reuse-clone`, and `--skip-initial-build`; the validator then continues from batch
`N` without recloning or repeating the completed pre-format build.

For routine large-project checkpoints, pass `--checkpoint`. A successful complete
validation records a baseline bound to the clone revision, Lean toolchain, selector,
and selected sources. Checkpoint mode reuses that clone plus the recorded Lake
ownership and runtime manifests, runs all formatter exception and idempotency checks,
and applies output for review without running target-project builds. It refuses a
missing or stale baseline. Use complete validation, not checkpoint mode, for the
release gate.
Validation batches run serially, while formatter workers within one invocation run
concurrently up to the formatter's worker-job limit. Imported files are grouped by
exact environment, and each group runs in one short-lived worker.
Per-batch output and the last batch state are persisted under
`.scratch/external-validation/logs/PROJECT/`.

Review external changes and diagnostics in the scratch clone. Treat code changes,
non-idempotence, actionable overflow, and either build failure as formatter issues
to investigate. Treat missing rules as required failures only for Mathlib. Convert
each issue into a focused internal test
or fixture and a formatter fix; do not make the scratch clone the source of the
fix. Rerun the affected project until clean, then run the complete release gate.
