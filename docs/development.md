# leanfmt development

This document is for contributors working on leanfmt itself. For formatting style and
examples, see [design.md](design.md). For the implementation model, see
[architecture.md](architecture.md).

## Prerequisites

leanfmt is a Lake package. Use the repository's pinned toolchain:

```sh
cat lean-toolchain
```

The normal commands assume you are in the `leanfmt` repository root.

The root package records our current development toolchain. CI also builds and
tests the same source with supported previous minor versions. Keep compatibility
changes on the main branch rather than maintaining a branch per Lean version.

## Build

Build the library and default executable:

```sh
lake build
```

Build only the formatter library:

```sh
lake build LeanFmt
```

Build the public executable:

```sh
lake build fmt
```

The executable is written to:

```sh
.lake/build/bin/fmt
```

## Run the formatter

Format files in place:

```sh
lake exe fmt path/to/File.lean
```

Check without writing:

```sh
lake exe fmt --check path/to/File.lean
```

Format or check a directory:

```sh
lake exe fmt Some/Directory
lake exe fmt --check --recursive Some/Directory
lake exe fmt --line-width 100 --check --recursive Some/Directory
```

`--recursive` or `-r` makes directory arguments include nested `.lean` files.
Hidden entries discovered during directory traversal are skipped unless
`--include-hidden` is passed; an explicitly supplied hidden path is still processed.
`--line-width N` overrides the default 90-character formatter line limit.

## Validation checks

The repository uses the same Lake entry points adopted by mathlib and CSLib:

```sh
lake build --wfail
lake test --wfail
make lint
```

`--wfail` promotes Lean warnings to errors. `make lint` runs Batteries'
environment linter from the separate `tools/linter` Lake package. Batteries is
therefore available to contributors without becoming a dependency of the
released formatter. The complete local review gate is `make check`; run `make
shellcheck` when changing shell scripts. CI runs these checks for every pull
request.

The development linter runs the enabled Batteries environment linters except
`docBlame`. leanfmt exposes a small public formatter API, but most declarations
are internal implementation details for syntax analysis, layout, diagnostics,
and the CLI. Other linter findings fail the gate and should be fixed rather than
added to a baseline.

## Lean-version compatibility

leanfmt supports one source and release line across our current toolchain and
supported previous minor versions. The current-toolchain CI job runs the complete
maintenance gate. It runs each core test group in a fresh `testSuite` process so
the runner releases that group's memory before starting the next one; CI logs
name each group as it starts and passes. Compatibility jobs select each previous
minor version in a disposable checkout, build the released library and
executable, then run the isolated `compatibilityTest` smoke executable. The
compatibility smoke module does not import the comprehensive current-toolchain
test suite, so growth in that suite cannot increase the elaboration cost of
compatibility testing.
The smoke suite checks parsing, formatting, preservation, idempotency, CLI
parsing, exact environment loading, and executable configuration without
asserting parser-version-specific layouts. Linting, fixtures, comprehensive
formatting rules, self-formatting, formatter diagnostics, and idempotency checks
run once with our current toolchain.

When adding or updating leanfmt in a project on an older supported Lean version,
preserve the project's toolchain during dependency resolution:

```sh
lake update --keep-toolchain
```

A normal `lake update` considers direct dependencies' `lean-toolchain` files and
may update the root project to leanfmt's current version. With
`--keep-toolchain`, Lake retains the downstream version and compiles leanfmt with
it. This is required for reliable loading of the project's compiled parser
extensions and imported environment.

An executable built by one Lean minor version cannot load another minor
version's `.olean` files. To validate an older project without adding leanfmt as
a dependency, build the current leanfmt source in a disposable checkout using
the target toolchain, then run that executable from the target project's
`lake env`:

```sh
target_lean_version=vX.Y.Z
compat=/tmp/leanfmt-$target_lean_version
mkdir -p "$compat"
git archive HEAD | tar -x -C "$compat"
printf 'leanprover/lean4:%s\n' "$target_lean_version" > "$compat/lean-toolchain"
(cd "$compat" && lake build fmt)
(cd /path/to/target && lake env "$compat/.lake/build/bin/fmt" \
  --check-exception --check-idempotent path/to/File.lean)
```

