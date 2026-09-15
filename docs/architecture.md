# leanfmt architecture

This document explains the implementation choices behind leanfmt. It is written for
contributors who want to understand or reproduce the formatter, not for users deciding
whether they like the style. For style rules and examples, see [design.md](design.md).
For build, test, debugging, and profiling commands, see [development.md](development.md).

leanfmt is a structure-preserving formatter. It parses Lean source with Lean's own
parser, converts the raw syntax into a lossless tree, asks syntax rules where line
breaks may occur, and lets one renderer choose physical whitespace and indentation.

## Design constraints

The implementation follows a few constraints that shape the whole codebase:

- Every source token must remain present exactly once and in source order.
- Formatting rules may inspect syntax tree shape, but they must not inspect renderer
  state such as current column, pending indentation, or output text.
- The renderer may inspect rendering state, but it must not make syntax-specific layout
  decisions from token spelling or node kind.
- Space decisions and line-break decisions are separate.
- Proof subtrees are preserved rather than reformatted.
- Unknown syntax must remain formatable and lossless, even when it receives only generic
  wrapping behavior.

These constraints deliberately rule out a classic pretty-printer pipeline that lowers
Lean syntax into an unrelated document algebra. Lean's parser tree contains source spans,
custom syntax, layout-sensitive proof blocks, and empty parser wrapper nodes. leanfmt
keeps that tree close to the source and introduces only the logical regrouping needed by
rules.

## Module map

The implementation is split by responsibility:

| Module | Responsibility |
| --- | --- |
| `LeanFmt.ParserLayout` | Evaluate imported parser descriptions once per occurring syntax kind and compile formatter availability, printing annotations, precedence, application shape, and trailing-body ownership into conservative syntax-layout facts. |
| `LeanFmt.RegisteredFormatAudit` | Inspect one registered Lean formatter's symbolic document, align it exactly with source-backed syntax, and propose a stable structural rule candidate. This module is not imported by the production formatter. |
| `LeanFmt.SyntaxTree` | Parse Lean source, keep token/trivia spans, classify delimiter envelopes, build the raw tree, and regroup selected raw syntax into logical nodes. |
| `LeanFmt.Formatter.SpaceRules` | Perform low-level token spacing and lossless trivia cleanup/reindentation. |
| `LeanFmt.Formatter.SourceBoundary` | Represent source trivia between tokens and expose comment, forced-break, blank-group, and ownership facts. |
| `LeanFmt.Formatter.LayoutTree` | Prepare a rendering view and guarded token joins: flatten uninterrupted conditional continuations, retaining nested ownership at source-forced or renderer-reported splits. The lossless syntax tree is unchanged. |
| `LeanFmt.Formatter.LineBreakRules` | Define rule-facing segments, rule context, break points, node-kind dispatch, and syntax-specific rule authoring. |
| `LeanFmt.Formatter.LayoutPlan` | Resolve one rule into a typed, normalized segment plan before rendering. |
| `LeanFmt.Formatter.Rebase` | Represent one source/output layout anchor and translate source columns through it. |
| `LeanFmt.Formatter.OriginalTree` | Classify protected source-layout islands, resolve explicit island policies, and plan indentation-preserving source emission. |
| `LeanFmt.Formatter.Renderer` | Carry render state and its immutable syntax-tree fact cache, choose among resolved layout alternatives, compute indentation, and emit tokens. |
| `LeanFmt.Formatter.Trace` | Record and format renderer traces for debugging. |
| `LeanFmt.Formatter.Diagnostics` | Analyze compact bang syntax, code preservation, overflow, and missing formatting rules. |
| `LeanFmt.Formatter` | Public formatting API plus `Debug` and `Internal` namespaces for tracing, profiling, and shared pipeline phases. |
| `LeanFmt.Cli` | Command-line argument parsing, hidden-aware file discovery, check mode, and validation checks. |
| `LeanFmt.Main` | Thin executable entry point that supplies runtime hardware concurrency to the toolchain-independent driver. |

The test-only executable is separate:

| Module | Responsibility |
| --- | --- |
| `LeanFmt.Tests.Cli` | Fixture update/check mode, renderer trace printing, and profile output. |
| `LeanFmt.Tests.Main` | Minimal `fmt-test` executable entry point. |
| `LeanFmt.Tests.Run` | `testSuite` entry point for `lake test`; sequential subprocess isolation bounds each test group's imported-environment lifetime. |
| `LeanFmt.Tests.Suite` | Root of the test library, containing unit-style formatter checks grouped into syntax-tree, basic formatting, expression/renderer, control-flow, collection/declaration, and CLI/architecture suites. |

Every imported test module is rooted at `LeanFmt.Tests`. A downstream package may
therefore define its own top-level `Tests` library without either package claiming the
other package's `Tests.*` modules. Lake package scope does not create a Lean module
namespace, so the namespace is explicit in the module names. The library explicitly uses
`LeanFmt.Tests.Suite` as its root, allowing all imported test sources to live under
`LeanFmt/Tests/` without a `LeanFmt/Tests.lean` forwarding module. Fixtures remain under
`Tests/Fixtures` because the test CLI reads them as files rather than importing them.

The Batteries environment linter lives in a separate Lake package under
`tools/linter`. That package depends on leanfmt by a local path and may pin
development-only lint dependencies. The root package and its manifest therefore
describe only the library and executables distributed to downstream users.

## Pipeline

Formatting a file follows this pipeline:

1. Normalize line endings to `\n`.
2. Parse the header and commands with Lean's module parser. The default public API
   uses an environment that imports `Lean` with parser extensions enabled. While each
   command's parser scope is active, probe every layout-delimited `let` body with Lean's
   term parser at application-argument precedence and retain the result as a parser
   fact. After parsing, `ParserLayout` evaluates each occurring syntax kind once. Its
   profile records formatter availability, `ParserDescr` printing annotations such as
   `ppSpace`, `ppLine`, grouping, indentation and dedentation, trailing-parser binding
   powers, conservative spaced-application shape, and parser-owned trailing bodies.
   These facts let logical regrouping follow imported and locally declared syntax
   without putting environment access, parser combinators, or project syntax names in
   line-break rules. Namespace and section entry/exit are elaborated through Lean's
   command state so scoped and local notation follow the source scopes.
   `ModuleParseState` keeps the parser position, command state, syntax, and let-body
   facts together. A fully elaborated checkpoint begins at the header. Quiet parsing
   postpones ordinary declarations, variable/universe declarations, include/omit
   commands, and module documentation. Declaration attributes and deriving handlers
   prevent postponement. The standard Mathlib and Batteries `lemma` implementations
   share the ordinary-declaration policy; unknown command implementations do not.
   The classifier uses audited macro and command elaborator implementation names,
   not syntax names or Lean's `isBuiltin` flag (which also marks some local entries).
   Missing, replaced, and mixed-policy handlers use the frontend.

   A standard `mutual` block can also be postponed when every member is an ordinary
   declaration accepted by that same policy. The container's registered elaborator
   and macros must be the audited Lean implementations. Declaration-only membership
   leaves its element-expansion and preamble macros inactive; namespace/end handlers
   must also retain their standard scope policy because qualified names can expand to
   a namespace wrapper. Attributes, deriving hooks, preambles, custom member macros,
   and replaced handlers keep the block on the frontend path. Postponement does not
   discard declarations or their proof bodies: the next environment-observing command
   still replays the complete pending prefix.

   Standard namespace, section, end, and standalone `set_option` commands update the
   quiet parser scope. The audited option handler uses registered option declarations
   and literal values, updating scope options and the cached recursion limit without
   observing pending declarations. `set_option ... in ...` is a separate wrapper and
   retains frontend replay, as do replaced option handlers. Every other command,
   including local syntax declarations, `run_cmd`, wrappers, attributes,
   and custom commands, runs through Lean's frontend with the complete preceding
   source state. The frontend processes only the pending prefix through that command;
   its result becomes the next checkpoint, and quiet parsing resumes. A successful
   command is not assumed independent of skipped declarations: environment absence
   queries are observations too. Earlier prefixes are not elaborated again, and the
   formatter does not try an opaque command speculatively before replaying it.
   Lean's parser end-position limit bounds this work without truncating the source or
   file map visible to command elaborators.
   If parsing itself fails, the command boundary is unreliable, so recovery processes
   the complete remaining source instead, respecting Lean's terminal commands such
   as `#exit`. Header and command-parser errors remain
   fatal, including errors Lean recovered from; unrelated elaboration errors remain
   tolerated. Each quiet scope update checks only its own diagnostics. Frontend replay
   isolates standard output/error streams, matching quiet scope elaboration.
   Both paths record let-body facts with the pre-command parser context. Frontend
   snapshots supply the state for the following command, keeping scoped syntax and
   namespace transitions equivalent without probing against the final environment.
   Missing facts still use conservative start alignment.
   Recovery cannot assume theorem bodies are irrelevant to parsing: a command
   elaborator can inspect a theorem's proof term before registering syntax. Lean's
   asynchronous elaboration still computes those bodies and requires ownership of its
   tasks and diagnostics; it is not a selective source-dependency API. Replacing
   declarations with headers, skipping attributes, or guessing dependencies is not
   part of the parser recovery contract.
   Info-tree collection is also observable through command state. Disabling it
   is not an assumed semantics-preserving optimization. Lean's minimal command-line
   snapshots discard the parsed syntax, parser state, and command scopes that
   prefix recovery needs; those snapshots cannot replace the complete state here.
   Repeated parsing and idempotency cannot independently detect a shared environment
   error. Parser-boundary regressions therefore compare with Lean's complete frontend
   and check elaboration of both original and formatted source. No selective-dependency
   scheduler or cross-source parser-state cache is implemented.
   Lean 4.33.1's optional old command snapshots reuse elaboration only across an
   unchanged source prefix, comparing syntax with source information and trailing
   trivia. The first changed command invalidates downstream snapshots. Formatting
   commonly changes that prefix, and an opaque command can inspect the complete
   file map, not just its preceding text. Snapshot reuse therefore does not provide
   a general shortcut for required prefix elaboration. The independent idempotency
   pass must execute command elaborators again; cached final modules serve the
   other diagnostics, not that independent parse.
   The CLI selects the environment from the source import header before parsing.
   A successful parse with fewer imports cannot establish equivalent syntax: an
   imported keyword can otherwise parse as an identifier and an operator. Only
   scripts with no imports beyond implicit `Init` use the default environment.
   For multi-file formatting, a bounded parallel classification pass reads
   each file once, selects its environment from the header, and records its source
   size. Files that use the default environment are sorted by size and spread across
   worker processes, keeping large files from collecting in one batch. Imported files are grouped by exact
   normalized import header, and every file in one group stays in the same worker. The parent
   obtains the target package's augmented environment from Lake once, then starts all
   formatter workers directly with that process environment. Isolation does not
   require a Lake root: temporary inputs and files without a common package root
   use the caller's working directory and complete inherited process environment,
   without invoking Lake again. This preserves externally supplied search paths,
   package overrides, and runtime-library requests. Even `--jobs 1` starts a fresh
   worker for each exact import group; it limits concurrency, not isolation.
   When imported parser-state
   commands require downstream native implementations, the driver loads the symbol
   libraries listed in `LEANFMT_LOAD_DYNLIBS` through Lean's dynamic-library API. It
   initializes parser plugins listed in `LEANFMT_LOAD_PLUGINS` inside Lean's importing
   context and carries both requests into every worker, keeping worker and
   single-process behavior equivalent.

   An imported worker skips the formatter's default `Lean` environment, reads its
   group's header first, and asks Lean to construct that one exact environment with
   `leakEnv := true`. Every file in the group shares the environment, keyed by the
   ordered imports and import level, and the process exits after the group. This
   matches Lean's one-module process lifetime and avoids reference-count work for an
   environment that survives until process exit. An internal bounded cache can retain
   Lean's opaque `ImportState` after the first direct import when explicitly enabled;
   the normal one-environment worker path uses Lean's direct importer. LeanFmt never
   inspects or reconstructs the state.
   Dropping the last cached environment is not an imported-region reclamation
   guarantee when Lean extensions are loaded. Process exit bounds that lifetime;
   the driver does not manually free regions that extensions may still reference.
   Files with a `module` header use exported `.olean` data; scripts use private data,
   matching Lean's frontend. Lean therefore remains responsible for its import fixed
   point, public/private data selection, IR phases, user initializers, and persistent
   extensions. `LeanEnvironment.lean` is the narrow maintenance boundary for these
   APIs. Driver policy is deliberately separate.

   The automatic worker count follows the machine's hardware concurrency for both
   default and imported environments. The scheduler keeps the configured number of
   one-environment workers active until its queue is empty. `Driver.Status` owns
   synchronized terminal output: when progress is active, worker stdout and stderr
   are drained concurrently and relayed line by line, clearing and restoring progress
   under the same lock as parent diagnostics. Output is not buffered by batch or
   reordered into batch order. Non-interactive workers inherit the streams directly.
   `-j` or `--jobs` overrides the automatic worker count.
   Setting `--env-cache-size` to a positive value enables the incremental
   prefix-state path for compatibility testing; zero is the normal direct-import path.

   The parent process keeps the default environment alive while imported workers run,
   so the peak is approximately one default environment plus one custom environment
   per active imported worker. Lean's runtime memory limit is per process and is
   sampled periodically at system-check points; it is not an aggregate budget or a
   concurrency controller. `--jobs` remains available when a particular project or
   machine benefits from a lower concurrency limit.
3. Convert Lean `Syntax` to a `SyntaxTree.Tree` of tokens and raw parser nodes.
4. Regroup selected raw nodes into logical `SyntaxTree.NodeKind` nodes.
5. Prepare the layout tree using source-boundary facts. Build renderer fact caches
   from this view, so all fit probes and traced rendering use the same child indexes.
6. Render the layout tree using line-break rules and space rules.
7. Reparse and rerender until the text reaches a fixed point, subject to the
   hard convergence limit.
8. Clean final trivia and normalize the final newline.

Each convergence pass uses the same parser/tree/rule/renderer pipeline; there is no
separate cleanup layout algorithm. If a construct formats poorly, the fix is to add or
refine a tree grouping, a line-break rule, a space rule, or renderer state logic. The
renderer is the only component that emits text.

The internal `ConvergenceResult` returns either the converged module or fallback text.
`formatSourceWithModules` retains the original normalized module alongside that result
for one file operation. The public formatting APIs still return their existing text
results. The CLI uses the retained modules for preservation, overflow, and missing-rule
diagnostics instead of reparsing them. Missing rules use the original module's source
positions; overflow uses the converged module. Fallbacks do not supply a converged
module and continue to bypass ordinary diagnostics.

Ignored-region formatting retains the complete original module and parses the complete
assembled candidate if its text changed. Individual chunk modules are never used as
whole-file diagnostic evidence. The independent idempotency check still runs a fresh
formatting operation when output differs from the input. This is per-file ownership of
already-produced data, not a cache across files, sources, environments, or invocations.
At most the original and current convergence modules are retained across passes; no
module history is kept after the file operation returns.

`Formatter.Internal.maxConvergencePasses` currently limits formatting to four passes. The
driver tracks previously seen results. A parse failure, cycle, or exhausted pass limit
causes a warning and returns the original normalized source. Fallback is deliberately
nonfatal so `--check-exception` and `--check-idempotent` can report formatter
problems without replacing a file with an unsafe intermediate result. The CLI caches
import-specific environments by the normalized import list to avoid reloading common
project headers for every file.

## Syntax tree

`SyntaxTree.Module` is the parsed source model:

```lean
structure Module where
  source : String
  rawSyntax : Syntax
  tree : Tree
  tokens : Array Token
```

`source` is the normalized source text. `rawSyntax` is Lean's parser output. `tree` is
the regrouped tree used by rules and rendering. `tokens` is a flattened token view used
for reconstruction and diagnostics.

