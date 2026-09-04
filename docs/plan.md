# Version 0.4 plan

Rules must describe general syntax ownership. External paths and declaration
names are evidence for tests, never formatter conditions. Missing-rule coverage
is release-blocking only for Lean's standard library and Mathlib.

## Open Issues

### Parser-described peer sequences

The registered-format audit found two first-class syntax gaps. Application-shaped
`match_expr` constructor patterns and level `max` operands should reach ordinary peer
application ownership. Long `universe` identifier tails should reach a peer-sequence
owner. Generalize parser-shape classification; do not add syntax-kind rules.

### Rule inventory

Core, Std, and Mathlib remain first-class syntax targets, but the dispatch table still
contains historical compatibility entries. Remove an entry only when parser metadata or
a general structural owner gives the same reviewed layout across the validation corpus.

## Progress

### Checkpoint 1: structural headers and peer continuations

Complete macro pattern regrouping, anonymous declaration-header consistency,
and peer application continuation ownership. The exact Mathlib `v4.33.0` gate
completed with all formatter diagnostics at zero and both post-format builds
passing.

### Checkpoint 2: application and suffix consistency

Complete focused coverage for the reviewed application, local declaration,
conditional, tactic suffix, and low-priority-pipe examples. Shared ownership now
uses the existing application and suffix mechanisms. The complete local gate,
GraphQL, quantum, and width-100 Hex validation passed; quantum produced no
formatting changes, and Hex's previously slow failing batch passed in 126
seconds. Focused Mathlib probes passed. The Mathlib checkpoint was unavailable
because this selector has no recorded baseline, so the final full gate will
establish it.

### Checkpoint 3: delimiters, command boundaries, and release gate

Complete delimiter-closer rebasing, command-sequence spacing, modified
declaration ownership, compact `match_expr` alternatives, structural `using`
continuations, and parser-safe `initialize` operands. The complete local gate,
GraphQL, quantum, and width-100 Hex validation passed; quantum produced no
formatting changes. The exact Mathlib `v4.33.0` baseline formatted 8,311 files
with every diagnostic at zero and passed both post-format builds. A subsequent
width-100 checkpoint covered all 84 formatter batches. After a focused
`initialize` correction at batch 74, its failing file and batches 74 through 84
were rerun cleanly.

### Checkpoint 4: large-project tail latency

Cache immutable subtree layout facts across speculative render candidates and
avoid allocating normalized copies of already-LF source trivia. The isolated Hex
hot file dropped from about 101 to 32 seconds per formatting pass. The complete
100-file batch that previously varied from 145 to 326 seconds passed every
formatter diagnostic in 67 seconds with unchanged formatting behavior.

### Checkpoint 5: parser-owned layout profiles

Move parser and formatter metadata out of `SyntaxTree` and diagnostics into one
`ParserLayout` adapter. Evaluate each occurring parser description once, retain its
printing annotations, and pass one profile map through regrouping. Explicit `ppSpace`
applications now reuse ordinary application ownership even when Lean also generated a
registered formatter.

### Checkpoint 6: annotation coverage audit

Consolidate raw structural fallback behind one auditable dispatch boundary. Parser-derived
applications and owned bodies already reach logical rules; generated unary prefixes and
ordinary matrix delimiters now use generic structural classification instead of project
syntax names. Keep core parenthesized wrappers, generated collection spellings, and the
Aesop rule-expression sequence explicit where one parser kind has multiple immediate child
shapes or changing the entry would alter reviewed layout.

The complete local gate passed. Full GraphQL and quantum validation established clean
build baselines; exact-tree checkpoints then passed with no changed sources. Width-100 Hex
passed all 873 owned files in 502 seconds, with its heaviest batch at 120 seconds. Width-100
Mathlib passed all 8,311 files and its full 8,705-job build, also with no changed sources.

### Checkpoint 7: registered-format experiment

Add an isolated, fail-closed adapter that executes one registered Lean formatter and
accepts its layout only when the rendered lexemes align exactly with source tokens and
its indentation maps to whole leanfmt levels. Rewritten or inserted tokens, comments,
multiline tokens, blank lines, unsupported whitespace, and incomplete source coverage
are rejected. This makes registered output useful as an audit oracle, but not yet as a
production layout source: comments require lossless reinsertion, and executing a
formatter per syntax node would add uncontrolled work to the hot path.

The production formatter does not import the experiment, and external formatting did
not change. The complete local gate, GraphQL, quantum, width-100 Hex, and width-100
Mathlib validation passed. Mathlib formatted all 8,311 files with every diagnostic at
zero and completed its 8,705-job aggregate build.

### Checkpoint 8: symbolic registered-rule deduction

Replace width-specific rendered-output observation with a symbolic `Std.Format` audit.
The audit now aligns text exactly to source tokens, retains soft and hard breaks, nesting,
group coupling, and source tags, and rejects column-relative alignment. It normalizes
transparent parser wrappers and recursive same-kind spines into logical children before
proposing an existing rule family with child-boundary breaks and indentation.

At least two samples must produce the same generalized operand/atom shape, rule family,
boundaries, indentation, and group paths before a candidate is called stable. Registered
formatters remain a development-time oracle; no production formatter module imports or
executes this deduction path.

The complete local gate passed with no fixture or self-formatting changes. External
baselines were not repeated because the formatter, parser, regrouping, rules, renderer,
diagnostics, and CLI dependency graph is unchanged.

### Checkpoint 9: registered ruleset audit

Add a development-only corpus tool that samples registered syntax, deduces stable
symbolic candidates, and compares their normalized direct-child boundaries with the
current production tree. Production breaks may be owned by regrouped descendants, but
nested breaks inside one logical child and leading boundaries are excluded.

The representative audit parsed 20 files each from Lean Core, Std, and Mathlib without
failure. It inspected 58,116 registered-syntax occurrences in 499 normalized groups; 115
groups produced stable candidates. Manual review classified broad application,
prefix-indentation, infix-side, balanced-delimiter, import, attribute, and source-island
differences as intentional. It found two actionable general gaps: parser-described peer
applications outside ordinary terms and command peer sequences. See
`docs/ruleset-audit.md`.

## Next Checkpoints

### Parser-described peer ownership

Cover application-shaped `match_expr` patterns and level operands through the existing
application classifier, then cover long `universe` tails through a general command peer
sequence. Add focused overflow and idempotency tests before external validation.

### 0.4 release gate

Run the complete local gate, GraphQL and quantum review, width-100 Hex, and a clean
Mathlib build-and-format validation. Minor formatting changes are acceptable when they
follow the simpler documented ownership model.

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

Mathlib validation uses exact `v4.33.0` commit
`db584cd6d46c92f209a44c0f1c829460d327499d`, formats only `Mathlib`, and uses
the Lake cache. The release gate recreates or resets the validation clone and
runs the clean, changed-module, and aggregate post-format builds. Later
formatter-only reviews may reuse that exact baseline when its revision,
toolchain, selector, and source manifest remain unchanged.