The target's `lake env` supplies its import paths and parser extensions, while
the disposable build supplies a binary with the matching Lean ABI. Do not
rebuild the main leanfmt checkout's `.lake` directory under the older toolchain;
that would replace its current-toolchain artifacts. The external validator
automates this workflow. It keeps one compatible build directory per target
toolchain under its scratch directory, refreshes that directory from the current
tracked and untracked formatter source, preserves its `.lake` build artifacts,
and lets Lake rebuild only changed modules.

Add a maintenance branch for an older Lean version only if its implementation
must diverge from `main`. Ordinary compatibility fixes belong on `main` and must
continue to pass the full toolchain matrix.

These options are intended for formatter development, not everyday user formatting:

```sh
lake exe fmt --check-exception path/to/File.lean
lake exe fmt --check-missing-rules Mathlib/path/to/File.lean
lake exe fmt --check-idempotent path/to/File.lean
lake exe fmt --check --check-exception --check-idempotent --recursive Some/Directory
```

`--check-exception` runs the formatter's safety diagnostics:

- compare the code-token sequence before and after formatting while preserving
  comment contents and requiring the parsed syntax signature to remain unchanged.
  The signature erases source positions and canonicalizes parser-packed `doIf`
  continuations outside quotations; other statement ownership stays exact (see
  [preservation](architecture.md#preservation-check-limitation-layout-sensitive-elaboration));
- report actionable formatted lines that still exceed the configured width.

`--check-missing-rules` separately reports syntax nodes that have no registered
line-break rule, together with the parser-layout metadata source used by generic
regrouping. External validation enables it only for the project named `mathlib`;
other downstream projects may rely on custom syntax that is not first-class support.

Overflow inside comments is ignored. A line is also exempt when every column beyond the
configured width belongs to one indivisible syntax unit, since the renderer has no legal
place to break that suffix. These units include single tokens, interpolated strings, and
atomic syntax elements followed immediately by tokens in the diagnostic's excluded
line-ender set. The set contains closing delimiters and punctuation such as commas and
semicolons that may finish a formatted line.

The wider diagnostic set is designed to accept additional formatter-development
checks later. Any reported exception makes the command fail. Without `--check`, the
formatter still writes an available checked candidate so a subsequent build can validate
that exact output. A format fallback has no candidate and keeps the source unchanged.
The formatter also processes the remaining files, then prints counts for every exception
kind at the end.

`--check-idempotent` remains separate because changed output requires another complete
formatting pass. Output that already equals its source is a fixed point and does not need
to be recomputed. Non-idempotence is a hard exception and is included in the final
exception counts.

When `--check` is combined with any diagnostic option, it becomes a dry-run switch:
files are not rewritten, but merely needing formatting does not make the command fail.
The command succeeds when there are no diagnostic exceptions. Without a diagnostic
option, `--check` retains its ordinary behavior and fails when a file needs formatting.

### Missing-rule exceptions

Missing rules are reported with their source location and original tree slice:

```text
missing rule: path/to/File.lean:line: Lean.Parser.Some.kind
Lean formatter: registered formatter
<original source slice>
```

A listed node is not automatically formatted incorrectly. It means the generic default
rule is being used. Add an explicit rule when the syntax has layout requirements that the
generic rule cannot know, such as projection tightness or mandatory command boundaries.
The `Lean formatter` line classifies the kind as `registered formatter`, `parser
description`, or `no formatter metadata`. The final exception summary counts all three
groups separately. Parser descriptions may already contribute conservative application,
precedence, or body-ownership facts. The classification does not delegate rendering to
Lean's pretty printer or make a missing leanfmt rule pass.

For release review, unresolved missing rules are blockers only in Lean's standard
library and Mathlib, which are first-class syntax-support targets. In other external
repositories, record missing-rule diagnostics as syntax inventory, but do not treat
them as failures unless review also finds a concrete preservation, layout,
convergence, overflow, or post-format build problem.

### Registered formatter ruleset audit

`tools/rule-audit` is a separate development-only Lake package. It symbolically inspects
registered Lean formatters, requires repeated candidates for a normalized syntax shape,
and compares direct child boundaries with leanfmt's current regrouped rules. Build it
without adding the audit to the released executable graph:

```sh
cd tools/rule-audit
lake build
```

Run the executable under the target project's `lake env` when project syntax is needed.
The tool prints a Markdown report and never changes source files. Registered output is
an audit oracle, not a style specification; review every difference against
`docs/design.md` and focused formatter tests. The current Core, Std, and Mathlib review
is summarized in `docs/ruleset-audit.md`.

## Tests

Run the unit-style test suite:

```sh
lake test
```

To build the test library directly without executing the suite:

```sh
lake build LeanFmt.Tests
```

`LeanFmt.Tests.Suite` is the test library root. `LeanFmt.Tests.Run` is the
`testSuite` executable used by `lake test`. It runs groups sequentially in fresh
subprocesses, so imported regions cannot accumulate across the whole suite.
Editor language-server checks only elaborate the test library, without running
side-effectful tests. Each group loads only its required environments. Tests share
one lazily loaded `ProjectSyntax` environment within their process; import-loader
checks keep their independent imports and run in separate subgroups.

Select a group with `lake exe testSuite basic-formatting` or
`lake exe testSuite cli-architecture`. Selecting a parent also runs all its
subgroups; an exact subgroup such as `cli-architecture/rootless-workers` runs
alone. Unknown selections fail before any group starts, and a failing group
stops the suite. The internal `--run-group NAME` dispatch runs exactly one group
in the child process, without recursively spawning more test runners.

`LeanFmt.Tests.LayoutArchitecture` contains stable contract tests for source-boundary
classification, resolved layout plans, original-island policies, and source/output
rebasing. Prefer adding intermediate tests there when changing component boundaries;
keep final formatted-text and parser-preservation coverage in the broad suite and
fixtures.

`LeanFmt.Tests.DocumentedExamples` keeps canonical examples in `docs/design.md`
synchronized with the formatter. Put `<!-- leanfmt-test -->` immediately before a
standalone Lean fence whose contents represent formatted output. The test formats each
marked fence, rejects formatter fallback, and requires the result to equal the documented
source. Update its expected example count whenever intentionally adding or removing a
marked example; the count prevents an accidentally removed marker from silently dropping
coverage. Do not mark deliberately unformatted input, partial syntax, or examples that
require a syntax environment other than the suite's default Lean environment.

Run fixture checks without rewriting fixture files:

```sh
lake exe fmt-test --update-fixture --check Tests/Fixtures/*/*.leanfmt
```

Update fixture expected output after an intentional formatting change:

```sh
lake exe fmt-test --update-fixture Tests/Fixtures/*/*.leanfmt
```

The `Makefile` wraps the common maintenance commands:

```sh
make test
make lint
make check
```

`make check` is the normal pre-review gate. It builds and tests with warnings as
errors, runs lints, checks fixtures and formatter invariants, and checks the diff
for whitespace errors.

## Fixture format

Formatter fixtures are `.leanfmt` files with two halves separated by:

```text
-----------------------------------------------------------------------------------------
-- leanfmt: expected output below (DO NOT EDIT)
-----------------------------------------------------------------------------------------
```

The first half is the input source. The second half is expected formatter output.

When adding a rule, prefer a focused fixture that shows the smallest useful example and a
unit-style test when the behavior is easier to assert directly in Lean.

## Renderer tracing

Renderer trace output is available through the test executable when updating fixtures:

```sh
lake exe fmt-test --update-fixture --trace-renderer Tests/Fixtures/04-expressions/let-expression.leanfmt
```

The trace interleaves formatted output lines with segment entries. Each entry includes:

- segment path,
- child range,
- node kind,
- selected rule name,
- current column and indentation,
- segment indentation,
- pending indentation,
- `tailIndentation`.

Use traces to answer questions like "which rule introduced this break?" or "what base
indentation did this child receive?" Keep renderer fixes state-based; avoid adding token
or node-kind special cases in renderer code.

Use `Formatter.LayoutTree.prepare` when inspecting the child indexes of a
renderer trace: the lossless syntax tree retains continuations that the rendering
view can flatten. Source-boundary decisions belong in layout preparation, not in
syntax regrouping or line-break rules. `assertConditionalChainCommentOwnership`
in the control-flow suite checks this ownership, token order, exact layout,
elaboration, preservation, and idempotency. Coverage includes ordinary, dependent,
pattern, and mixed chains at widths 60 and 100; comment boundaries and comments
inside conditions; attached proofs; parentheses; nested `do`; and joined/broken
tails. Existing conditional and suffix tests remain enabled.

## Profiling

The test executable can print formatter phase timings. Add `--check` when
profiling a source file so the command does not rewrite it:

```sh
lake exe fmt-test --profile --check path/to/File.lean
```

Profile output includes normalize, parse, syntax-tree construction, render, and total
format time.

For integrated driver and diagnostic timings, run the formatter under the target
project's Lake environment with identical source, toolchain, and flags:

```sh
lake env /path/to/leanfmt/.lake/build/bin/fmt --profile --check \
  --check-exception --check-idempotent --line-width 100 path/to/File.lean
```

Diagnostics reuse the original and converged modules from that file operation;
idempotency still starts a fresh formatting operation when the source changed.
`assertDiagnosticChecksReusePerFileModules` checks replay counts with an isolated
`run_cmd` counter rather than a wall-clock threshold.

Compile both comparison executables with the target project's Lean version. Enter the
formatter copy before running Lake: `lake -d` selects a package directory but does not
change the toolchain Elan selected when launching Lake. Use alternating before/after
samples without concurrent builds or validation, and retain both wall and CPU timings.

Parser-state changes also need an independent semantic check. The
`assertParserCommandsObserveCompletePrefix` tests compare syntax with Lean's complete
frontend; `assertFrontendElaborates` waits for all elaboration snapshots and checks both
original and formatted input. Preservation and idempotency alone can agree on the same
incomplete environment. Extending the quiet path requires auditing the actual command
and macro implementations, including replacements, attributes, and scoped wrappers.
The info-state observer case also checks syntax registered by a command that reads
the native info-tree collection flag; treating that flag as invisible bookkeeping
would change subsequent parsing.
`assertMutualParserReplayIsDeferred` checks that eligible declaration blocks remain
unelaborated until an observer needs them, then verifies actual theorem bodies and
complete-frontend syntax parity. The custom-handler tests keep block, member, and
scope overrides on the authoritative replay path. These state assertions test the
optimization independently of machine-dependent timing thresholds.
`assertOptionScopeDoesNotReplayDeclarations` checks immediate option and recursion-limit
updates without declaration replay, later observer state, and scope-exit parity with
the frontend. Overridden option handlers and scoped wrappers retain replay coverage.
`assertReviewedHeaderAndContinuationOwnership` covers empty assignment headers,
absent `finally` continuations before a suffix, and quantified `suffices` continuations,
with preservation and idempotency checks.

The repository also includes a stable local workload that covers regrouping,
original-layout emission, layout search, and convergence. Record a baseline before an
optimization and compare the new implementation on the same machine:

```sh
scripts/profile-baseline.sh --record /tmp/leanfmt-before.profile
scripts/profile-baseline.sh --compare /tmp/leanfmt-before.profile
```

The script runs one warmup followed by five timed samples and compares median phase
timings. It allows a 25 percent increase with a 10ms absolute floor by default; the
sample count and tolerances can be changed through the environment variables shown by
`scripts/profile-baseline.sh --help`. Do not compare baseline files across machines.

For larger runs, redirect ordinary formatter output and time the command externally:

```sh
time lake exe fmt --check --recursive Some/Directory >/tmp/leanfmt-check.out 2>&1
```

When optimizing, keep a before/after measurement and validate with the normal checks.

For comment-processing changes, `assertTriviaNormalization` compares slice-based
cleanup with an independent character-based implementation. It covers exhaustive
short delimiter combinations, nested and unterminated comments, mixed line endings,
Unicode, and long comment bodies in both preserved-line and inline modes.
Keep ordinary, short-comment, and cascading near-width conditional chains in
32/64/128-clause performance comparisons. Compare identical outputs as well as
timings: faster comment processing does not establish linear retry scaling.
Avoid optimizing by moving syntax decisions into the renderer.

## Adding a formatting rule

A typical rule change follows this path:

1. Add or inspect a fixture that reproduces the layout problem.
2. Use `--check-missing-rules` if first-class syntax may be falling through to
   `defaultRule`.
3. Use `--trace-renderer` to find the segment path and current rule.
4. If raw parser shape is awkward, add a lossless raw-node decision in
   `SyntaxTree.regroupRawNode`; keep `regroupTree` as the recursive traversal.
5. Add or refine a rule in `LineBreakRules`.
6. Keep rule output logical: break points, soft-source-break policy, mandatory/flow,
   base inheritance, or infix-depth accumulation.
7. Do not make the renderer inspect syntax to solve a local rule problem.
8. Run tests, fixtures, idempotency, and code-preservation checks on representative
   files.

Small parser-wrapper nodes often should be `transparentRule`. Syntax with tight token
requirements, such as projections, should get an explicit rule or transparent dispatch
rather than relying on default flow breaks.

## Adding a space rule

Space rules are local token-pair decisions. Add one only when the decision is independent
of the wider tree and render state. If the answer depends on syntax context, use a tree
rule instead.

After changing space rules, run fixtures that cover:

- comments,
- projection dots,
- braces and brackets,
- declaration punctuation,
- compact bang syntax.

## Release and downstream use

leanfmt is redistributable as a Lake package. A downstream package can depend on a local
checkout while developing:

```toml
[[require]]
name = "leanfmt"
path = "../lean-tools/leanfmt"
```

A published repository can be consumed with Lake's Git dependency form:

```toml
[[require]]
name = "leanfmt"
git = "https://github.com/duckki/leanfmt.git"
rev = "vX.Y.Z"
```

Resolve it without replacing the downstream project's Lean version:

```sh
lake update --keep-toolchain
```

Downstream users can run:

```sh
lake exe fmt path/to/File.lean
```

Before cutting a release or sharing a commit, run:

```sh
lake build
lake build LeanFmt.Tests
lake exe fmt-test --update-fixture --check Tests/Fixtures/*/*.leanfmt
```

For a real-world smoke test, run the formatter in
`--check --check-exception --check-idempotent` mode over a separate Lean repository.

## Review checklist

Before asking for review, summarize:

- which rule or renderer behavior changed,
- whether the requested safety and missing-rule diagnostics passed,
- whether formatting is idempotent on affected files,
- which fixtures or unit tests cover the change,
- any missing-rule exceptions intentionally left unresolved.

Do not commit before review unless the reviewer explicitly asks for a commit.

## External validation

The external validator clones one or more explicitly provided Git repositories,
downloads their Lake build caches, and builds each complete project. It resolves
selected sources through Lake, builds module targets outside the project's default
build, and formats staged copies of every Lake-owned source from that project's
`lake env` while checking preservation, unknown rules, and idempotence. Selected
Lean files without a Lake module target are listed and skipped. Only after every
requested formatter batch succeeds does the validator apply the staged output,
build changed modules in large internal batches, and build the complete project
again. This complete path is the release gate.

For ordinary formatter checkpoints, `--checkpoint` reuses the clone, ownership
classification, setup runtime, and imported artifacts from a previous successful
complete validation. It still formats every selected source with preservation,
exception, and idempotency checks and applies the output for review, but it runs no
target-project Lake build. This keeps broad Hex and Mathlib formatting coverage
cheap enough for intermediate checkpoints; it does not replace the complete gate
before release.

Staging keeps the clean build artifacts usable while later formatter batches import
files formatted by earlier batches. Lake setup files also identify the project-wide
set of native libraries and parser plugins required by the selected source
environments. The validator preserves Lake's load order: native libraries first,
then plugins.

Before formatting, the validator compares the project's `lean-toolchain` with
leanfmt's. A matching project uses the formatter built in the main checkout. For
a different Lean version, the validator automatically mirrors the current
formatter source into
`.scratch/external-validation/formatter-toolchains/TOOLCHAIN`, retains that
mirror's incremental `.lake` build, builds `fmt` with the target toolchain, and
runs the resulting executable from the target project's `lake env`. Neither the
main checkout's build artifacts nor the target repository's package declaration
is changed.

The current release checkpoints and known external-formatting issues are tracked
in [plan.md](plan.md).

```sh
scripts/validate-external-projects.sh $HOME/lean-libs/mathlib4
```

At least one Git repository argument is required; there are no preset targets.
Pass either `GIT_REPO` or `NAME=GIT_REPO`. The source can be a local path or any
clone source accepted by `git clone`. The validator makes a fresh scratch clone
unless `--reuse-clone` is passed:

```sh
scripts/validate-external-projects.sh $HOME/target-repo
scripts/validate-external-projects.sh my-project=$HOME/target-repo
```

After a complete validation succeeds, the validator records a checkpoint baseline
next to the project logs. The baseline binds the reusable manifests to the clone's
Git revision, Lean toolchain, file selector, and exact selected-source list.
Checkpoint mode implies clone reuse and refuses stale or missing state before it
formats anything:

```sh
LEANFMT_VALIDATION_LINE_WIDTH=100 scripts/validate-external-projects.sh \
  --checkpoint --files Mathlib \
  mathlib=$HOME/work/lean-libs/mathlib4
```

Run the ordinary command once whenever the clone revision, toolchain, selector, or
selected files change. A complete run refreshes the baseline only after every
formatter batch, changed-module build, and aggregate post-format build succeeds.
`--checkpoint` cannot be combined with partial batches or explicit build targets.

Pass `--files FILE_SELECTOR` to validate a subset of Lean files. A project can
also override the current selector with `GIT_REPO::FILE_SELECTOR` or
`NAME=GIT_REPO::FILE_SELECTOR`. An exact existing `.lean` file is included even
when a companion-environment setup generated or copied it as an untracked file.
When the selector names a tracked directory, every tracked `.lean` file under
that directory is included. Other selectors are passed to `git ls-files`, so
quote patterns containing `*` to keep the shell from expanding them first:

```sh
scripts/validate-external-projects.sh \
  --files Mathlib/Combinatorics \
  mathlib=https://github.com/leanprover-community/mathlib4.git
```

By default, the validator runs each project's Lake default targets before and
after formatting. Repeat `--build-target TARGET` to use explicit acceptance
targets instead. The targets apply to every project argument in that invocation,
so use a separate invocation when companion projects need different targets:

```sh
scripts/validate-external-projects.sh \
  --build-target CompPoly.Univariate.CMvEquiv \
  --build-target CompPoly.Bivariate.CMvEquiv \
  --files 'CompPoly/*/CMvEquiv.lean' \
  --reuse-clone comp-poly=$HOME/validation/CompPoly
```

Explicit targets are appropriate when a prepared companion project has a
narrow declared acceptance surface and unrelated default targets are not part
of the source being validated. Both the initial and final builds use the same
target list.

Complete validation runs in batches of 100 files by default. The validator first
runs one complete project build, resolves and builds every selected Lake module,
and copies the owned sources to its staging tree. Each validation batch formats
staged files with the exception and idempotency checks enabled. Batches continue
until all are formatted or one reports a diagnostic failure. A formatter failure
leaves the project sources untouched and stops validation immediately without a
final build.
After every requested batch succeeds, the validator applies all staged output, builds
changed module targets, and runs one complete project build. Within each batch,
leanfmt manages formatter worker processes and batch sizing. The validator prints the
selected, Lake-owned, and unowned file counts; total batch count; selected batch;
batch index range; first/last file; setup-runtime count; and any
worker-job override. Without `--batch`, it runs batches in order and stops formatting
at the first failed batch.
Pass `--batch N` to run only a specific 1-based validation batch:

```sh
scripts/validate-external-projects.sh \
  --files Mathlib/Combinatorics \
  --batch 2 \
  mathlib=https://github.com/leanprover-community/mathlib4.git
```

To resume an interrupted scratch validation, pass `--start-batch N` with
`--reuse-clone`. The validator keeps the existing clone and staging tree, then
validates batch `N` and every later batch for the same file selection. Add
`--skip-initial-build` only when that same clone already completed the clean
pre-format build:

```sh
scripts/validate-external-projects.sh \
  --files Mathlib \
  --start-batch 34 \
  --reuse-clone \
  --skip-initial-build \
  --skip-final-build \
  mathlib=$HOME/work/lean-libs/mathlib4
```

Validation batches remain serial so a failure has one unambiguous stopping point.
Within each formatter invocation, worker batches run concurrently up to the configured
job limit. Each validation batch writes its formatter output to
`.scratch/external-validation/logs/PROJECT/batch-N.log` and updates the adjacent
`state` file with the running, passed, or failed batch. The same log directory records
the selected, Lake-owned, unowned, changed, setup, and runtime paths, so
interrupted runs can be diagnosed and resumed without overlapping formatter
invocations.

For formatter-only iteration, pass `--skip-final-build`. The initial clean build
still runs, and successful staged output is still applied, but the validator omits
the changed-module and complete builds:

```sh
scripts/validate-external-projects.sh \
  --files Mathlib \
  --skip-final-build \
  mathlib=$HOME/work/lean-libs/mathlib4
```

Clones are created under `.scratch/external-validation`; `--reuse-clone` requires
the corresponding existing clone there. Set
`LEANFMT_VALIDATION_DIR` to use another directory,
`LEANFMT_VALIDATION_SKIP_CACHE=1` to build without downloading caches,
`LEANFMT_VALIDATION_FILE_PATTERN` to change the default file selector, or
`LEANFMT_VALIDATION_BATCH_SIZE` to change the validation batch size.
`LEANFMT_VALIDATION_FORMATTER_JOBS` passes `--jobs` to limit concurrent workers;
the automatic worker count uses the machine's hardware concurrency for both default
and imported environments. Multi-file formatter invocations first process
scripts with only implicit `Init` imports in leanfmt's default Lean environment, then
process files with explicit imports in short-lived workers. Classification uses import
headers, not speculative parsing without the declared extensions. It runs in
bounded parallel batches and records source sizes from the same file reads; the worker
scheduler spreads large files across its batches. The parent asks Lake
for the target package's augmented process environment once and launches workers
directly with it. Without a common input Lake root, including temporary staged
copies, workers inherit the caller's current directory and process environment
without another Lake invocation. Imported files are grouped by exact normalized import header. A group
is never split across workers, even when it contains many files, and every group gets
one worker process. The work-conserving queue keeps the configured job count active.
Each imported worker skips leanfmt's default environment, imports its one exact header
with `leakEnv := true`, shares that environment across the group's files, and exits.
When stderr is a terminal, the parent pipes and concurrently drains worker stdout
and stderr, forwarding complete lines to their original destinations. One shared
status writer clears the in-place progress line before each message and restores
it afterward; parent batch diagnostics use the same lock. Output is not retained
for an entire batch, and ordering between workers or streams is not guaranteed.
A final unterminated message gets a newline only on a terminal destination.
Without terminal progress, workers inherit stdout and stderr directly as before.
Files with a `module` header use exported
`.olean` data; scripts use private data, matching Lean's frontend.
Lean itself computes every transitive import, IR phase, initializer, and persistent
extension; leanfmt does not derive environments from a superset. Lowering the worker-job
count reduces peak memory. `--env-cache-size N` remains an internal compatibility
control for exercising Lean's incremental first-import path; the default zero uses
Lean's direct importer. Set
`LEANFMT_VALIDATION_LINE_WIDTH=N` to pass a project-specific line width to every
formatter invocation.

Imported environments can dominate both runtime and memory. Compare one and two
workers on the target machine with
`LEANFMT_VALIDATION_FORMATTER_JOBS=1` and
`LEANFMT_VALIDATION_FORMATTER_JOBS=2`. Lean's own memory ceiling is a soft,
per-process runtime check rather than a total budget for all workers, so worker count
is the reliable control for avoiding system-wide memory pressure.
Worker isolation also applies with `--jobs 1`; imported environments are released
when each worker exits rather than accumulating across unrelated import groups.
Serialize heavy validation, baseline, candidate, and test-suite runs on
memory-constrained machines. Start with one worker for import-heavy projects,
including direct CLI runs over temporary copies (`fmt --jobs 1 ...`). On macOS,
monitor physical footprint including compressed memory, not RSS alone; swapped
processes can report small RSS while still causing severe memory pressure.

For example, mathlib and CSLib can be validated at their 100-column convention
while continuing to use fresh scratch clones:

```sh
LEANFMT_VALIDATION_LINE_WIDTH=100 scripts/validate-external-projects.sh \
  --files Mathlib \
  mathlib=$HOME/work/lean-libs/mathlib4
LEANFMT_VALIDATION_LINE_WIDTH=100 scripts/validate-external-projects.sh \
  cslib=$HOME/work/lean-libs/cslib
```

The script stops formatting at the first failing validation batch without building.
After every requested batch succeeds, complete validation runs the post-format
builds unless `--skip-final-build` was passed. Checkpoint mode deliberately omits
them and reports that it is not release evidence. The script exits with a nonzero
status if any executed phase failed. Each phase and the final summary include
elapsed wall-clock time. Build-cache retrieval is an optional optimization:
repositories without a `cache` executable are reported as skipped rather than
failed.