`SourcePositionMap` stores Lean's precomputed line starts for the normalized source.
Renderer and diagnostic column queries share this map instead of rescanning the source
prefix for every token.

The renderer also builds an immutable fact tree alongside the lossless syntax tree for
each formatting pass. It caches protected-layout classification and comment-boundary
containment, then follows child scopes in lockstep with rendering. The cache records
decisions owned by `OriginalTree` and `SourceBoundary`; it does not introduce syntax or
line-break policy in the renderer.

Tokens are exact source leaves:

```lean
structure Token where
  role : TokenRole
  kind : SyntaxNodeKind
  value : String
  lexeme : String
  leading : Trivia
  trailing : Trivia
  span : Span
```

`lexeme` is the text the renderer emits. `leading` and `trailing` preserve original
trivia text and spans. Rules must never synthesize replacement token text. Space rules
may clean trivia when using it as inter-token whitespace.

The tree shape is intentionally small:

```lean
inductive NodeKind where
  | raw (kind : SyntaxNodeKind)
  | letExpression
      (kind : SyntaxNodeKind)
      (bodyCanStartApplicationArgument : Bool)
  | application
  | infixChain (kind : SyntaxNodeKind)
  | definition
  | annotatedDeclaration
  | modifiedDeclaration
  | signatureParameters
  | structureHeader
  | structureConstructor
  | structureDeriving
  | parserOwnedHeader
  | parserOwnedBody
  | tacticAttachedProof
  | matchHeader
  | matchDiscriminants
  | matchPatterns
  | doForHeader
  | doFallbackClause
  | doFallbackContinuation
  | structureUpdate
  | ifThenElseClause
  | ifThenElseChain (kind : SyntaxNodeKind)
  | proofBody
  | derivingClause
  | unifConstraints

inductive Tree where
  | missing
  | leaf (token : Token)
  | node (kind : NodeKind) (children : Array Tree)
```

### Raw extraction

`extractRawTree` recursively converts Lean syntax into:

- `.missing` for missing syntax,
- `.leaf` for atoms and identifiers,
- `.node (.raw kind) children` for parser nodes.

Atom and identifier leaves record source spans through `SourceInfo`. Synthetic and none
source-info tokens are preserved as tokens with synthetic trivia and spans. A parsed
module containing a nonempty lexeme that cannot be recovered from its source span is not
safe to reconstruct, so the public formatter preserves that module unchanged before
rendering. Empty structural parser tokens do not trigger this guard.

`Module.reconstruct` sorts all tokens by source span and concatenates each token's full
trivia and lexeme. This is the basic losslessness check: parsing and extracting a tree
must be enough to reconstruct the source.

### Regrouping

Raw parser shape is sometimes inconvenient for formatting. Regrouping is the only phase
that changes the lossless syntax tree's shape. Layout preparation may derive a separate,
token-equivalent rendering view without replacing that syntax tree.

Current logical regroupings are:

| Logical node | Why it exists | Expected children |
| --- | --- | --- |
| `.letExpression kind bodyCanStartApplicationArgument` | Layout-delimited `let` needs a parser-derived answer to whether its body could be consumed as one more right-hand-side application argument. The active parser scope supplies this fact, so imported and locally declared syntax extensions behave according to their precedence without appearing in a formatter keyword list. | The original raw `let`, `letI`, or `letrec` children, unchanged. The raw kind is retained for ordinary rule dispatch and diagnostics. |
| `.application` | Lean parser applications are nested per argument, but formatting wants one function-application segment. Generated term parsers can express the same shape as a head and arguments separated by empty `ppSpace` groups; recognizing that structural pattern prevents continuation indentation from staircasing through the generated wrapper. An extension parser can prove the same ownership when its complete descriptor is one tight word-like leading symbol, optional clauses, and one final term or identifier operand. `ParserLayout` removes only Lean's printing-only combinators while matching that shape, so an explicit `ppSpace` and implicit lexical separation behave alike even when the syntax also has a registered formatter. Punctuation-only heads remain unary or extension-owned syntax. Applications normally own their physical start column, including applications on ordinary infix, pipe-projection, and low-priority-infix operands. A parser-described spaced tactic instead owns the operand continuation base through transparent parser and low-priority-infix envelopes. Exactly one simple parenthesized proof argument is regrouped with its envelope so the complete application can probe a compact proof. When multiple structured proof arguments require mandatory peer layout, every parenthesized argument retains a peer boundary; an ordinary argument after any parenthesized peer starts a peer run at the same application base. A sliced run created by those structural boundaries has no function head, so its internal flow uses zero-level peer boundaries instead of adding another application continuation level. This keeps nested terms, named arguments, type ascriptions, proof arguments, and closing delimiters from inheriting incidental inner columns without forcing fitting ordinary arguments onto separate lines. Other arguments keep ordinary flow behavior. `<|` remains exceptional only in its breakpoint policy. A final attached `do` or `by` argument is split into a fitting application header and an owned body, so the body does not force an otherwise fitting header argument onto its own line. | Child `0` is the head, children `1...` are arguments in source order. Raw `null` argument containers are spliced. A generated spaced form requires at least two non-atomic argument trees and exactly one empty generated group between every content child. A parser-described form requires a non-atomic operand separated from its head in source. Direct tactic-sequence entries are excluded from parser-described application regrouping: the tactic retains contextual ownership while an application inside its final term remains an ordinary child owner. Ambiguous generated or extension-owned token sequences retain their missing-rule diagnostic. `return` wrappers move their prefix into a `.suffixGroup` with the application head, so ordinary and lambda arguments share the prefix's structural base instead of the function name's inline column. A terminal attached-body application becomes `.parserOwnedBody`; its header application ends in the introducer and its body is the unwrapped sequence. |
| `.infixChain kind` | Infix peers with equal Lean parser binding powers need one shared chain, and renderer indentation should not infer peer structure from nested raw nodes. Most chains are balanced; ordinary multiplication chains flow so fitting factors can share continuation lines. Same-kind peers remain the compatibility fallback when parser metadata is unavailable. Dedicated nested pipe-projection nodes use the same representation even though their operator token is not exposed as an ordinary binary-infix atom. | Odd-length array alternating operand, operator, operand. Operands are even indexes; operators are odd indexes. The outer parser kind is retained for rule dispatch. A pipe member with arguments is first grouped as one application operand. |
| `.lowPriorityInfixRhs` and `.lowPriorityOperand canFlow hasAttachedBody` | A low-priority operator and its right operand need one local layout owner so attachment and operand alignment do not depend on token inspection or renderer ancestry. Regrouping classifies whether the operand can flow beside the operator and whether it owns an attached body; line-break rules consume only that structural policy. The enclosing infix chain owns the leading boundary before each complete operator-operand group. The nested owner offers a post-operator boundary only for a flowing suffix; a non-flowing operand instead keeps its first line with the operator and uses its own structural breaks. A suffix operand retains its established suffix and original-layout behavior. The nested owner also formats an original child's leading boundary, so the outer break cannot strand the operator and a protected island can reuse its existing structural fallback. | The RHS node contains a policy-bearing operator child followed by the right operand. Every operator-operand pair after the first chain operand has this shape. The operator remains separate from a layout-sensitive binding operand so `let` and `have` can establish the aligned start required by Lean's layout parser. |
| `.calcBody` and `.calcStep` | Lean's raw calc trees hide the boundary after `calc`, wrap later rows separately from the first row, and put each relation, assignment, and proof in wrappers with no shared layout owner. Logical nodes let the term or tactic owner control the body boundary, the body own peer-row alignment, and each step own the proof-body boundary and the tail floor for its relation header. | A term-level calc or annotated calc tactic contains its `calc` token followed by one `.calcBody`. A proofless first term is attached to the keyword through a `.suffixGroup`, followed by the remaining body. The body contains direct `.calcStep` children. Each proof-bearing step contains a `.suffixGroup` header followed by its proof body. The header retains the parser's complete relation tree and `:=`; for `by`, `do`, and nested `calc`, it also contains the suffix introducer while the introducer's body becomes the step body. When that body starts with a parser-defined delimited tactic sequence, its opener joins the attached introducer and the remaining sequence becomes the step body. The step breaks its body one level inward and lifts the multiline header tail two levels inward. The retained relation tree therefore uses ordinary infix, application, and notation rules: its RHS has the usual zero-level infix continuation relative to the raised tail, while the proof body remains one level inside the calc row. The infix rule omits the first operator breakpoint for a bare placeholder relation, keeping forms such as `_ =` and `_ ≤` together while allowing the RHS and proof body to break normally. |
| `.parserOwnedHeader`, `.parserOwnedBody`, and `.parserOwnedTacticBody` | A registered command or tactic parser can declare a trailing keyword clause whose final term or tactic sequence is a body. Exposing that ownership gives the body one structural continuation base without making line-break rules inspect parser kinds, token spacing, or project-specific names. The parser-layout policy records body suffixes, optional repeated-argument header keywords, and whether the owner belongs to the tactic category. A tactic-body marker keeps the proof envelope movable independently of the suffix that completes its header. Optional layout-constrained tactic bodies such as `colGt >> tacticSeq` qualify for the same treatment, including when Lean represents the owner as a trailing parser. Keyword-like suffixes from active `command` and `tactic` parser descriptions qualify, as does `=>` before a recognized tactic sequence; the concrete suffix must occur in the parsed node, so absent optional clauses and other punctuation-only syntax remain opaque. A complete tactic-sequence entry with the structural shape `header => body` receives the same ownership even when the final body uses a custom parser category such as a conversion sequence. Core tactic alternatives whose parser places `=>` at the start of the final tactic sequence use that same ownership after regrouping moves the arrow into the header. Tactic-sequence context, rather than a syntax namespace, proves that ownership; established layout owners such as alternatives retain their dedicated body structure. A parser-described spaced term whose optional header contains a doc comment uses the same ownership because the note is metadata for the following term; ordinary term parsers keep their missing-rule diagnostics. | The body node contains one header followed by the complete body. Every construction path builds a nonempty parser-described prefix through the same `.parserOwnedHeader` normalization: its head attaches to its first argument, a leading `:=` or `←` in the final child attaches to the preceding header tree, and the value remains a structural peer. A final parser-described optional keyword plus repeated-term wrapper becomes a nested header: the keyword and first term form a suffix group, and later terms are direct peers at one continuation base. An ordinary identifier in the body value cannot be mistaken for that keyword. Remaining header arguments retain ordinary flow boundaries even when the value contains a low-priority infix, so the assignment boundary is considered before a later type boundary. A comment-bearing term instead keeps its directive and doc payload in one `.suffixGroup`, retains the source break before its body, and gives that body zero added indentation. Bracketed tactic arguments therefore flow from the tactic base. A command suffix such as `where` attaches to the final header child. A term-body tactic suffix such as `using` attaches to the body application head, leaving that application's arguments as structural peers. A tactic-body suffix such as `says` completes the header, while `.parserOwnedTacticBody` contains only the proof envelope; fitting bodies may remain beside the suffix and broken bodies continue one level from the header base. When this shape is the sole body after `by`, the outer introducer contains a `.tacticAttachedProof` with the parser-owned header and body as peers, so a fitting header remains after `by` and a broken proof uses the header base. Attached `do` or `by` bodies exposed by existing structural syntax use the body node with their existing header shape. In a protected proof, a source-detached body marks the tactic as a layout owner so its continuation can be normalized. |
| `.indexedInfix kind` | Infix notation with an indexed operator needs one leading break before the complete operator without allowing its closing bracket to detach from the index. Recognizing the five-child delimiter shape during regrouping covers generated and explicitly named parsers while keeping delimiter spelling out of line-break rules. A structural RHS introducer inherits the relation base, including through one tight delimiter, so lambda and binder-operator bodies do not inherit the indexed operator's ending column. | The original five children remain in source order: left operand, an operator atom ending in `[`, index, `]`, and right operand. The outer parser kind is retained for rule dispatch. |
| `.delimitedCollection kind` | An anonymous parser wrapper can itself contain a complete delimited collection. Classifying that shape once during regrouping lets rule dispatch reuse the ordinary collection rule without repeatedly searching descendant tokens during layout probing. | The flattened delimiter, item, and separator children remain in source order. The delimiter kind records the parser-derived outer shape. |
| `.suffixGroup` | A header suffix belongs to the preceding syntax even when the parser stores it at the start of the following body wrapper. Grouping it with the header lets the body boundary break first without allowing the suffix to detach under width pressure or retain a removable source break. A declaration's optional universe suffix is similarly attached to its identifier so convergence cannot separate `name` from `.{u}`. The same transparent attachment keeps a tactic prefix with the first line of its final structural proof argument while that argument's intact introducer still owns the proof body. Source-adjacent edge pieces of generated term notation use the same attachment. A generated prefix owner keeps its leading atom attached to the operand, but preserves an ordinary application as a separate child so its arguments retain their structural base. A leading atom and its operand form a suffix group without inserting the atom into the operand's child array. Type ascriptions and infix chains keep their original child positions, so their internal spacing and break policies cannot claim the prefix boundary. The operand retains its own structural layout inside the attachment, including a delimited operand's base at its opener. An adjacent identifier and generated suffix form one application head, so the following arguments share a structural base rather than inheriting the suffix token's column. A fixed extension prefix followed by a `letDecl` attaches to that declaration's existing header; empty optional parser children do not interfere, and value or proof ownership remains with the nested declaration node. A final generated operand keeps its preceding atom, while interior separators remain rule-owned children. A term-taking tactic attaches a terminal opening delimiter to its tactic prefix even after the operand has become an application or infix node and whether or not the tactic also owns nested proof layout; ordinary applications and direct command terms retain an argument boundary. A single-token tactic wrapper attached to a direct tactic sequence uses the same group and forwards a nested layout owner, so `· exact ⟨...⟩` can format structurally without broadening unrelated protected proof islands. Nested `do`-notation declarations attach an existing `do` or `by` introducer to `←`, and a `do if` branch attaches `do` to `else`. A `by` branch retains the existing `else`-body boundary because Lean's layout parser requires its proof body to indent from the nested branch. An optional `private` structure-field value modifier attaches to its complete value; for a lambda it joins the lambda root so descendant breaks inherit the field-value base. The `do if` pass visits only direct clause wrappers, so it cannot rewrite a fallback clause or an already established owner. | The attached trees in source order. `cases` uses this shape for its discriminant and `with`; calc proof headers can include `by {`; generated notation uses it for pieces such as `#{`, `∂μ`, `∂.pi`, an attached `%` suffix, and declaration-like `doElem` syntax. A proof-valued tactic contributes its protected prefix followed by the complete final proof argument. |
| `.tacticAssignmentProof` | A tactic assignment whose value is a non-structural `by` proof needs the assignment boundary to outrank breaks inside its declaration header. Regrouping refines the ordinary trailing-proof split only when its shell ends in `:=`; `by` joins that shell and the proof body becomes a direct child. Proofs containing intrinsic `cases`, `induction`, `match`, or `calc` layout remain intact under their existing owner. | The assignment shell including `by`, followed by the proof body and any trailing syntax. The balanced rule keeps a fitting assignment flat and otherwise breaks before the proof body. |
| `.tacticAttachedProof` | A single-tactic proof exposed after a multiline low-priority tactic shell needs a local continuation base without changing ordinary suffix groups or inherited alternative bases. Regrouping records that ownership once instead of making the renderer inspect `<|`, `by`, or tactic kinds. Multiple-tactic proofs retain the mandatory suffix owner that preserves Lean's layout scope. | The complete parser-owned tactic shell ending in its proof introducer, followed by the proof body and any trailing syntax. The flow keeps a fitting proof attached and otherwise breaks its body one level from the shell's rounded local base. |
| `.namedDiscriminant` | Elimination tactics and dependent conditionals parse a name and `:` separately from the discriminant. A semantic group exposes the lower-priority break before `:` without making the line-break rule inspect tokens or optional-wrapper depth. | The name, `:`, and discriminant in source order. |
| `.patternLambda` | A pattern lambda is a structurally multiline application argument. Giving it a logical kind lets applications break before the complete lambda while the lambda rule owns the alternatives, without searching descendant tokens for `fun` or `|`. The node uses its physical start as its base instead of inheriting an enclosing continuation base; the alternatives' zero-level breaks therefore round an off-column `fun` up to the next indentation boundary, while equation arms settle at their command-relative physical base. | The original raw `Lean.Parser.Term.fun` children, including the direct `matchAlts` child, remain unchanged. Known transparent application-argument wrappers expose this semantic role without separating their prefixes. |
| `.definition` | Definitions, abbreviations, class abbreviations, opaque declarations, and definition-like extension commands need one node containing header, assignment marker, body, and suffixes. | A raw `declValSimple` wrapper is spliced wherever it occurs among the command's children, including through the single optional wrapper used by `opaque`, leaving `:=` immediately before the value/body. A parser-generated `group` with that complete declaration value becomes the same structural owner, so extension declarations do not depend on their keyword spelling. A direct `whereStructInst` also establishes a definition value for generated command syntax; its leading `where` stays on the final signature line while its fields own the following structural breaks. Only a separate `Term.whereDecls` child is treated as an auxiliary declaration suffix. |
| `.annotatedDeclaration` | Every command form that accepts declaration annotations forms one flow, whether it is built in, introduced by a syntax extension, nested under a command wrapper, recursive under `where`, or a named structure constructor. Source breaks are preserved; otherwise the command remains after its annotations only when the complete command fits on one physical line. The wrapper also establishes the command-line base inherited by modifier and declaration children, including a documented declaration nested in `let rec`. | Child `0` contains the leading annotations or, when no annotation is present, the leading declaration modifiers. Any remaining modifiers and the command follow as separate children in source order. An annotation or direct documentation comment embedded in generated command syntax is extracted without changing that command's remaining child indexes; generated term syntax is excluded even when it carries a direct comment child. This applies inside scoped-command wrappers as well as at module level. A leading modifier container in an extensible command is removed from that command and placed before it, so the command starts at its keyword and both remain one flow. Optional wrappers around a recursive declaration's attributes are removed. Structure-constructor modifiers are separated from the constructor command so both inherit the structure field base. An inductive constructor keeps its `|` prefix outside the wrapper so annotations that follow it retain source token order. |
| `.modifiedDeclaration` | Declaration modifiers need the same command-line base as their declaration, but they are not annotation commands and must not activate annotation-flow source-break behavior. Separating the ownership keeps `private`, `protected`, `noncomputable`, and similar modifiers attached while equation alternatives remain relative to the declaration base. | Child `0` is the declaration-modifier container and the command follows in source order. Top-level command annotation records the nested command context without changing this modifier-only policy. |
| `.signatureParameters` | Parameter sequences need flow behavior at binder boundaries without forcing rules to inspect raw `null` wrappers. | Direct binder/parameter children from declaration signatures, function binders, `termination_by` parameter lambdas, and `unif_hint` commands. When the `opaque` parser exposes a declaration identifier and its signature as direct siblings, the signature is merged into the identifier's existing parameter flow. In a termination lambda, the final parameter and `=>` share one child so the arrow stays attached while preceding parameters flow at two indentation levels. |
| `.declarationHeader` | A declaration's return-type boundary and value boundary have different priorities. Nesting the complete header lets it remain flat when breaking only the value is sufficient, without consulting the value's source trivia or inheriting the name's tail column. Signature-only extension commands with one keyword, a direct `declId`, and a direct `declSig` use the same ownership, so their binders and return type follow the command base instead of staircasing through parser wrappers. | Local `Term.letIdDecl` and `Term.letEqnsDecl` nodes place the name, parameter sequence, and optional type specification in this child, then retain assignment and value children in source order. After let-body annotation has restored that complete shape, a source-detached assignment proof is regrouped as a declaration shell ending in `:= by` followed by its proof body. Assigned `initialize` declarations use the same group around their name and optional type. A signature-only extension header attaches its keyword to the declaration identifier and retains the complete signature as the second child. Transparent single-content wrappers are removed when they lead to an explicit `doNested` value or a single-expression assigned initializer, while a multi-statement implicit initializer sequence retains its sequence wrapper and layout ownership. A direct single-expression initializer attaches `initialize` to the operand head only when they share a source line; a detached direct initializer retains its parser-significant sequence boundary. In either attached form, its top-level application cannot break between arguments at the command base because Lean would parse the continuation as another initializer statement; descendants still inherit the command base for their own bodies. A header with a name or parameter owns a possible break before `:`; an anonymous typed header has no preceding header content, so its `:` remains with the surrounding declaration keyword. The outer declaration owns the break after `:=` or `←`. |
| `.macroPattern` | A macro pattern is a parser-owned sequence whose atoms need ordinary peer boundaries when the complete signature does not fit. | Direct, nonempty `Lean.Parser.Command.macroArg` children from the macro parser's pattern container, in source order. |
| `.structureHeader`, `.structureConstructor`, and `.structureDeriving` | A structure header may wrap before `extends`, but that continuation must not become the base inherited by constructors, fields, or `deriving`. Separate render scopes let each part own its break and indentation without renderer state exceptions. | The raw structure has a `.structureHeader` first child, ending in `where` when a body is present. It is followed by an optional `.structureConstructor`, the raw `structFields` node directly, and an optional `.structureDeriving`. Structures and classes that only extend parents still receive a header node. The constructor and deriving wrappers contain their original regrouped syntax. |
| `.matchHeader` and `.matchDiscriminants` | Multiple match scrutinees need peer flow boundaries after commas, aligned under the first scrutinee, rather than generic nested parser wrapping. A complete header also makes the owning `with` explicit when a discriminant contains a nested match, preventing the outer suffix from remaining on the final inner branch line. Term matches and match statements in `do` notation share the discriminant owner even though Lean gives them different raw kinds. | The discriminant node preserves alternating discriminants and commas. Only the ambiguous nested-match case adds `.matchHeader`, containing the discriminants followed by the owning `with`; it breaks before the outer suffix while ordinary match headers retain their existing suffix behavior. A match used as the first operand of a spaced tactic inherits that tactic's structural base, keeping alternatives aligned with the attached `match` introducer. |
| `.matchPatterns` | Multiple patterns in one alternative need peer/balanced wrapping rather than raw nested `null` behavior. | Pattern children from the `matchAlt` pattern wrapper, with a redundant single `null` wrapper removed. |
| `.doForHeader` | A `for` binder and its collection need separate LHS and `in` layout without teaching the renderer about `do` syntax. | The `for` keyword and declaration children before the loop body. |
| `.doFallbackClause` and `.doFallbackContinuation` | Lean's raw `do` tree may store `| fallback` and later commands in one wrapper. Formatting needs an ordinary optional boundary before the fallback clause and a structural boundary before the later command. A source-attached fallback after a simple single-content value may use the existing prefix-retention mechanism to keep `|` on that line while the clause owns a structural break before its body. A detached fallback or one following a structurally breakable value instead uses the parent's ordinary boundary before the complete clause. | The clause contains `|` and its fallback body. The continuation contains every following child that belongs to the surrounding `do` sequence. Both `let pattern := value \| fallback` and `let pattern ← action \| fallback` use this shape, including extensible `let_expr` syntax. |
| `.structureUpdate` | The source before `with` behaves as an LHS expression, while the surrounding braces remain an ordinary balanced structure. | The comma-separated source expressions as direct children, including their separators and the final `with` token. Redundant anonymous sequence wrappers are removed. |
| `.ifThenElseClause` and `.ifThenElseChain kind` | Ordinary, dependent, pattern, and `do`-notation continuations retain conditional ownership independently of source comments. Layout preparation joins uninterrupted runs for the existing balanced branch rule. All conditionals accept source branch breaks without forcing fitting inline branches to break; `do` statement sequences retain their own mandatory boundaries. | A syntax chain contains a clause header, its result branch, `else`, and a complete nested continuation. The last conditional instead owns its fallback. Headers contain `if` plus a suffix group holding the condition and `then`; named and pattern conditions retain their existing header structure. Attached `do`/`by` bodies join the header suffix and leave the branch peer empty, and final `else` suffix attachment is unchanged. Parser-packed `do` continuations are nested into the same ownership shape. `LayoutTree` flattens only links without source-forced comment breaks into alternating header/body peers; it prepends `else` to the following header in that view only. Single conditionals outside chains retain their existing raw rules. |
| `.proofBody containsTacticLayoutOwner` | Tactic syntax after `by` or `decreasing_by` is normally one protected proof-layout region, including ordinary term proofs, binder default tactics, and termination proofs. The Boolean records whether the body contains a tactic shell that must establish structural indentation. An owning shell's nested tactic sequence receives a separate proof-body wrapper that carries any deeper ownership inward, so nested headers and alternatives can be corrected while leaf proof scripts remain protected. A detached `.parserOwnedBody` also establishes ownership; the same suffix written inline does not broaden a compact proof island. When one owner makes the surrounding proof structural, a non-owning tactic infix chain remains a nested authored-layout island instead of being reformatted as a side effect. Transparent single-content wrappers and a `.suffixGroup` beginning with a proof body retain proof-envelope identity, so an enclosing alternative still owns the structural break after `=>` when a nested trailing proof has been extracted. A source-detached assignment introducer is exposed when the complete boundary between `:=` and `by` contains a line break, regardless of which token owns that trivia. A following tactic that starts on the next line does not detach an already attached `:= by`. | The tactic-sequence children after the separate introducer token. For `binderTactic`, the preceding `:=` also remains a separate sibling. Nested wrappers contain the tactic sequence owned by the surrounding tactic shell. |
| `.tactic kind containsSequence isOwner containsOwner isSpacedApplication`, `.tacticEliminationTargets containsNamed`, `.tacticEliminationHeader targetIsNamed`, and `.tacticIdentifierClause` | Structural proof formatting asks the same tactic-ownership questions many times while probing layouts. Recording those parser-tree facts once prevents repeated descendant scans while preserving the raw tactic kind for rule dispatch and diagnostics. Core tactic kinds can establish that role intrinsically. Parser-described term-taking tactics additionally record that they are spaced applications and use ordinary application layout without losing their tactic identity. Their prefix descends through application and infix owners to the first structural head; another term owner joins the prefix in a suffix group. The operand's own rule therefore controls every available internal break without a renderer-level tactic-prefix exception. Extension syntax becomes a tactic only from its parser context as a tactic-sequence entry, so a similarly named term or command is not protected by namespace convention. That context is propagated through empty parser wrappers and tactic-combinator operand positions before generic spaced-application regrouping. When regrouping has already made a tactic combinator an infix chain, contextual annotation visits only its operand positions. A `cases` or `induction` owner sees one header child and its alternatives, so alternative boundaries are mandatory without forcing optional breaks inside the header. A direct target collection reuses discriminant flow, including the lower-priority break before a named target's `:`. An induction identifier clause similarly groups `generalizing` with its first name and exposes every later name as a flat peer flow. | The regrouped children of a core tactic or a contextually identified extension tactic. The first operand retains its structural owner with the tactic prefix nested in its leftmost head, or contains both in an enclosing suffix group; remaining tactic arguments stay direct peers. Infix boundaries such as `<|` therefore remain owned by their infix rule. Other children are unchanged except for nested proof-body wrappers introduced at owned tactic-sequence boundaries. An elimination header contains its keyword, target, optional identifier clauses, and attached `with` suffix. An optional default tactic receives a direct proof-body wrapper, while explicit alternatives remain a sibling of the header. When Lean's raw tree places a same-indented tactic-sequence continuation inside a preceding non-owner tactic, regrouping returns that continuation to the surrounding sequence; a deeper continuation remains owned by the preceding tactic. Ordinary parser wrappers may be divided before a complete direct final proof argument, including one enclosed by a local declaration. Terminal suffix and low-priority infix envelopes may expose a simple final proof body through that same path. Parentheses and projection suffixes preserve source order as structural prefix, body, and suffix children, allowing the proof body to use the tactic base while closers remain attached afterward. A suffix group with a direct proof body flows the structural owner before deciding whether the body fits on its final line; the existing prefix policy keeps a fitting first tactic attached, while an available boundary breaks an overflowing body after its introducer. Multiple-tactic bodies still require that boundary. A suffix group whose shell is an enclosing proof body inherits the surrounding structural base; a non-proof shell containing the spaced tactic that owns an extracted proof keeps that tactic-local base. Sequence-shell metadata survives extraction, and directly attached sequence wrappers remain intact. Proofs containing tactic layout owners stay atomic; other delimiters, nested term owners, tactic shells, and non-suffix token-bearing siblings stop the traversal. The proof introducer remains in the structural shell that owns the body. |
| `.derivingClause` | Long deriving-class lists need peer flow boundaries rather than an opaque optional wrapper. | The `deriving` keyword followed by deriving classes and commas as direct children. |
| `.unifConstraints` | Pre-goal `unif_hint` constraints use line breaks as syntax separators and must never be flattened into horizontal whitespace. | The constraint elements between `where` and `⊢` as direct children. |
| Termination suffixes | `termination_by` is an ordinary formatted measure while only the tactic after `decreasing_by` needs proof-layout protection. Both clauses align with the base of their owning declaration. | Optional wrappers under the raw `Termination.suffix` node are removed. A parameter lambda under `terminationBy` exposes its parameter flow before the measure. The outer rule offers only the break after `=>`, so that break is attempted before the nested parameter flow; the nested flow keeps the first parameter after the keyword and indents continuation parameters two levels. `decreasingBy` retains its keyword as one child and wraps only its tactic sequence in `.proofBody`. |
| Lake DSL commands | Lake package and library commands need their `where` configuration body to share the command base, while Git dependency clauses need one rule to own the complete `from git` header and revision suffix. | Optional configuration wrappers are replaced by their `where` and field children. Dependency-name, source, and Git wrappers are spliced into the raw `requireDecl` node in source order. |
| Multi-item delimited collections | Brace terms, arrays, lists, tuples, anonymous constructors, and matrices need one balanced rule to own opening, item, and closing breaks. A generated term with parser printing breaks can prove the same ownership from a matching outer delimiter plus a direct comma or semicolon. | Parser sequence wrappers are spliced only when they contain an actual comma or matrix-row semicolon, so delimiters, items, and separators become direct children of the collection node. A parser-described generated collection receives `.delimitedCollection`; an otherwise transparent singleton `choice` wrapper is removed only around that proven collection. Unseparated custom-syntax fragments and singleton wrappers remain intact to preserve the established base for one multiline item. |

Conditional ownership is retained until layout preparation:

```text
Chain[Header(if, Suffix(condition, then)), body, else, Chain[...]]
```

A `do if` with only a final `else` uses the same owner with its fallback in place
of the nested chain. Both branch bodies are direct peers, so one balanced rule
handles authored or width-driven breaks. A `do if` without `else` retains its raw
rule, which also accepts authored breaks without making them mandatory.

`Formatter.LayoutTree.prepare` checks the source boundary between `else` and the
next `if`. It flattens an uninterrupted run into alternating header/body peers,
prepending `else` to each continuation header:

```text
Chain[Header(if, Suffix(condition, then)), body,
      Header(else, if, Suffix(condition, then)), body, else, fallback]
```

A line comment or a block comment containing a newline terminates that run.
The existing balanced rule then renders the final `else` with a complete nested
conditional body; ordinary child scopes establish its deeper base. The lossless
tree is unchanged, and the rendering view preserves every token in order. Normal
and traced rendering prepare the same view before computing layout facts. No
comments or break nodes, shared balance-state API, or syntax-specific renderer
logic are needed.

Preparation accumulates each run before visiting its children, without repeatedly
preparing the remaining tail. Unchanged subtrees remain shared rather than being
copied; only changed owners and their ancestor paths are rebuilt. The
[conditional style](design.md#conditionals) defines the boundary contract.

Single-line block comments may instead force a split only after parent placement
and width checks. Preparation marks these joins by the source start of the right
token, without predicting columns. The renderer records a broken join when the
emitted whitespace before that token contains a newline. Feedback belongs to
immutable output state: accepted fit probes commit it, and rejected probes discard
it. The renderer does not inspect conditional syntax or comment contents for this
decision.

Preparation also records the original guarded owners at paths in the prepared
view. These sparse retry descriptors are attached to cached layout facts, not
syntax nodes. Each descriptor retains the disabled joins used to prepare it.
An alternative must retain its owner's token range and external layout role;
only internal grouping changes, so the parent's incoming context remains valid.
Plain chains need no retry descriptor.

Preparation caches physical comment facts at visited continuation boundaries,
keyed by both UTF-8 source endpoints. The prepared view, its retry descriptors,
and layout-fact construction share this immutable, module-local cache. It stores
no width, placement, indentation, or fit decisions and is never reused for a
different source. Boundaries outside the cache retain direct classification.

Physical edge queries scan only leading or trailing horizontal whitespace and
the one or two newline delimiters needed by the query. First-line width and
last-line extraction likewise inspect the relevant string slice, without building
character lists for unrelated comment text. Widths remain Unicode character
counts; byte lengths only detect whether the first-line slice consumed the input.
CRLF and CR normalization and the definition of horizontal whitespace are unchanged.
Comment-forced-break queries scan ASCII delimiter bytes directly, tracking nested
block depth and stopping at a line comment or a newline inside a block. They do
not normalize, decode, or reconstruct comment text. CR and LF both force a break
inside a block; line endings outside comments do not. ASCII delimiter bytes cannot
occur inside a multibyte UTF-8 character.

Trivia cleanup and inline-comment emission use the same delimiter property to
retain complete comment slices rather than decode, reverse, and reconstruct their
characters. One scan locates whitespace and comment runs; nested block depth and
line-comment termination determine the slice endpoints. Only whitespace outside
comments is normalized, after the existing CRLF/CR normalization. This changes
allocation cost, not comment ownership, fit decisions, or retry feedback.

After an owner's first failed attempt, retries also share a bounded cache of
canonical source-layout facts. It is built from that owner's prepared tree before
retry descriptors or proof-island policy overrides are attached. Source endpoint
pairs select candidate entries; complete tree equality verifies the kind, grouping,
tokens, and trivia before reuse. Same-span wrappers are distinct candidates.
Newly grouped nodes compute fresh summaries, and each prepared view attaches fresh
retry descriptors. The cache never stores output, placement, fit results, or
alternative emission policies, and retries do not add entries. Nested retries
inherit it; returning from the owner restores the enclosing cache. Owners whose
first attempt succeeds do not allocate this cache.

An unchanged token prefix is not a sufficient key for rendered-piece reuse.
Contextual rules can inspect the entire enclosing segment, and regrouping changes
that segment even before the first changed token. A future reuse contract must
resolve those dependencies as well as incoming indentation and whitespace,
trailing fit context, feedback, and tracing. The source-facts cache does not grant
that contract.

When a complete owner reports a newly split join, rendering retries that owner
from its unchanged incoming state and original tree, with the join disabled.
The accepted prefix, enclosing layout context, and other owners are not replayed.
Nested owners can settle their own joins before their parent commits output.
Partial segments cannot retry an owner: their sibling indexes describe only the
existing view. Flat probes that bypass owner rendering still report feedback to
the bounded module-level fallback. Earlier feedback survives local retries, but
feedback and trace from rejected owner candidates do not leak into accepted output.

The first owner attempt finishes to collect simultaneous join failures. When
retrying with disabled joins, a balanced attempt may stop after its first newly
broken join, since its remaining output would be discarded. This early exit
returns directly to the owner retry boundary. Child rendering, flow alternatives,
and fit probes remain complete before any width comparison; an incomplete attempt
cannot be selected as a fitting candidate. This avoids rendering a doomed tail
without caching or resuming partially accepted render state.

Disabled joins accumulate in each retry lineage, so every retry removes at least
one active join. Later joins are reconsidered at their actual deeper base; fitting
ones remain joined. Parsing and import state are reused, not reconstructed. Normal
and traced rendering share this path. Protected-island alternatives still choose
emission policy on a fixed tree; they are not tree-ownership alternatives. Local
retries reduce repeated work, but overlapping continuation tails can still be
rendered repeatedly; this is not a linear-time guarantee.

A parser extension whose leading atom ends in `(` and whose final atom is the
matching `)` uses the same structural parenthesis rule as core syntax. The body
retains its own application breaks, and the closing delimiter uses the balanced
rule's closing boundary. No extension-kind exception is needed.

A parser-owned header groups a single-token modifier with a following delimited
argument. The delimiter then owns the collection's internal flow without allowing the
modifier to detach. Complete non-term-taking tactic entries with a delimited
argument use that same grouping, with or without a trailing location clause;
internal parser helpers and delimiter-owned nodes retain their own grouping.
Bracketed tactic-argument collections are structural delimiters rather than
separate protected tactics; an enclosing protected proof or tactic still retains
its authored layout.
Grouped headers omit tokenless parser wrappers while retaining every token,
including empty-lexeme tokens. This keeps absent optional clauses from creating
an empty leading flow segment. Their enclosing
tactic keeps its source-island classification; recovery uses the existing header
and collection rules. A wrapper containing only a header is not itself a
header-and-body recovery owner, so an already-overlong collection stays protected.
Header normalization includes intervening atom modifiers and Lean's configuration
parser before a bracketed header argument, not just one optional modifier. Term
arguments and trailing clauses remain outside that attached prefix. Conversion
sequences carry the same tactic-entry
context as ordinary tactic sequences. Matrix row classification examines only
collection separators through parser sequence wrappers; semicolons inside an
item's nested proof do not change the surrounding collection rule.
A single-token tactic prefix is carried through transparent,
single-content tactic-sequence wrappers only when the descendant contains a structural
tactic layout owner. The prefix then joins that owner's first structural head; unrelated
proof islands retain their established suffix grouping. The tactic bullet `·` remains
a sequence boundary and is never carried into the following owner.

Tactic-sequence nodes are hard proof-extraction boundaries. Regrouping may enter
an owned tactic to expose its final proof, but it cannot absorb sibling tactics
or a following command into that proof. When a suffix group contains an
unparenthesized proof with multiple tactic entries, its rule mandates the body
boundary after the retained `by` introducer so Lean's layout scope is preserved.

Declaration prefix attachment recognizes an empty `.declarationHeader` as an owner,
not absent content. Thus an anonymous `have :=` keeps its keyword and assignment
together when its value is recovered structurally. Declaration wrappers, including
`sufficesDecl`, inherit the surrounding declaration base for their continuations.
Optional `try` continuations contribute breakpoints only when they contain tokens, so an
absent `finally` cannot leave a pending break before an enclosing suffix.

Parser-owned lambda, macro, named-argument, and `suffices` categories may hide a
leading `do` or `by` inside their body wrapper. Regrouping splits that introducer,
attaches it to the preceding separator with `.suffixGroup`, and exposes the remaining
proof or do sequence as the body. A default-rule node with that structural pair inherits
its enclosing base, so protected proof emission rebases without losing internal layout.
Direct loop `do` tokens already have parser ownership and remain ordinary children.
Catch alternatives whose attached introducer is hidden under a term wrapper expose the
same header/body pair before rules run.

Lean's `macroTail` wrapper contains both the type portion of a macro signature and
its expansion body. Regrouping removes that wrapper so the macro command owns the
possible type boundary and the boundary after `=>` directly. The parser's sequence
of `macroArg` children becomes a `.macroPattern` flow, exposing peer boundaries when
a long pattern needs to wrap. The macro rule can therefore keep a fitting signature
flat while moving a multiline body one level inside the command; an attached `do`
or `by` remains in the suffix group produced by the parser-owned-body pass.

Regrouping deliberately avoids semantic interpretation. Infix peers are flattened
only when Lean's evaluated trailing parser descriptions report identical result and
left binding powers; the formatter does not classify operator text or reproduce a
precedence table.

Core `variable`, `include`, and `omit` commands splice their parser-owned binder
container into direct command children. Their existing command rule then exposes each
binder boundary at one shared continuation base, whether the binders are identifiers or
structured terms.

Some other registered Core parsers store a word-like head and two or more simple,
source-separated operands in one final anonymous container. After dedicated term,
tactic, declaration, generated-syntax, and delimiter regrouping has had priority,
`SyntaxTree` splices that atomic peer tail into the original raw node. Its existing rule
then exposes every peer boundary at one continuation base. This covers headed lists such
as universe levels, level `max` operands, and `match_expr` constructor arguments without
adding syntax-kind dispatch or changing the renderer. Structured binder lists and nested
owners such as `openSimple` do not satisfy the shape.

The `letExpression` annotation is a syntactic parser fact rather than semantic
interpretation. For each concrete body, `SyntaxTree` runs `termParser argPrec` against
the body's source text in the command's current parser context. A successful prefix parse
means the body could continue the binding's right-hand-side application, so the rule
requires start alignment. A failed probe means the leading syntax itself separates the
body, so visual alignment is only preferred. The probe runs once while parsing the
command; rendering consumes the stored Boolean and never reparses the body. If the
incremental command parser falls back to Lean's full frontend or a source span is
unavailable, the missing fact defaults conservatively to required alignment.

The same parser-context pass records one `ParserLayout.KindFacts` value for every
concrete syntax kind in the module. A profile contains formatter availability, printing
annotations, trailing-parser binding powers, the exact single-operand descriptor shape
used by command-like spaced applications, trailing keyword/body suffixes with final term
or tactic-sequence bodies, and optional keyword clauses with repeated spaced arguments.
Ordinary and conversion tactic sequences are recognized both as named parser
references and as inline nodes, including nodes with antiquotation support.
An arrow before a recognized sequence supplies the same trailing-body ownership
boundary as a keyword suffix; optional header clauses do not hide it. Arrow
clauses retain the structural sequence policy for source-detached bodies, while
keyword clauses keep their existing fitting-body attachment policy.
A complete tactic entry whose top-level infix structure ends in `=> body` supplies the
corresponding ownership directly from its parser context, including when `body` belongs
to another parser category. Descriptor evaluation is cached per kind for the module.
Regrouping verifies that a recorded suffix is present in the concrete tree before
creating `.parserOwnedBody`. Line-break rules and the renderer never query the
environment or parser metadata.

Dedicated Core, Std, and Mathlib regroupings and rules remain leanfmt's explicit style
contract. For a syntax kind without one, parser-owned printing annotations are the first
generic structural signal. Immediate token-tree shape can then select an existing
application, prefix, postfix, indexed, delimited, or recursive-sequence owner. If neither
source proves a shape, the raw node keeps `defaultRule` and a missing-rule diagnostic.
This ordering provides intelligent extension handling without adding one rule per
downstream syntax name.

An arbitrary registered `@[formatter]` is not itself a safe layout plan. Lean exposes it
as executable `CoreM` code that produces a `Std.Format`; that document can normalize
token spelling, insert syntax, and has no source-token-indexed boundaries. `ParserLayout`
records the registration and still uses an available `ParserDescr`, but it does not
delegate output to the registered formatter.

`RegisteredFormatAudit` executes that code only as a development-time oracle. It walks
the symbolic `Std.Format` before width-dependent rendering, aligns every text fragment
with the original token stream, and records `.line`, `.nest`, `.group`, and source-tag
structure at token boundaries. It rejects comments, rewritten or inserted tokens,
multiline tokens, unsupported whitespace or indentation, incomplete spans, and
column-sensitive `.align` nodes.

The audit then normalizes transparent `null` wrappers and recursive same-kind parser
spines into logical children. Breaks that coincide with those child boundaries become a
candidate application, prefix, postfix, infix, delimiter, suffix-body, sequence, or
generic structural rule. A candidate is stable only when multiple samples produce the
same structural key, family, child breaks, indentation, and grouping policy. These are
reviewable deductions, not generated production dispatch: production parsing,
regrouping, rules, and rendering neither import nor consult them.

The development-only `tools/rule-audit` package samples source files and compares stable
candidates with current rules. It collects production boundaries from regrouped nodes
inside the audited source span, then keeps only boundaries at normalized immediate-child
starts. Leading boundaries and nested breaks inside one child are outside that
comparison. Differences remain review evidence because registered formatters do not
define leanfmt's style.

### Recognized raw nodes

Most syntax remains `.raw kind`. Rules can still recognize raw kinds when the raw parser
shape is stable enough. Examples include:

- module/header/import commands,
- source-adjacent extension index notation with a direct receiver and balanced
  `[` index `]` children, which reuses the indexed-term rule,
- declarations, structures, inductives, theorems, mutual blocks, and `where` suffixes,
- binders and declaration signatures,
- `let`, `if`, `match`, `do`, lambdas, quantifiers, and subtypes,
- structure instances, arrays, tuples, and parser `null` wrappers under known parents,
- proof escape hatches such as `Lean.Parser.Term.byTactic` and
  `Lean.Parser.Term.binderTactic`.

Binder-name lists are exposed as flow opportunities by rules on their lossless
wrapper segments. Explicit and implicit binders can therefore wrap names before
their type annotation, while untyped quantifier binders can wrap before the
comma. The renderer receives ordinary break points; it does not need to know
which parser wrappers represent binder lists. The enclosing binder rule owns a
separate break before `:`; the name-list flow does not reserve the type as a
same-line suffix.

The quantifier rule separately exposes boundaries between complete binder
groups. Those are zero-level breaks from the quantifier's binder base, so a
continued group aligns with the first binder, rounded to the indentation grid
when the operator starts off-column. It does not gain an extra continuation
level. Flow within one untyped binder-name group retains its own ordinary
continuation indentation.

Binder-body ownership is resolved against the complete parent tree, including
when layout operates on a slice after the comma. A trailing measure clause is
not reclassified as a new body when the comma lies outside that slice. The body
and its suffixes use ordinary flow, so a fitting suffix can follow a multiline
body while a long suffix can still move. For a source-tight generated marker
before an application, grouping attaches the marker to the application head,
not to the complete application. Thus `∂.pi` remains one head and its arguments
retain ordinary application boundaries.

Required proof-body boundaries share one structural multiple-tactic check for
attached introducers and tactic alternatives. The enclosing rule owns the break;
the protected body retains its relative layout. Record separator detection
likewise accepts a comma owned by the preceding field-list wrapper as well as a
direct sibling comma, without introducing a separate ellipsis layout policy.

Open-command identifier lists use the same peer flow in both `open A B C` and
parenthesized `open A (x y z)` forms. Their parser wrappers differ, but the list
rule owns the same break between complete identifiers in either shape.

The full dispatch table lives in `LineBreakRules.ruleFor`. If a raw node is not
recognized, `ruleFor` returns `none`, the renderer uses `defaultRule`, and
`--check-missing-rules` reports the missing rule. For raw parser kinds, the report also
classifies the same `ParserLayout` metadata source used during regrouping: an explicit
formatter registration, a generated `ParserDescr` fallback, or neither.
The missing-rule report intentionally filters unstable implementation-detail kinds such as
tokens, generated private names, custom term-notation names, and `stx` helper nodes.

Named dispatch falls through one `structuralRawRule?` boundary. That boundary preserves
the established precedence between transparent single-child wrappers, generated indexed,
set-builder, prefix, postfix, and recursive shapes, ordinary outer delimiters, and the
remaining recursive or binder heuristics. This makes structurally supported syntax
auditable without duplicating project kind names in the dispatch table. Generated
collection spellings remain explicit where the same bracket shape is shared by literals,
tactic arguments, and configuration syntax; delimiters alone do not prove collection
ownership there.

## Space rules

`SpaceRules` is the low-level token/trivia transformer. It answers what horizontal
whitespace belongs between adjacent code tokens and performs the mechanical cleanup or
reindentation requested for a source-trivia slice.

Its main entry point is:

```lean
def interTokenWhitespace
    (source : String) (left right : SyntaxTree.Token) (preserveLines : Bool := true)
    (normalizeAdjacent : Unit → Bool := fun _ => false) :
    String
```

Important behavior:

- Normalize line endings.
- Remove trailing whitespace before newlines.
- Collapse excessive blank-line runs.
- Preserve and reindent comment trivia.
- Keep tight punctuation such as `(`, `)`, `[`, `]`, commas, semicolons, projection dots,
  fully qualified name-quotation prefixes, and compact `!value` when source adjacency
  requires it.
- Insert a single space between ordinary adjacent code tokens.

The context-dependent adjacent-token query is deferred until the source trivia is
empty. Comment handling, preserved source breaks, and ordinary spaced tokens do
not inspect the enclosing structural context for that unused decision. Pending
indentation takes its normal boundary path without constructing the query.

Space rules do not inspect `SyntaxTree.Tree`, render state, or ancestors. Regrouping
classifies the direct boundaries of ordinary infix chains and type ascriptions where empty
source trivia should still receive canonical token spacing; the renderer passes only that
boolean fact to `interTokenWhitespace`. Semantic facts about source trivia belong to
`SourceBoundary`; it determines whether trivia contains comments, forces a physical break,
begins or ends at a blank group, and exposes source indentation evidence. Comments and
source breaks remain outside the syntax tree.

## Resolved layout plans

`LineBreakRule` is the rule-authoring representation. `LayoutPlan.resolve` evaluates its
context-dependent predicates exactly once for one segment, normalizes lexical break
boundaries, and returns a renderer-facing `LayoutPlan.Plan`.

The resolved plan uses closed policy types instead of independent renderer callbacks:

```lean
inductive Mode where
  | atomic | mandatory | balanced | flow

inductive BasePolicy where
  | local | inherited | rounded | inheritedRounded

structure ChildBoundaryPlan where
  index : Nat
  prefixPolicy : PrefixPolicy
  originalLeading : LeadingBoundaryPolicy

structure Plan where
  name : String
  mode : Mode
  sourceBreaks : SourceBreakPolicy
  base : BasePolicy
  tail : TailPolicy
  startAlignment : StartAlignment
  breakPoints : List BreakPoint
  children : List ChildBoundaryPlan
```

Breakpoint normalization also lives here. Tight postfix boundaries and trailing
separators are syntax/token planning facts; the renderer receives only legal normalized
breakpoints and does not inspect their spelling.

## Line-break rules

Line-break rules are syntax-facing. A rule receives a `RuleContext` and a `Segment`.
It returns pure judgements about the current tree segment.

```lean
structure Segment where
  parent : SyntaxTree.Tree
  start : Nat
  stop : Nat

structure RuleContext where
  ancestors : List Frame := []

structure BreakPoint where
  index : Nat
  indentLevels : Nat := 0

inductive StartAlignment where
  | none
  | preferred
  | required

structure LineBreakRule where
  name : String
  atomic : Bool := false
  formatOriginalChildLeadingBoundary
    : RuleContext -> Segment -> Nat -> Bool := fun _ _ _ => false
  keepPrefixWithChildFirstLine
    : RuleContext -> Segment -> Nat -> Bool := fun _ _ _ => false
  useExistingBreaks : RuleContext -> Segment -> Bool := fun _ _ => false
  mandatory : RuleContext -> Segment -> Bool := fun _ _ => false
  flow : RuleContext -> Segment -> Bool := fun _ _ => false
  inheritBase : RuleContext -> Segment -> Bool := defaultInheritBase
  liftsTailIndentation : RuleContext -> Segment -> Bool := fun _ _ => false
  startAlignment : RuleContext -> Segment -> StartAlignment := fun _ _ => .none
  roundUpBaseIndentation : Bool := false
  breakPoints : RuleContext -> Segment -> List BreakPoint := fun _ _ => []
```

A `BreakPoint` index means "break before child at this index." `indentLevels` is a
logical two-space continuation count. It is not an absolute column and not a token
anchor. Every returned point is an ordinary layout opportunity or a structural break
when its rule is mandatory. Break points carry no source-, token-, or comment-dependent
activation predicate.

Command sequences are the one vertical-spacing specialization. `LineBreakRules`
classifies module, header, import, top-level command, and mutual-command sequences and
catalogs command nodes as module keywords, public or ordinary imports, module docstrings,
declarations, or other commands. This exposes syntax facts without encoding vertical
spacing in every `BreakPoint`. Macro commands are declaration peers for this purpose;
annotation wrappers forward the classification of the command they contain.

When the renderer processes one of those sequences, it renders each command once and
records whether the result is multiline. Boundaries known from syntax or the previous
command are applied before rendering. If the current command newly requires a blank
boundary, the renderer upgrades only its already-emitted leading whitespace. Import
groups use fixed grouping, module docstrings are separated from following commands, and
adjacent declarations receive a blank line when either renders multiline. Leading
comments and docstrings remain attached to their command. Other syntax sequences retain
the ordinary source-preserving boundary behavior.

`ruleFor : SyntaxTree.Tree -> Option LineBreakRule` is the dispatch table. It has no
ordered candidate list. A known node maps to exactly one rule. Unknown raw nodes return
`none`; `formattingRuleFor` maps that to `defaultRule` for rendering.

The final raw-node arm delegates to `structuralRawRule?`. This helper is an ordered
structural classification, not another syntax-rule registry: parser-derived application
and body owners have already become logical nodes, while immediate delimiter, generated
prefix/index, recursive sequence, and binder shapes select their existing general rules.

The rule module is organized by broad syntax families. Each family keeps its breakpoint
computations and `LineBreakRule` values together; generic wrapper rules and the complete
dispatch table remain at the end.

Rule-authoring methods compile into these plan properties:

- `useExistingBreaks`: source breaks at this rule's break points are tried before flat
  layout and can override fitting flat output. For a non-flow rule, one accepted source
  break activates the rule's complete break-point set; partial source layouts are not
  rendered. If that structural layout moves a multiline original-layout child and the
  moved child overflows, the renderer keeps the rule layout instead of accepting a flat
  probe that cannot remove the child's physical source break.
- `atomic`: the segment is always rendered flat internally. Its parent still measures
  its complete width and may break before it. Interpolated strings use this so `s!` and
  interpolation contents cannot split independently.
- `formatOriginalChildLeadingBoundary`: the parent rule owns the whitespace before the
  selected original-layout child. The renderer applies ordinary token spacing at that
  boundary and rebases the island's internal source layout to its formatted start
  column. Transparent wrappers use this for later children, so a source newline inside
  a type specification cannot detach its term from the preceding `:`.
- `keepPrefixWithChildFirstLine`: at a selected child boundary, when the child can format
  its first line beside the already-rendered prefix, delegate wrapping to that child
  rather than taking the boundary immediately before it. Such a rule requires a
  genuinely single-line flat probe and does not reactivate the boundary merely because
  it existed in the source. Protected source emission uses the same first-line fit
  probe: a movable first line rejoins the prefix, while a genuinely nonfitting first
  line keeps its structural post-prefix boundary. A comment at that boundary still activates the break, so
  its continuation indentation is structural. Refutable `let` fallback clauses use
  this to keep `|` with the fallback's first term; annotated declarations use it only
  between a modifier container and its extensible command. Named arguments use the
  same contract at their closing-delimiter boundary: `)` remains a tight suffix when
  it fits, while a forced comment activates the existing base-aligned closing
  breakpoint. Flowing parser-owned collections use that contract for their closing
  delimiter too, so item fit probes reserve its width. When no rule breakpoint exists,
  an unbreakable original first line also
  remains with its prefix if the fallback child break cannot make that line fit; this
  avoids a no-benefit break and a possible convergence cycle. Real rule breakpoints can
  still expose structural wrapping inside the child. If a tight leaf suffix does not fit
  and the flow has earlier structural breaks, the renderer applies those earlier breaks
  instead of detaching the suffix.
- `mandatory`: returned breaks are structural and are applied without a flat attempt.
- `flow`: returned breaks are candidates; flat layout is tried first, then accepted
  source breaks, then computed wrapping. If the accepted source layout still overflows,
  computed wrapping adds breaks without dropping its accepted source boundaries.
  Structure headers use flow so fitting headers stay flat and overflowing headers break
  before `extends`.
- `inheritBase`: this segment uses the surrounding base indentation instead of its
  rendered start column.
- `liftsTailIndentation`: while rendering every child except the final child, establish
  the indentation of the following rule boundary as that child's tail indentation.
  Infix-like and flow rules lift continuations one level beyond that tail. Rules never
  encode prefix widths or variable depth contributions. Tail lifting does not replace
  a base explicitly inherited from the surrounding syntax.
- `startAlignment`: rules classify start alignment as absent, preferred for visual
  stability, or required by layout-sensitive parsing. The renderer decides whether
  padding is needed after measuring the nested layout. It may suppress preferred
  alignment immediately after `(`, as for conditionals and syntactically unambiguous
  `let` bodies. Required alignment remains active when Lean's parser reports that a
  layout-delimited body can start an application argument. Explicit
  semicolon-delimited lets use preferred alignment because their body boundary does not
  depend on layout.
- `roundUpBaseIndentation`: positive structural breaks start from the indentation boundary
  after the segment's physical start. Conditionals, delimited structures, tuples, arrays,
  and binding right-hand sides use this so contents remain one full level past an
  off-column head.
- `breakPoints`: logical child boundaries. Rules must not read renderer state or output
  columns. Syntax regrouping introduces a logical child when the raw parser shape does
  not expose the boundary a rule needs. Rules may declare that their candidate boundaries
  preserve authored breaks; `SourceBoundary` evaluates those physical boundaries outside
  rule callbacks and the renderer applies the resolved policy generically.

The default rule is deliberately shape-only. It distinguishes missing children, empty
leaves, nonempty leaves, empty nodes, and nonempty nodes. A nonempty leaf between two
nonempty node children is treated as an infix-like break point; otherwise boundaries
between present children are flow break points. It does not inspect token kind, token
role, or token text.

When a known grammar's immediate child shape does not describe its legal layout,
syntax regrouping exposes the semantic boundary or `ruleFor` selects a separate
syntax rule instead of weakening this invariant. For example, a notation whose
opening delimiter is part of one composite atom can be transparent so its enclosed
term owns the wrapping, while an indexed infix group offers one leading break before
its complete operator. Neither the default rule nor the renderer infers the layout
from token spelling.

## Renderer

The renderer owns physical layout. It is the only layer that emits text, measures line
width, tracks current output, and computes indentation.

Core state is:

```lean
structure RenderState where
  source : String
  sourceMap : SyntaxTree.SourcePositionMap
  output : String := ""
  currentLine : String := ""
  lastToken? : Option SyntaxTree.Token := none
  pendingIndent? : Option Nat := none
  segmentBaseColumn : Nat := 0
  segmentIndentation : Nat := 0
  layoutAnchor : Rebase.Anchor := {}
  tailIndentation? : Option Nat := none
  tailIndentationStop? : Option Nat := none
  tailIndentationAnchors : List TailIndentationAnchor := []
  breakIndentationShift : Nat := 0
  lineFitSuffixWidth : Nat := 0
  context : LineBreakRules.RuleContext := {}
  trace : Trace.State := {}
```

Key fields:

- `sourceMap` is built once per rendering pass and answers source line/column queries.
- `currentLine` avoids repeatedly scanning `output` for the current line.
- `lastToken?` lets the renderer ask space rules for inter-token whitespace.
- `pendingIndent?` records a scheduled newline before the next emitted token.
- The pending whitespace state can mark a comment-created tree boundary. This lets
  the renderer move the leading comment beside the preceding token when that line
  fits while retaining the boundary indentation for the token after the comment.
- `segmentBaseColumn` and `segmentIndentation` are the current segment's physical and
  logical bases.
- `layoutAnchor` keeps the nearest enclosing source-line base and its rendered output
  column as one value. Protected source regions move every source column through that
  anchor, so the two sides cannot be updated independently.
- `tailIndentation?` is the indentation floor inherited by continuation lines in the
  current segment. It is a single absolute indentation, not an infix depth counter.
  Child rendering restores the surrounding tail when it returns.
- `tailIndentationStop?` caches the complete segment's final child boundary. Balanced
  slices reuse that boundary instead of treating the slice's final child as the node's
  final child.
- `tailIndentationAnchors` caches each rule boundary's already-computed indentation. A
  non-final child uses the first boundary after it as the base for its contribution,
  falling back to the segment base when no boundary follows it.
- `breakIndentationShift` is the one upward translation shared by every breakpoint in
  the current segment. Computing it once preserves relative indentation and avoids
  recomputing the breakpoint profile during emission.
- `lineFitSuffixWidth` is trailing same-line width that a recursive child must leave
  room for.
- `context` is the rule ancestor stack. Flat rendering and fit probes push and restore it
  exactly like normal rendering, so structural boundary facts cannot differ by candidate.
- `trace` records optional debugging output.

`WhitespaceState` is the token-spacing subset of `RenderState`. Both real token
emission and suffix-width measurement use its single `defaultWhitespace` implementation.
The measurement path retains only this smaller state and the measured suffix width, so
it cannot drift into a second whitespace policy.

### Rendering algorithm

For each segment:

1. Resolve the segment's authoring rule into one `LayoutPlan.Plan`.
2. Record a trace entry if tracing is enabled.
3. Emit missing and leaf segments mechanically.
4. Ask `OriginalTree` to plan protected source-island emission and apply the returned
   text and token-state update.
5. If the plan is atomic, render all of its children flat as one measured unit.
6. If the plan is mandatory, apply all resolved breaks.
7. If the plan has no break behavior, render children in source order.
8. If the plan preserves source breaks, collect them only at resolved break points.
   For non-flow rules, any accepted source break applies all rule breaks. For flow rules,
   try the accepted source-break candidate once before flat layout. If it does not fit,
   retain that rejection and continue to flat layout and computed wrapping without
   reconstructing the rejected candidate. When a multiline original-layout child makes
   the source-break candidate overflow, skip the misleading flat probe and apply the
   rule layout because the child keeps its physical source break in either candidate.
9. Try flat rendering when allowed.
10. For rules that prefer child layouts, try the recursively rendered children when
    the rule-specific prefix remains flat and the complete child layout fits.
11. For flow plans that did not already try source layout through their source-break policy,
   try accepted source breaks after flat failure, then computed flow wrapping that
   retains those accepted source boundaries while adding any required breaks.
12. For non-flow plans with break points, apply all resolved breaks simultaneously.

Fit measurement is speculative. The renderer emits into an empty probe while retaining
the current line and pending boundary state, then records two facts from that one result:

- `flat` means the complete segment occupies one physical line.
- `fits` means the result stays within the configured width. It may reuse a multiline
  layout owned by an opaque or already-broken nested child without activating this
  segment's own break points.

A failing child probe may restore a protected child's source break at its owner's
existing positive-indentation breakpoint when that boundary keeps the child's
first line attached to its prefix.
The prefix must already have fitted without breaks; only the child is retried.
This admits a fitting assignment header with a broken attached proof body without
hoisting the proof out of its value or wrapping declaration parameters ahead of
the assignment. It cannot create a break inside an originally inline protected
span. The result is multiline, not flat, and zero-indentation peer
owners still reject that joined layout.

When a child retains its leading source boundary and no structural indentation is
pending, it and its transparent wrappers keep the enclosing layout anchor instead
of replacing it with a hypothetical inline token column.
Protected quotation emission rebases a retained leading source boundary before
computing its internal continuation anchors. The already-rebased leading column
is the input to later target-column adjustments, so the first line and multiline
contents move together without applying the shift twice.

An original-layout island can make a source newline physically unremovable even when its
parent rule does not generally preserve source breaks. If that island starts at a
configured breakpoint and the preceding prefix moved from its own source line, flat
measurement rejects the stale boundary. Ordinary rule layout then supplies the target
indentation before original-tree emission rebases the protected text. The renderer makes
this decision from boundary state; it does not inspect introducer spelling.

When a flow segment contains a multiline protected child, the complete segment is not
accepted as flat merely because the preserved lines fit. Computed flow then takes an
available boundary before that child, so a parenthesized multiline proof argument moves
below the application prefix. A directly attached body with no boundary before its
introducer remains attached. Zero-indentation flow boundaries apply the same invariant to
peer pieces, which is why a multiline command moves below its annotation without
classifying every multiline application as flat.

This separation keeps line-width and nested-layout decisions in the renderer. Rules
return only break opportunities and do not need access to either fact.

### Source breaks

The renderer discovers source breaks by looking between adjacent child tokens, but only
breaks accepted by the current rule can be used. Source indentation is ignored. Rules
for declarations, bindings, lambdas, and alternatives do not return break points before
`:=`, `←`, or `=>`; they return an RHS break after the separator instead. The renderer
does not inspect separator spelling. Accepted source breaks and computed rule breaks both
become `pendingIndent?`; later rendering does not distinguish their origin.
Rule-specific discovery queries the token boundary at each resolved break point directly,
without intersecting two complete lists. Missing children do not introduce boundaries.
The segment's leading boundary still uses the caller's last emitted token. Balanced
layouts stop at the first retained source break, since that selects all rule breaks;
only flow candidates calculate the individual retained-break indentations. Both paths
use the same eligibility predicate, including prefix attachment policy.

ASCII line-ending and comment-marker prechecks use Lean's byte-array search. ASCII
bytes cannot occur inside multibyte UTF-8 characters; this changes only the search
implementation, not character-width measurement or comment classification. Line-ending
helpers still distinguish raw LF checks from checks accepting either CR or LF.

Blank-line trivia at an accepted break point is a source break too: the renderer
retains one blank line while rebasing the following token to the rule-computed
indentation instead of preserving its old absolute column.
Blank trivia at any other nested boundary is removable and is not emitted ahead of the
owning rule. Final output is stripped of horizontal whitespace before newline normalization.

Before applying a rule break, the renderer normalizes boundaries that would
separate a trailing punctuation token from its preceding syntax. The break moves
to the next content child, after the separator. This lexical emission invariant
keeps the default shape rule generic: it does not inspect comma spelling or
duplicate token-spacing policy.

For flow rules, accepted source breaks remain selected if their layout needs additional
computed wrapping; the renderer adds fitting breaks instead of discarding the accepted
ones. For non-flow rules, accepted source breaks are activation signals for the complete
balanced rule layout. This is a renderer invariant, not an opt-in rule predicate.

### Rule consistency invariants

Rules and regroupings should preserve these cross-syntax relationships:

- Non-flow means balanced. A non-flow rule never renders only a source-selected subset
  of its returned break points. Flow rules may select the subset needed to fit.
- A child that is structurally multiline does not fit as a same-line parent operand or
  application argument. The parent breaks before it through ordinary fit/flow logic;
  rules do not accumulate exceptions that prefer a parent break. Annotated declarations
  use the same flow behavior: a multiline command moves below its attribute.
- `:=`, `←`, and `=>` terminate headers. Declaration, binding, lambda, and arm rules
  omit breaks before them and expose RHS breaks after them.
- Header suffixes such as instance `where` and match `with` behave like assignment
  separators: they remain with the header, while their following body owns the break.
- Elimination alternatives align with their tactic keyword, and their bodies use the
  same two-level indentation as match-alternative bodies. For `cases`, the alternatives
  break after the attached `with` suffix; an unlabeled default alternative uses the
  same body indentation before later labeled alternatives return to the tactic base.
  A named discriminant keeps its name attached to `cases` and may break before its `:`,
  aligned with that name's base indentation. `induction` uses the same header and body
  ownership; a long `generalizing` clause wraps between identifiers without stranding
  the induction target on a line by itself. For an unlabeled parenthesized default
  alternative, regrouping attaches only the opening delimiter to the existing `with`
  suffix; the delimited tactic sequence remains the body owner and the closing delimiter
  remains its tight suffix.
- `let ... :=` and `let ... ←` use equivalent header/RHS layout for both identifier
  and destructuring patterns. `def ... :=` and `| ... =>` follow the same separator
  principle with their construct-specific body indentation.
- Peer syntax is regrouped before rules when raw parser nesting would create accidental
  precedence. Same-kind infix operands and multiple match patterns are examples.
- Match discriminants are peer flow items with breaks after commas aligned under the
  first scrutinee. Match arm patterns are non-flow balanced peers: all pattern
  boundaries break together.
- Applications do not special-case `basicFun`, structure instances, `let`, or other
  argument kinds. Their formatted multiline shape is enough to make the application
  break before the argument.
- Fitting constructors are flat. When the enclosing declaration and constructor both
  need breaks, the declaration break after `:=` precedes constructor-internal breaks.
  Anonymous constructors then use balanced item breaks like tuples and arrays.
- Inductive and equation arms inherit the arm base while their binders/patterns use flow
  opportunities. This keeps `|` at the arm base and continuation binders below it.
  When constructor documentation precedes `|`, the inductive rule assigns one base to
  the complete constructor and the constructor rule keeps both the documentation and
  marker on that base.
- Transparent singleton wrappers around declaration identifiers inherit the declaration
  base. Structure-field wrappers likewise inherit the field base, and the wrapper that
  directly owns `structInstFieldEqns` owns the break before those equations. Rules do
  not infer either base from the wrapper's incidental rendered column.
- An inline semicolon suppresses the adjacent structural tactic- or do-sequence boundary
  when the joined sequence fits; width pressure returns the following statement to the
  owning sequence's peer base. A source-detached tactic after a trailing semicolon keeps
  that peer boundary because Lean's tactic parser uses it to delimit the preceding proof.
- Interpolated strings are atomic nodes: parents may break before the complete atom, but
  neither `s!` nor interpolation children break independently.
- Comments remain source text between the surrounding lexical tokens. Lean normally
  exposes them as token trivia, but it may leave a comment only in the physical source
  gap after an opening delimiter. Grouping and balancing must preserve that source-gap
  text and allow the containing rule to recompute indentation. A source-broken
  application argument that starts with a delimiter followed by a line comment retains
  its argument break so the delimiter and comment do not migrate onto the preceding
  application line.
- An intrinsically multiline comment makes its renderer tree boundary structural even
  when no syntax rule owns that exact source gap. This is independent of syntax kind:
  the renderer derives indentation from the surrounding tree, shifts multiline comment
  continuations by the difference between the comment opener's source and rendered
  columns, and separately applies the tree indentation to the token after the comment.
  A later comment aligned with that following token moves with the following tree;
  an authored continuation keeps that relation. A later line authored immediately one
  column left of the opener is treated as aligned and clamped to the rendered opener;
  a more distant line retains its distinct relative offset.
  A flow parent cannot flatten away this physical break.
- Line comments force the token after the comment onto a new line, but may remain
  attached to preceding code while that complete line fits. Block comments force a
  break only when their own text contains a newline. A one-line block comment may flow
  inline, with its internal text preserved and only surrounding horizontal trivia
  normalized; width pressure may still activate the enclosing tree's ordinary break
  or break between the comment and its following token. Syntax-specific rules do not
  inspect comment text or source spacing, and comments are not added to the syntax
  tree as layout nodes.

This separation lets rules say "this boundary may follow source layout" without letting
source indentation leak into renderer state.

### Indentation model

Indentation uses two concepts:

- physical column: where a segment starts on the rendered line,
- logical indentation level: `column / indentationSpaces`.

Breaks are computed by:

```lean
def breakIndent (baseColumn baseIndentation : Nat) (breakPoint : BreakPoint) : Nat :=
  if breakPoint.indentLevels == 0 then
    max (indentationPastColumn baseColumn) (baseIndentation * indentationSpaces)
  else
    (baseIndentation + breakPoint.indentLevels) * indentationSpaces
```

Zero-level breaks round the physical base column up to an indentation boundary while
respecting a larger logical base.
This keeps constructs such as match alternatives past a `match` that starts at an odd
column. Breaks with added levels use the floored logical base plus those levels. That is
more conservative for continuations such as application arguments.

For rules with `roundUpBaseIndentation`, positive breaks first round the physical start
to an indentation boundary. A local rounded flow whose prefix becomes multiline may
advance to that prefix's rendered indentation before applying its next break. An
inherited rounded flow retains the surrounding logical base, so a multiline alternative
header cannot shift its body farther inward.

Child segment bases are derived from renderer state, not from token spelling. If a child
rule says `inheritBase`, the surrounding segment base is reused. Otherwise the child base
comes from the column where its first visible token will be emitted.

Parser-described spaced tactic applications extend that inherited base through
transparent lambda and conditional wrappers. Their nested bodies therefore use the
application's logical base even when the wrapper begins after an inline tactic head.

### Tail indentation

Tail indentation generalizes the indentation needed for a multiline left operand of an
infix operator. A rule establishes a tail for its non-final children through
`liftsTailIndentation`. A child that inherits that tail then adjusts its own balanced,
infix-like, or flow layout. The same mechanism therefore covers applications, binders,
structure updates, and other syntax whose continuation must remain visibly inside a
following boundary.

The model has three terms:

- A segment's **start column** is the physical column of its first visible token.
- Its **head indentation** is
  `indentationLevelForColumn (indentationPastColumn startColumn)`. Rounding is inclusive:
  a start already on the indentation grid stays there; an off-column start moves to the
  next grid column.
- Its **tail indentation** is an absolute logical indentation floor for later lines if
  the segment renders across more than one line. It is not a depth count and is not added
  to a rule's requested indentation.

When a rule sets `liftsTailIndentation`, the renderer caches the complete segment's final
child boundary. Every earlier child inherits the indentation of the following rule
boundary as its tail indentation. Thus a `for` binder is anchored by `in`, an infix
operand by its following operator, and an off-column child by the already-rounded
boundary rather than by the width of its prefix.

If the same rule also sets `inheritBase`, that inherited base remains the segment's
structural base. Tail lifting constrains continuations but does not rebase the segment
onto the physical column of an inline opener.

For example, an inner operator is lifted beyond the operator that follows its containing
operand:

```lean
- f firstLongArgument
    nextArgument
  - g
:: h
```

Here `::` establishes the outer tail. The left child containing `- g` lifts beyond it,
and the application inside that child retains its own continuation indentation. The
result is a hierarchy of absolute floors, not a sum of operator widths or nesting depths.

At complete-segment entry, the renderer computes the natural indentation of every rule
breakpoint. The least natural indentation is the base of that breakpoint profile. It then
computes the required profile base:

```text
balanced segment:       inherited tail
infix-like/flow segment: max(rounded head, inherited tail + 1)
```

If the required base is higher than the natural base, their difference becomes one
`breakIndentationShift`. The renderer applies that translation to every breakpoint in
the segment. For a zero-level breakpoint, it shifts the final rounded natural
indentation; applying the shift before rounding could make a one-level shift disappear.

Translating the whole profile is essential for balanced syntax. A structure can assign
one natural level to fields and zero to its closing brace:

```lean
-> {
      field1 := value1,
      field2 := value2
    }
    :: rest
```

Shifting those breakpoints together preserves the one-level difference. Clamping each
breakpoint independently to the tail would incorrectly align the fields with the closing
brace.

`tailIndentationStop?` records the final-child boundary of the complete segment, even
while balanced rendering visits slices of that segment. `tailIndentationAnchors` records
the already-computed indentation of each following rule boundary. A non-final child takes
the first anchor after it, merges that floor with an inherited outer tail, and receives
the result in `tailIndentation?`. Nested child rendering is scoped, so this state does not
leak into later siblings.

Transparent parser wrappers inherit a structural base only from an owner that defines
that relation. Structure-field default values inherit the field base, so `binderDefault`
does not derive proof indentation from the physical column after `:=`; an attached `do`
or `by` introducer is first grouped with that assignment suffix. A function wrapper
used as the right operand of an indexed infix similarly inherits the indexed relation's
base. Ordinary function wrappers keep their established local base; making every `fun`
inherit its parent both changes unrelated lambda layout and expands layout search.

The renderer computes each child's rule and breakpoints once before recursive rendering
and passes that prepared pair into the child call. Layout decisions therefore reuse rule
facts without inferring semantic behavior from the presence or shape of breakpoints.

### Suffix width

Recursive formatting must account for same-line suffixes owned by parent segments. For
example, when rendering a declaration signature, the parent may later emit ` :=` before
breaking to the body. The signature must leave room for that suffix when deciding
whether its final line fits.

`lineFitSuffixWidth` stores that extra width. The renderer estimates suffix width by
walking following siblings until the next active break boundary and stops at tokens that
are not suffix-eligible. The suffix classifiers live with line-break rules; the renderer
only measures with those classifications and the same whitespace policy used by actual
emission. Tight optional-access `?` participates in that measurement, so a following
defaulting call or projection can expose an earlier application break before overflowing.
Final atoms in a `.suffixGroup` are suffix-eligible by their structural ownership,
including generated postfix operators. Operand fit checks count those atoms together
with enclosing suffixes such as `:= by`; the classifier uses the complete group's
child list even when its current segment is sliced. Single-child wrappers preserve
that ownership, while ordinary identifier arguments remain separate operands.
A preserved proof island retries structurally only when its attached suffix creates an
overflow that the preserved proof did not have. Parser-identified spaced tactic
applications may participate in that retry, allowing their ordinary application
breakpoints to leave room for closing delimiters and projection members.
A parser-identified spaced tactic locally groups the `by` introducer of a final
parenthesized, one-line proof argument with its proof body. The surrounding application
and delimiters remain intact, so fitting proofs compact while nonfitting arguments retain
ordinary application indentation. Multiline proof content remains an original-layout
island.
A regrouped proof body stops inherited suffix measurement after its `by`
introducer; the proof renderer may still keep a fitting first tactic, such as `classical`
or `calc`, on that line. When measurement stops before a token or rule boundary,
same-line comment trivia preceding that boundary still contributes to the fit.

The existing binder-body classification also identifies trailing operands as
suffixes. For `∫⁻ t : T, X ∂(Y)`, the body reserves the compact `∂(Y)` width,
including any enclosing declaration suffix. The rule layer classifies tokens in
that trailing operand as suffix-eligible, allowing measurement across its optional
breaks; mandatory boundaries and line-breaking comments still end measurement.
This gives breaks inside `X` priority over breaks inside `Y`, without changing
breakpoints or adding syntax knowledge to the renderer. Reservation guides fit checks, not emission:
a measure that cannot remain compact still uses its ordinary structural layout.

### Proof and original-source escape hatches

Proof subtrees, attribute instances, and unresolved parser `choice` nodes are not
reformatted. A choice retains its internal source line structure because changing it can
remove one of Lean's valid parses even when the token stream is unchanged.
`Formatter.OriginalTree` owns protected-tree classification, source-slice rebasing, and
emission planning. Classification still identifies a `LayoutIslandKind`, but rendering
uses an `IslandPlan` containing an explicit `IslandPolicy`: content layout, multiline
behavior, first-line breakability, relative-layout retention, pending-indent behavior,
anchor choice, leading-boundary ownership, and following-comment ownership. The renderer
retains that complete plan instead of repeatedly interpreting a classification tag.
Lemma and theorem commands use the same structural declaration and equation ownership;
parser groups directly owning declaration equations reuse the theorem rule, and
transparent wrappers retain the enclosing modifier owner's base. Only their proof
bodies remain protected. A transparent owner such as `cases`, induction
alternatives, or a regrouped `calc` exposes its governing boundaries while leaf proof
regions remain protected. An unregrouped calc shape remains an original-layout
compatibility fallback and cannot justify opening its protected parent.
Its renderer-facing API returns the planned text, final token, and the one
comment-boundary flag needed by subsequent ordinary rendering; it does not own or mutate
renderer state. When the renderer reaches a recognized proof or attribute node, it
applies that plan. If the renderer has already formatted the boundary before an island,
that boundary's output column is final; original-tree emission rebases only the island's
source slice and must not apply the source-to-output shift to the boundary again.
A following standalone comment at or above the next source token's indentation follows
that token. When an island's policy preserves following-comment ownership, a comment
deeper than the next token retains the same relative depth as both move; no blank-line
exception is needed to establish that source nesting.
A multiline syntax-owned module or declaration comment stores part of its text inside a
token rather than trivia. Original-tree emission treats the complete comment source slice
as one layout island. Its first physical line uses the formatted opening anchor. Later
nonblank lines preserve their indentation offsets from the slice's common source
continuation margin beneath that anchor. This also covers a comment whose opener began
inline while its continuation began at the surrounding block margin. Its indentation
therefore does not depend on how the parser divides the comment into tokens.
The same continuation-floor rule applies to a multiline block comment inside any moved
original-layout island. When a continuation was authored left of the island's first token,
it may align with the moved island base but cannot escape to the stale source column.
A protected subtree that begins on a new source line inherits the source-to-output
layout-base translation established by its enclosing formatted segment. The output-side anchor is
the column where that segment actually starts, including when a child that began a source
line now follows a formatted prefix such as `:`. Every protected line moves by the same
delta. A proof island normally cannot move left of its structural proof indentation,
which keeps a block proof beneath its owning `have` rather than beneath a wrapped type
continuation or outside its declaration. This structural floor is retained even when an
unbreakable tactic line consequently exceeds the configured width.

Source preservation is node-local, not a recursive rendering mode. An opaque node emits
its source slice; a structural node visits children using their own resolved policies.
When moving a protected proof right overflows a structural header's first source line,
`OriginalTree.overflowAlternative?` can propose a sparse alternative: open the path to
that owner, retain its children's ordinary plans, and explicitly preserve all
neighboring source regions. A fitting declaration is not opened because an unrelated
tactic overflows. Quotations, ignored regions, and other non-proof islands are opaque
barriers to this search. Declaration headers, parser-owned headers, and owners with a
directly attached proof term are eligible. Existing declaration, expression, and proof
rules supply every new breakpoint; for example, an overflowing `show ... by` can wrap
its proposition or break after `by` without exposing the proof body's internal layout.
Applications and delimited arguments are also eligible when a positive indentation
shift newly overflows a previously fitting physical source line. Eligibility checks
all argument lines, not only the first, using character columns and the complete
source line, including trailing comments. A recovered argument and the affected
arguments enclosing it use consistent structural layout, rather than combining
reflowed values with stale source indentation for their peer fields or elements.
Their parser tactic wrappers become structural along with their contents;
nested proof, quotation, ignored, and other protected islands keep their own plans.
Header owners on the recovered path also retain ordinary child plans, so their
proof introducers establish the proof's structural base. Their declaration-header,
parser-owned-header, and suffix-group envelopes likewise keep ordinary child
plans: an attached keyword is part of that structural shell, not an independently
protected peer. Other ancestor paths
explicitly preserve unaffected siblings. There is no tactic-name dispatch or
extra rule API for this recovery.
Where recovery retains siblings, source-line ownership limits that sparse plan:
a retained token-bearing sibling protects the complete physical line it shares
with a candidate. `OriginalTree` discards partial recovery for that shared line;
it does not invent separator breakpoints or put source-boundary policy in the
renderer. Tokenless siblings do not protect a line, and retained siblings on
separate lines do not prevent recovery. Required indentation can therefore
produce an accepted protected-line overflow without opening only the final
argument of an inline sequence.
Optional single-value tactic assignments are regrouped in the syntax tree into a
definition with a parser-owned header, assignment token, and value. This exposes the
ordinary value boundary for `obtain`-shaped syntax without a tactic-specific break rule.
Absent assignments and multi-value assignment clauses retain their original shape.

The renderer resolves this alternative into its immutable `TreeLayoutFacts`, refreshing
the original-emission and multiline summaries along the changed path. Flat probes,
first-line and suffix measurement, and text emission all consume that same fact tree;
child probes select the child's facts and resolve its incoming base and source
anchor through the same placement calculation as nested rendering. Flat and
structural traversal restore the parent's scope on return. A first-line probe
measures the island's first content line with normal
leading-boundary spacing, not an empty line before its source start. Required
comment breaks remain part of that boundary. An island's multiline summary covers
its content, not the boundary before its first token. Enclosing owners count
retained boundaries between their children; transparent wrappers do not turn a
leading break into an internal one. Fit probes for sliced segments use that same
composition over their selected children, so retained body boundaries still
require the owning rule's indentation. Thus a quotation at the start of a line does
not force an otherwise fitting infix expression to break. There is no recursive switch
that disables descendant protection, and no mutation of the lossless syntax tree.
At an available flow boundary, an actually retained leading break still selects
that boundary's indentation even if the child's content is one line. This keeps
named-argument proof bodies beneath their header after `by` rejoins `:=`.
The alternative is built only after a moved source island overflows and is selected
only if it reduces the overflow count. Nested proof bodies therefore remain protected
even while their enclosing declaration is formatted structurally.

A source-emitted
quotation may instead reduce a uniform shift by whole
indentation levels, never past its original source column. That fit calculation reserves
any closing delimiters and other tight parent suffix that must remain on the island's
last line; excluding that suffix would undercount the actual completed-line width.
Protected proof and calc continuations retain their resolved owning indentation;
width fitting cannot reduce that indentation. Intact source lines may overflow
at that required base under the existing protected-line policy.

An attached suffix group is a structural header during overflow recovery even
when it contains only prefix tokens, such as `exact let`. Opening the owner does
not leave that group as a separately preserved neighbor while rebasing its body.
Terminal infix proof envelopes use the existing header/body/suffix split for
protected leaf proofs. The proof remains owned by its infix value: when the value
moves to a continuation line, its proof moves with that base rather than
inheriting the declaration's base. Assignment-first break priority remains
unchanged, even when a complete field header could fit before its proof.
Structural tactic owners remain atomic under their existing ownership contract.
An extracted proof-body container is not a body introducer, even when its first
tactic is `calc`. The enclosing lambda or clause keeps its ordinary body boundary;
the first tactic cannot replace the base shared by following proof statements.
Trailing-body extraction uses intrinsic tactic ownership rather than the body's
source-detached classification. A parser-owned tactic moved below `by` therefore
keeps the same enclosing header/body split. An extracted structural proof body
uses its available body boundary before wrapping internally; it rejoins its
introducer only when the complete body fits.
Attaching a protected multiline body also requires the complete preserved block
to fit, not just its first source line. Otherwise the existing body boundary is
used before any internal overflow recovery is considered.

Anonymous constructors and structure instances remain structural even when an item or
field contains a proof. Their ordinary rules own item, field, and closing-delimiter
indentation, while nested proof bodies retain their own protected source layout. An
application's first proof-bearing lambda is likewise structural; the narrower compound
case in which a later proof lambda follows an earlier multiline proof-bearing argument
remains one application-level island.
More generally, a rule with a zero-level breakpoint cannot be skipped when a nested
protected island retains a source line. The rule applies its complete structural layout
so closing delimiters and peer boundaries cannot drift. If a parent break moves a
protected proof-bearing application or other supported braced proof layout away from its
parent-relative source column, the renderer uses that tree's ordinary
structural rule. Equation clauses and other protected proof-layout shapes remain source
islands. The renderer also may retry an otherwise source-emitted complete delimiter island
structurally when doing so removes an avoidable overflow. Each structural path recomputes
the rule's breakpoints because protected-source emission intentionally does not prepare
them. This lets established collection, field, and nested-expression rules establish a
parse-safe block base without adding syntax decisions to original-source emission.
A protected tactic island receives the same overflow-only retry when its sole structural
content is a bracketed collection, possibly beneath transparent parser wrappers. The
collection rule then owns its item and delimiter layout; fitting authored tactic layout
remains protected. This covers parser-owned tactic headers such as `simpa [...] using`,
where `using` is also included in the parent suffix width so a collection is not accepted
flat when the attached keyword would make the completed line overflow.
For flow rules, a multiline protected child likewise prevents acceptance of the whole
segment's fitting multiline probe. When the rule exposes a boundary before that child,
computed flow takes it and renders the complete child from the selected continuation base.
A retained body beginning at a rule-owned source break receives that rule's
indentation even during flat traversal. Its introducer's previous inline position
does not determine the body's base. This does not reject the entire surrounding
probe: fitting headers can remain compact while the body's authored break is
retained. Balanced layouts still account for retained breaks at their own child
boundaries; a break before the whole segment is not an internal break.
Unbroken intermediate headers do not introduce continuation bases. When a retained
break makes an owner multiline, its base is resolved from that owner's entry
placement, not from the cursor after rendering its prefix.
Checked probes propagate a local retained-body-break flag, separately from
comment line breaks. Enclosing zero-indent layouts reject that candidate and use
their existing structural rules. This flag is not persistent renderer state.
Retained-boundary summaries follow the resolved island policy through wrappers;
an original-layout island whose leading boundary is structural does not retain
that source break. A parent rule that formats the boundary likewise takes
precedence. Source preservation alone does not make a boundary mandatory.
When the incoming line already overflows, only width rejection is disabled;
the same placement and layout checks still apply.
The single-expression `doExpr` parser wrapper inherits its binding's base;
it does not establish a second base at an inline expression introducer.
Compound proof-layout islands consume an available pending indent through their
island policy, both in probes and nested emission. Their continuation rebasing
uses that same resolved choice; the renderer does not add a separate policy override.

When a multiline proof or
quotation begins inline, its later source lines use the introducer's source-to-output
movement, clamped to the island's structural indentation, rather than treating the
far-right first token as an indentation anchor. If formatting moves the quotation's
first token onto its own line, that first token becomes the source-to-output anchor;
continuations do not retain the column of an introducer that is no longer inline.
The same clamp applies when a quotation's line structure is stored inside its source
slice instead of token-leading trivia; width fitting cannot pull that continuation
below the enclosing structural base.
A terminal run of closing delimiters that begins on later source lines identifies the
quotation island's original base, so those delimiters return to the moved quotation's
base while the protected body retains its relative indentation.
Module and declaration documentation
comments are also emitted from their original source slices so their internal whitespace
cannot be changed. This
protects tactic scripts, term proof layout, quotation bodies, and comment text while
declarations around them can still be formatted. When an original-source child followed
its previous token on the same source line, it honors a pending boundary selected by its
parent rule; an existing source-line boundary and the child's internal layout remain
unchanged.
Qq terms use their own original-layout classification rather than the generic Lean
quotation policy. Their first line is indivisible, but their leading boundary is structural:
an application or other parent rule may move the complete `q(...)` island to its selected
continuation base without opening or reformatting the quoted syntax. That selected base is
also a floor for every continuation line in a multiline Qq island, so source indentation
cannot escape left of its new structural owner. Generated `Qq.termQ(...)` parser kinds use
the same policy, so generated variants cannot expose their outer closer to ordinary rules.
A protected proof-layout child that already begins on a source line still adopts a
pending structural indent from its parent before rebasing its internal relative layout.
This keeps nested record values beneath the field assignment that owns them. That
rule-owned indent is a structural floor for the complete island: fit recovery must not
leave later source-aligned lines at an older column, even when uniformly shifting a
pre-existing long line would make it longer. Equation arms therefore remain aligned
under their declaration instead of escaping Lean's layout block. When a parent moves a
protected layout to a new line column, that structural target applies to the complete
island, including every later equation arm and protected proof line in the block.
A proof body whose introducer starts its output line retains the introducer-relative
indentation, while an inline body that moves horizontally without an opening delimiter
starts at least one indentation level below its surrounding output layout base. A deeper
source indentation remains intact. When such an inline body is detached, a nested tactic
sequence authored at the original proof base remains a peer of the first tactic; other
continuations are normalized to one level. An inline body immediately after an opening
delimiter retains its delimiter-owned source layout while it remains inline. If structural
formatting keeps the opener with a preceding suffix and moves the multiline body to the
next line, original-tree emission rebases the complete body from its source first-token
column to the selected output body base; sibling tactics therefore move together.
Delimiter and `where` proof-layout islands likewise retain their established first-token
anchor so their fields do not drift with a moved header.
A multiline parenthesized tactic sequence with multiple sibling tactics retains the
hanging base immediately after `(`. Moving that complete island preserves the odd-column
alignment required by Lean's layout parser, while a parenthesized single tactic remains
structural so an owned body such as `case ... =>` can still be normalized.
An application whose argument is a proof-bearing `fun` is protected as one layout
island. The syntax tree owns the lambda shell but not the proof body's internal
layout, so moving the application and the proof independently can detach the proof
from the lambda selected by Lean's layout parser.

The escape hatch is intentionally narrow. If a non-proof syntax form is unsafe, prefer a
specific transparent/default rule or a grouping change before adding another original
source region. Tactic nodes identified by their position in a tactic sequence are
original-source islands unless they are structural layout owners. Core tactics also carry
an intrinsic parser identity; extension syntax outside tactic context remains ordinary
raw syntax. This covers extension-owned tactic grammars without cataloging individual
libraries in the formatter and avoids protecting unrelated syntax merely because its
namespace contains `Tactic`. Multiline custom braced term
syntax is also emitted from original source so leanfmt does not invent a layout for an
extension-owned DSL whose braces may carry domain-specific structure.
ProofWidgets JSX remains an original-source island, but its complete relative indentation
is rebased when the surrounding formatted layout moves it; leaving a JSX tag at its old
absolute column can change which tokens Lean's layout parser assigns to the element.
When the formatter-selected rebase would newly overflow an atomic JSX line, the renderer
also measures the source layout translated only by its parent layout's movement and uses
that candidate when it has fewer overflows. For `do` bodies, token emission records only
new atomic overflow caused by moving a source token away from a column where it fit.
The outermost eligible `do` sequence considers a source-layout candidate only when that
signal is present. Both source-relative candidates are bounded below by the child's
resolved structural base; recovering an old margin cannot detach the body from a
moved header. This avoids both repeated nested recovery and reconstructing large
`do` bodies for pre-existing overflow that recovery cannot improve. Rebased original text
is reconstructed token by token so whitespace inside string and other atomic token
lexemes is never changed.
An original-source island whose own source slice is single-line still participates in
ordinary flat-fit checks, so inline extension syntax does not force its parent to break.
The island normally retains its source-leading boundary as well. A surrounding rule can
claim that boundary with `formatOriginalChildLeadingBoundary`; the renderer then supplies
the boundary whitespace and the island preserves only its internal relative layout.
`calc` uses explicit logical grouping instead of a whole-expression source island. Its
term or tactic owner owns the mandatory break before a proof-bearing body, the body aligns
rows one level beneath the rendered introducer line, and a proofless first term stays
attached to `calc`. The existing rounded-base policy includes a pending continuation
indent when a comment detaches the introducer. A multi-piece leading suffix group
is a compound header, not a plain introducer: its first token cannot suppress
the enclosing value boundary. A proofless `calc initialTerm` therefore moves as
one header, and the existing calc owner establishes the row base at that new
position. This distinction uses the grouped tree, not the initial term's text.
The flow renderer's overflow retry requires an existing rule breakpoint and uses
that breakpoint's indentation. It does not create a post-operator boundary to
reduce protected-line overflow.
A long single-operator step can break before its operator. Opaque
operands retain protected internal layout, while a regrouped application or infix chain on
the right uses its ordinary breaks before the attached assignment overflows. A
low-priority chain may keep `<| calc` after an indivisible left operand; when the left
operand itself has structural breaks, the outer `<|` boundary takes priority over
splitting that operand merely to reserve space for the calc suffix. Diagnostics treat an
unchanged protected calc operand shifted right by structural indentation as an
unbreakable-layout overflow.
An ordinary infix rule owns the leading boundary of each right operand, including
an operand preserved by an overflow-recovery alternative. Its internal source
layout remains protected; a retained leading newline cannot leave the operator
alone after the rule breaks before it.
The low-priority infix rule likewise owns the first line of an ordinary right operand.
When a non-suffix right operand is multiline, the outer infix rule breaks before the
complete operator-and-operand group. The nested operator-operand owner formats that
operand's leading boundary and exposes no second break after the operator. The operand's
own syntax then controls any internal wrapping. Preferred expression-head alignment yields
to that owned boundary, so an ordinary conditional starts after one token-space rather
than acquiring padding from both owners. Layout-sensitive binding expressions such as
`let` and `have` still require start alignment on the operator line, and the operand's syntax rule owns
its internal body breaks at that aligned base. A right operand containing a protected
proof body moves with the same complete group; original-tree planning remains responsible
for preserving and rebasing the proof layout. Structurally eligible delimited islands
reuse their normal structural fallback when the formatted boundary moves them. Suffix
operands such as `by`, `do`, and `calc` retain their established suffix attachment and
source-layout handling instead of transferring that boundary. A protected operand whose
first source line cannot fit beside the operator, or whose first token follows a
line-breaking comment, retains the post-operator boundary and its relative source layout.
When formatting that boundary detaches an inline protected layout, original-tree
emission rebases from the first token only when the continuation was authored at or to
the right of that token. A proof continuation authored to the left of an inline
`show ... by` belongs to the surrounding structural owner instead; it moves to that
owner's base rather than being clamped against the former inline column. A quantified
`show ... from` result already owns structural body breaks, so a nested proof after
`from` does not promote the complete `show` to one proof island. The `show`, `from`,
and application retain their normal break rules while the nested proof keeps its own
protected layout. Other proof-bearing `show` terms retain their established island.
That ownership propagates through leading-child wrapper chains and stops at the first
preceding sibling. A transparent type specification can therefore normalize the boundary
after `:` even when a known application or infix node wraps the extension-owned term,
without claiming spacing inside that known syntax.
Syntax-authoring commands (`syntax`, `macro_rules`, `elab`, `elab_rules`, and `run_cmd`), Batteries
alias and library-note commands, and raw generated command syntax are layout islands for
the same reason. Generated commands first pass through ordinary regrouping, so a command
recognized as a definition, annotated declaration, or other structural owner does not use
this fallback. The fallback is based on the parser's generated `command...` kind rather
than the command's namespace. When such a command owns standalone trailing comments, the
original island carries a one-boundary comment-indentation marker so those comments retain
their source indentation without affecting the following formatted command.

If an unbreakable value already starts on a source line and moving it to the preferred
indentation would create an otherwise avoidable overflow, the renderer first keeps its
source column translated by the parent layout's movement. When a source-broken
application begins with an unbreakable qualified head and that parent-relative column
still overflows, the renderer may use the original absolute source column as a final
fitting candidate. Structural multi-token children never recover past a pending base
selected by their parent rule; they use their own break rules or accept the resulting
overflow. Single tokens, atomic rules, multiline atomic tokens, and quotation islands may
still use the source-column mechanism. Standalone comment trivia does not
make an otherwise valid structural layout fail its fit probe: the comment follows the
surrounding code's indentation even when the unchanged comment text then exceeds the line
limit. If reformatted code makes an attached line comment overflow, the renderer moves the
unchanged comment text to its own line without changing the following code's indentation.

## Diagnostics and formatter exceptions

Diagnostics are separate from formatting. The compact-bang diagnostic examines tokens
and reports ambiguous spellings such as `!f a b`, but it does not rewrite them. The
diagnostic API lives under `Formatter.Diagnostics`.

Formatter safety checking is also separate from rendering. It orders source-backed
tokens by their lexeme spans, scans every physical source gap between them for comments,
then compares the code-token sequence and comment text. Line-comment text and relative
block-comment whitespace are exact. A uniform indentation shift of a complete multiline
block comment is normalized against the comment's opening column, allowing the comment
to move with its owning syntax without allowing internal relative whitespace to change.
The check does not rely solely on Lean's token-trivia attachment, because comments after
delimiters may exist only in those source gaps. The safety check also reports remaining
line overflow. The separate opt-in missing-rule check reports source locations and tree
slices. Each missing raw syntax kind is classified by whether Lean provides a registered
formatter, only a parser-description fallback, or no formatter metadata. The
classification comes from the same parser-layout adapter used by regrouping; it does not
delegate rendering to Lean's pretty printer. Non-ignorable missing leanfmt rules become
exceptions when that check is enabled. Preservation normalization gives every code token
and comment boundary one canonical space, so ordinary formatting whitespace is ignored
without conflating tokenizations such as `ab c` and `a bc`. `ruleFor` returning `none`
still renders with `defaultRule`, so unknown nodes remain conservatively formatable.
Generated private parser node names beginning with `_private.`,
custom term-notation node names such as `termℂ` or `Some.Namespace.termFoo`, token nodes,
and generated `stx` helper names are ignored by missing-rule reporting because they are
not stable rule targets. Diagnostic analysis and the exception model live in
`Formatter.Diagnostics`; trace and profiling APIs live under `Formatter.Debug`;
convergence and shared pipeline phases live under `Formatter.Internal`.

Ignored-region chunks also pass a whole-file parse and syntax-preservation check.
Chunks can lose an enclosing namespace or split a declaration; if a chunk cannot be
parsed or the assembled result differs structurally, formatting retains the complete
original source and reports a preservation fallback. This conservative guard does not
try to reconstruct parser context at arbitrary source offsets.

### Preservation-check limitation: layout-sensitive elaboration

The preservation check is necessary but not complete. It compares code-token/comment
fragments and a source-info-stripped syntax signature. Syntax-owned module and declaration
comments delegate their contents to comment fragments, which preserve text and relative
indentation while permitting a uniform column shift. Outside quotations, the signature
canonicalizes Lean's parser-packed `doIf` continuation clauses into nested `doIf`
nodes inside single-statement `else` sequences, matching Lean's elaborator expansion.
This permits `else if` to split across lines without accepting arbitrary scope changes:
condition and branch signatures, bindings, sequence items, and following statements
remain intact. No general statement-sequence wrapper is discarded. Quotations retain
their raw parser shape because macros can inspect it. Lean elaboration can still change
when formatting changes layout-sensitive source positions that are not represented in
that signature.

Mathlib validation exposed this class of bug:

- repository: `leanprover-community/mathlib4`
- commit: `81a5d257c8e410db227a6665ed08f64fea08e997`
- file: `Mathlib/Combinatorics/SimpleGraph/Triangle/Removal.lean`
- original source lines: `179-186`
- failing formatted build target:
  `Mathlib.Combinatorics.SimpleGraph.Triangle.Removal`

The original source used a layout-sensitive `do` fallback:

```lean
meta def evalTriangleRemovalBound : PositivityExt where eval {u α} _zα pα? e :=
  match pα? with | none => pure .none | some _ => do
  match u, α, e with
  | 0, ~q(ℝ), ~q(triangleRemovalBound $ε) =>
    let .positive hε ← core q(inferInstance) (some q(inferInstance)) ε | failure
    assertInstancesCommute
    pure (.positive q(triangleRemovalBound_pos $hε))
  | _, _, _ => throwError "failed to match on Int.ceil application"
```

An unsafe formatter version produced this patch. The result was parseable and the
token/syntax preservation diagnostics reported no code change, but the post-format build
failed:

```diff
@@
-meta def evalTriangleRemovalBound : PositivityExt where eval {u α} _zα pα? e :=
-  match pα? with | none => pure .none | some _ => do
-  match u, α, e with
-  | 0, ~q(ℝ), ~q(triangleRemovalBound $ε) =>
-    let .positive hε ← core q(inferInstance) (some q(inferInstance)) ε | failure
-    assertInstancesCommute
-    pure (.positive q(triangleRemovalBound_pos $hε))
-  | _, _, _ => throwError "failed to match on Int.ceil application"
+meta
+def evalTriangleRemovalBound : PositivityExt
+  where
+    eval {u α} _zα pα? e :=
+      match pα? with
+      | none => pure .none
+      | some _ => do
+          match u, α, e with
+          | 0, ~q(ℝ), ~q(triangleRemovalBound $ε) =>
+              let .positive hε ←
+                core q(inferInstance) (some q(inferInstance)) ε | failure
+                                                                  assertInstancesCommute
+                                                                  pure
+                                                                    (.positive
+                                                                      q(
+                                                                        triangleRemovalBound_pos
+                                                                          $hε))
+          | _, _, _ => throwError "failed to match on Int.ceil application"
```

The build errors were:

```text
Mathlib/Combinatorics/SimpleGraph/Triangle/Removal.lean:188:14:
Application type mismatch: The argument PUnit.unit has type PUnit.{1}
but is expected to have type Strictness _zα e (some val✝)

Mathlib/Combinatorics/SimpleGraph/Triangle/Removal.lean:195:75:
Unknown identifier `«$hε»`

Mathlib/Combinatorics/SimpleGraph/Triangle/Removal.lean:198:64:
failed to prove positivity/nonnegativity/nonzeroness
```

The architecture response is to give `do` let fallbacks explicit syntax rules.
When a `doIdDecl` or `doPatDecl` contains a fallback tail, the declaration may break
after `←` and before the `|` fallback arm. The wrapper that owns `| fallback` plus the
following `do` continuation forces a break before that continuation. This keeps
continuation commands at the outer `do` indentation instead of allowing them to become
source text after the fallback expression. A fallback containing multiple direct
`do` items receives a structural breakpoint one level beneath the pipe; a single
fallback expression may move onto the pipe line even when the source broke there. The
later continuation still returns to the declaration base. The post-format build remains
the guardrail for preservation classes that syntax diagnostics cannot prove.

A refutable `let pattern := value | fallback` receives the same treatment when
the fallback contains multiple direct `do` statements: the fallback breaks after
`|`, its statements share the one-level-deeper base, and the successful
continuation returns to the declaration base. A single fallback expression may
remain on the pipe line. A line-breaking comment immediately after `|` moves beside
the pipe and supplies the unavoidable break; the fallback body then uses the same
structural base as the uncommented form.

Overflow analysis uses the formatted module's lossless token spans. A terminal token
exempts overflow only when the token itself is wider than the configured limit; a token
that fits by itself remains actionable because another rule may move it, unless the
formatted line already consists only of that token or an atomic syntax tree and tight
excluded line enders at its
structural indentation. Comment-only overflow is similarly exempt when the same literal
comment line occurs in the source, even if formatting moves it to a deeper structural
indentation. New or changed overflowing comment text remains actionable.
Preserved original-source islands and syntax marked atomic by its line-break rule remain
exempt when they cover the entire suffix beyond the width limit. This keeps rendering and
diagnostics consistent for multi-token atomic syntax such as projection suffixes and
interpolated strings. A comma is also joined to any preceding atomic tree without requiring
a particular array or structure context. A `.suffixGroup` attached to an application makes
the prefix and application head one indivisible diagnostic span while the arguments remain
breakable. That suffix-owned application head is directly exempt because no rule can
separate its prefix and head. Parser-described spaced tactics retain a breakpoint before
their application operand and therefore need no corresponding diagnostic exemption.
An indivisible unit may be followed immediately by any sequence of tokens in the
diagnostic's excluded line-ender set. The set contains closing delimiters, commas, and
semicolons; it is explicit rather than inferred from parser context. Other overflowing
lines still indicate that the formatter left a possible structural break unresolved.
Formatting exception checks compare normalized overflowing line text with the source and
report only newly introduced shapes; unchanged pre-existing overflow remains available
through direct `overflowOccurrences` analysis without being attributed to the formatter.
They discard these inherited occurrences before building structural overflow evidence.
Code preservation remains a separate check even when no new overflow remains.
The standalone analysis keeps layout-island and isolated-token exemptions, while the
source-versus-formatted comparison temporarily removes those movable exemptions. This
reports a movable quotation or isolated token that fit in source but was shifted past
the limit, without reporting the same pre-existing source overflow. Proof, compound
proof-layout, and protected tactic islands remain exempt: their text is emitted as an
indivisible source-layout unit, so no internal rule boundary is available to resolve an
overflow introduced by a required structural move. A line headed by one indivisible
atomic tree uses the same exemption as a line headed by one token. Otherwise, the
comparison maps token indexes back to the source and retains a movable atom's
exemption only when its original physical line already overflowed; this covers an
unbreakable declaration name split away from an already-long command prefix.
An otherwise fitting source line that becomes too wide only because a protected island
receives its required structural indentation is also exempt when the normalized line text
is unchanged. A line consisting of opening delimiters followed by one indivisible token
uses the same principle: the delimiters do not make an unbreakable qualified identifier
actionable merely because the complete physical line exceeds the limit.

The CLI reports each exception at its file, continues processing later files, and
aggregates per-kind counts for a final summary. Non-idempotence participates in that CLI
summary even though its extra formatting pass is enabled separately. A file whose first
formatting result equals its source is already a fixed point, so the driver runs the
extra idempotency pass only when formatting changed the text. With diagnostic
checking enabled, `--check` controls writing only; diagnostic exceptions, rather than
ordinary formatting differences, determine failure.

## Why these choices

### Why not Lean's pretty printer?

Lean's pretty printer is semantic and elaboration-oriented. leanfmt needs to preserve
unrecognized syntax, comments, proofs, and exact token text in files that may contain
project-specific parser extensions. A source formatter needs a lossless source tree,
not just pretty-printed elaborated terms.

### Why regroup applications and infix chains?

Parser shape for applications is nested: `f a b` arrives like `((f a) b)`. Formatting
applications wants one head and a list of arguments, so `.application` flattens that
shape.

Infix chains are kept for balanced peer-operator breaks. Raw binary infix trees are
locally usable, but a long chain needs one rule decision over all peer operators. The
syntax-tree pass evaluates the active trailing parser descriptions once per syntax kind
and flattens adjacent binary nodes with identical binding powers. Thus `+` and `-`, or
project-defined peers, share a continuation base without a formatter-maintained operator
table. The `.infixChain` node keeps that syntax reasoning in rules and leaves indentation
math in the renderer. If an infix chain's right operand is an alternating
`term | term | ...` sequence, the infix rule exposes the right-operand boundary and the
generic wrapper rule flows at its bars. This is a parser-derived shape classification
rather than a rule-name or token-text special case.

### Why rule and renderer separation?

Rules know syntax. `SourceBoundary` knows authored trivia. `LayoutPlan` composes rule
judgements into a stable renderer contract. The renderer knows columns and fit. Keeping
those concerns separate prevents rendering from asking what token or tree kind it is
handling, while `Rebase.Anchor` keeps source/output column translation coherent.

### Why preserve proofs?

Proof scripts are dense, style-sensitive, and often use tactic syntax that changes across
imports. Formatting theorem statements while preserving proof bodies provides useful
formatting without imposing a tactic layout policy.
