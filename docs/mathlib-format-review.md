# Mathlib formatting review

This document records the visual review of a complete Mathlib formatting run so
the remaining layout work can be addressed without repeating the corpus review.
It is a point-in-time work list, not part of the normative formatting style.

## Remaining issues and TODO

Mathlib paths are evidence and regression inputs, never conditions in formatter
code. The open items below are governing layout problems. Long indivisible lines
and formatter-created too-many-lines warnings are not findings when the
surrounding shape and starting indentation are correct.

### Final initial-release checkpoint

**Status: the focused comment-ownership checkpoint passed the complete final
validation; this candidate is ready for the initial release.**

Commit `13e7968` is the structural calc baseline. The final candidate fixes the
two blocker families found during its Mathlib review: source-tight generated
notation such as `∂μ`, `∂.pi`, and `#{...}`, and delimited calc proofs whose
opener, body, and closer must move coherently. The fixes use syntax regrouping,
existing line-break rules, and original-tree ownership. They add no renderer
syntax checks, specialized calc rule, token exception, or new rule API.

Commit `906e73b` is the preceding exact candidate. The focused release candidate
adds generic source-comment ownership and boundary emission: comments at or
shallower than the following source token follow that token; a trailing comment
group ending before a blank stays with the preceding body; and blank-separated
comment groups split ownership at the existing blank. The renderer uses those
source boundaries without adding comments or breaks to the syntax tree, and the
spacing layer rebases complete comment groups while preserving multiline block
comment interiors. No syntax-specific comment exception or new rule API was
added.

The final candidate passed the complete local, GraphQL, quantum, and exact
Mathlib `v4.32.0` gates. Relative to the preceding archived Mathlib tree, its
17-file delta consists of the two already-approved `∏ᶜ fun` corrections and 15
comment-ownership corrections. Independent review found every final hunk sound,
including proof-, field-, branch-, notation-, and following-command ownership.
Minor high-risk imperfections listed below remain deferred; exceptions,
non-idempotence, code changes, actionable overflow, build failures, and
performance regressions are all clear.

### Remaining issue queue

| Family | Representative evidence | Intended owner | Risk | Order |
| --- | --- | --- | --- | --- |
| A line comment between a calc proof and the following row can move from the proof indentation to the row indentation | `Mathlib/Analysis/Normed/Field/Approximation.lean` | Generic source-comment ownership and original-tree emission | High | Defer unless the release audit finds a regression |
| A moved `fun`, quotation, or parenthesized protected body without a usable parent boundary retains a stale column | `Mathlib/Analysis/BoxIntegral/Partition/Split.lean:155`; `Mathlib/AlgebraicGeometry/Gluing.lean:644`; `Mathlib/Data/Nat/Bitwise.lean:260`; `Mathlib/RingTheory/WittVector/Basic.lean:85`; `Mathlib/Tactic/MinImports.lean:170`; `Mathlib/MeasureTheory/Integral/CurveIntegral/Basic.lean:253`; `Mathlib/Probability/Kernel/IonescuTulcea/Traj.lean:746` | Syntax grouping and original-tree planning | High | Post-release checkpoint |
| Peer application, declaration-field, or `calc` continuations disagree on their shared base | `Mathlib/Geometry/Manifold/MFDeriv/SpecificFunctions.lean:277`; `Mathlib/Algebra/Order/Monoid/Defs.lean:28`; `Mathlib/Analysis/InnerProductSpace/Projection/Basic.lean:362` | Syntax grouping, line-break rules, and renderer continuation bases | High | Separate checkpoint |
| A protected branch or source-preserved elimination body remains aligned with its header | `Mathlib/Algebra/BigOperators/Fin.lean:632`; `Mathlib/Data/ENat/Lattice.lean:139`; `Mathlib/Analysis/Meromorphic/Order.lean:198` | Tactic ownership and protected-body rebasing | High | Separate checkpoint |
| A source-preserved line-comment continuation can detach from its first physical line | `Mathlib/Algebra/ContinuedFractions/Computation/Basic.lean:193` | Original-tree source slices and generic comment-boundary handling | Medium | Separate checkpoint |
| A proof-bearing structure-valued `where` can retain a stale leading boundary | `Mathlib/CategoryTheory/Abelian/Injective/Resolution.lean:327` | Original-tree classification and layout planning | Medium | Separate checkpoint |
| Mathlib `lemma` equation arms in a `mutual` block can use the wrong command base | `Mathlib/AlgebraicGeometry/Morphisms/ChevalleyComplexity.lean:624` | Syntax grouping and original-tree ownership | High | Separate checkpoint |
| Inline record and attribute children can inherit the opener's source column | `Mathlib/Lean/Meta/RefinedDiscrTree/Basic.lean:169`; `Mathlib/Algebra/Group/Submonoid/Membership.lean:553` | Syntax grouping and continuation-base planning | High | Separate checkpoint |

### Release TODO

1. Complete: the exact `906e73b` local gate passed lint, self-formatting, every
   fixture check, preservation, missing rules, fallback, idempotency, and
   `git diff --check`.
2. Complete: fresh GraphQL and quantum validation passed with automatic worker
   counts, clean diagnostics, reviewed output, and successful final builds.
3. Complete: exact Mathlib `v4.32.0` passed all 83 width-100 `Mathlib` batches
   using the Lake cache and passed the complete post-format build.
4. Complete: independent reviewers checked generated prefixes, delimited proofs,
   calc layout, comments, and broad external output. The intended final delta is
   sound.
5. Complete: focused reproductions cover trailing body comments, declaration-
   leading comments, blank-separated ownership groups, declaration-result
   continuations, multiline block comments, preservation, and idempotency. The
   generalized fix uses existing APIs and passed another complete validation.

### Accepted output

- Adjacent anonymous-constructor delimiters can accumulate one indentation
  level per syntax delimiter. `Mathlib/Algebra/AlgebraicCard.lean:66` remains
  intentionally deferred.
- A preserved source break after `<|` can retain two spaces before the next
  token, as in `Mathlib/Lean/Expr/Basic.lean:301`. This is intentional unless
  the spacing policy changes.
- Long unbreakable lines are accepted when they begin at the correct logical
  indentation. Formatter-created long-file warnings are accepted when the
  formatting shape is sound.

## Validation/checkpoint standards

### Change design

- Generalize a syntax or layout invariant. Never add Mathlib paths, declaration
  names, or isolated token sequences as formatter exceptions.
- Keep syntax regrouping, line-break decisions, horizontal spacing, and source
  emission in their owning modules. The renderer manages layout state and
  executes plans without identifying Lean syntax kinds.
- Reuse existing syntax groups and rule APIs. A new rule API is a high-risk
  design change and requires separate review before implementation.
- Keep one governing invariant per commit. A larger checkpoint may contain
  multiple commits only when each is independently testable and the final
  corpus delta remains attributable.
- Add focused formatting, code-preservation, fallback, and idempotency coverage
  before accepting generated fixture or external-project churn.

### Local gate

Every checkpoint must pass:

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

Review fixture and self-format changes immediately. A generated change is not
accepted merely because regeneration produced it.

### External validation

- Use the formatter's automatic worker count. Do not pass `--jobs`.
- Validate GraphQL from `$HOME/work/apollo/graphql-lean` and quantum from
  `$HOME/work/lean-libs/quantum-computing-lean`. Check exceptions,
  preservation, idempotency, formatting changes, phase timings, both builds,
  and any performance trend.
- Validate only the `Mathlib` directory at width 100 against exact Mathlib
  `v4.32.0` commit `81a5d257c8e410db227a6665ed08f64fea08e997` and use the
  Lake cache. Skip the pre-format build because the input is a released commit;
  always run the complete post-format build.
- Run all 83 Mathlib formatter batches unless resuming persisted state produced
  by the same formatter binary and pristine input. Every batch must pass code
  preservation, actionable-overflow, missing-rule, fallback, and idempotency
  checks.
- Compare formatting identical pristine inputs with the preceding committed and
  candidate binaries. Review the isolated checkpoint delta rather than a reused
  checkout's accumulated history.
- After a clean Mathlib build, use independent reviewers to look for wrong or
  missing line breaks and incorrect indentation. Accept long indivisible lines
  at the correct base and formatter-created too-many-lines warnings when the
  surrounding shape is correct.

### Checkpoint acceptance

A checkpoint is complete only when the local gate and requested external rings
pass, the exact formatting delta is understood, no exception or build failure
remains, and timings show no material regression. Record commands, commits,
phase timings, diff statistics, representative review, accepted warnings, and
the next bounded step here before committing.

## Checkpoint history

Entries are ordered newest first. They record what changed and the validation
evidence available at that checkpoint; open work is maintained only in the
queue above.

### 2026-08-10: Formatter architecture boundary migration

Commit `e79aa66` introduced explicit `SourceBoundary`, `LayoutPlan`, and
`Rebase` modules, made original-tree island policy explicit, and removed Lean
syntax-kind decisions from the renderer. The follow-up cleanup removes the last
two source-trivia reads from line-break rule callbacks. A new
`.localDeclarationHeader` syntax group gives a local declaration's signature
and value separate layout ownership: the header owns a possible break before
its return type, while the outer declaration owns the value break. The
`doLetRec` source-break behavior now composes existing flow and source-boundary
policies without a specialized renderer path or a new rule API.

The complete local gate passed, including both builds and tests, the development
linter, fixture regeneration and dry checking, self-formatting, code
preservation, actionable overflow, missing-rule, fallback, idempotency, and
`git diff --check`. GraphQL passed three formatter batches in 20, 12, and 7
seconds and its final build in 3 seconds; its only output change is the intended
long local return-type layout. Quantum passed its formatter batch in 14 seconds
and its final build in 2 seconds with no output change.

Exact Mathlib `v4.32.0` passed all 83 width-100 `Mathlib` batches and the full
8,654-job post-format build. The formatter batches took 2,456 seconds, the build
took 3,498 seconds, and all external phases took 5,985 seconds under unusually
high host load. The isolated checkpoint delta is 74 files, 202 insertions, and
210 deletions. Every hunk is a local declaration signature: fitting signatures
collapse, while long signatures break before `:` from the declaration base and
retain separate value-body ownership. No exception, preservation failure,
actionable overflow, missing rule, fallback, non-idempotence, or build failure
occurred.

A same-files A/B on Mathlib batch 13 compared committed/current wall times of
50.02/46.75 seconds and then 44.58/40.21 seconds. Average user CPU fell from
about 95 to 88 seconds, so the migration adds no measurable formatter cost.
With component ownership now explicit and the source-trivia checks removed from
line-break rules, the architecture migration is complete. The next bounded
checkpoint returns to the remaining formatting queue, beginning with the
source-preserved line-comment continuation case.

### 2026-08-10: Focused comment ownership release checkpoint

The final candidate generalizes source-comment ownership without changing the
syntax tree or adding a rule API. A comment group ending before a blank remains
owned by the preceding body; a later blank-separated group follows the next
tree; comments moved beside a suffix use the following tree's source and output
bases; and multiline block-comment interiors remain anchored to their opener.
Focused tests cover trailing structure, proof, and command comments, split
ownership groups, proof-step and declaration-body leading comments, long and
multiline declaration-result comments, code preservation, fallback, and
idempotency. One intermediate whole-corpus run exposed an over-broad blank-line
placement; focused tests captured its governing shape, and the final generic
boundary correction removed all four reviewed regressions.

The complete local release gate passed: both builds and tests, the development
linter, fixture regeneration and dry checking, self-formatting, code
preservation, actionable overflow, missing-rule, fallback, idempotency, and
`git diff --check` were clean. Fresh GraphQL and quantum runs used automatic
workers and no `--jobs`. GraphQL's initial build, three formatter batches, and
final build took 81, 16/11/6, and 0 seconds. Quantum restored its cache in 13
seconds; its initial build, formatter batch, and final build took 36, 11, and 2
seconds. The combined run took 259 seconds. Both formatted Lean trees were
byte-identical to their preceding validated outputs.

The definitive Mathlib run used exact `v4.32.0` commit
`81a5d257c8e410db227a6665ed08f64fea08e997`, width 100, only the 8,264 tracked
files under `Mathlib`, the Lake cache, and automatic formatter workers. Cache
restoration took 28 seconds. All 83 batches passed preservation,
actionable-overflow, missing-rule, fallback, and idempotency checks. The complete
8,654-job post-format build passed in 3,215 seconds; total validation took 5,889
seconds. This is slightly faster than the preceding 3,288/5,982-second full run,
and the known heavy formatter batches stayed within their prior timing ranges.

The final Mathlib tree changes 7,552 files by 336,385 insertions and 295,058
deletions relative to pristine Mathlib. Relative to the archived preceding
formatted tree, exactly 17 files change: two retain the approved `∏ᶜ fun`
attachment and 15 correct generic comment ownership. Review confirmed trailing
proof and structure comments stay in their bodies, blank-separated leading
comments stay attached to following commands, branch comments use their branch
bases, and no source-authored blank is duplicated. Formatter-created long-line
and long-file warnings remain accepted only where the surrounding shape and
starting indentation are sound. This checkpoint has no remaining initial-release
blocker.

### 2026-08-10: Exact final-candidate validation

Commit `906e73b` (`Preserve generated notation and delimited proofs`) passed the
complete local release gate. Builds, tests, the development linter, fixture
regeneration and dry checking, self-formatting, code preservation, actionable
overflow, missing-rule, fallback, idempotency, and `git diff --check` were all
clean. The only self-format change was a mechanical wrap in
`LeanFmt/SyntaxTree.lean`, folded into the candidate before the final gate.

Fresh GraphQL and quantum runs used automatic formatter workers and no `--jobs`
option. GraphQL's initial build, three formatter batches, and final build took
96, 18/12/7, and 0 seconds, with no source delta. Quantum restored its cache in
13 seconds; its initial build, formatter batch, and final build took 38, 12, and
15 seconds. Its reviewed five-file delta remained the previously accepted calc
alignment change. Every diagnostic and both final builds passed; the combined
external run took 297 seconds.

The definitive Mathlib run used exact `v4.32.0` commit
`81a5d257c8e410db227a6665ed08f64fea08e997`, width 100, only the 8,264 tracked
files under `Mathlib`, the Lake cache, and automatic formatter workers. Cache
restoration took 30 seconds. All 83 formatter batches passed preservation,
actionable-overflow, missing-rule, fallback, and idempotency checks. The full
8,654-job post-format build passed in 3,206 seconds; total validation took 6,390
seconds. Formatter-created long-line and long-file warnings were accepted only
where the surrounding shape and starting indentation were sound.

The final Mathlib tree changes 7,553 files by 336,406 insertions and 295,077
deletions. Its 66,654,312-byte diff has SHA-256 digest
`97485be2b6276807b513b39a92276885a6f771bee6f25e6a03e29d57035480da`.
Relative to the immediately preceding validated tree, only
`CategoryTheory/Sites/EqualizerSheafCondition.lean` and
`CategoryTheory/Sites/Sheaf.lean` change: each replaces a premature break after
`∏ᶜ` with the structurally correct `∏ᶜ fun` attachment.

Loaded-run timing outliers in batches 13, 22, 47, 51, and 68 were replayed at
77, 95, 96, 73, and 81 seconds, compared with 82, 102, 113, 84, and 94 seconds
during the full run. A controlled same-files A/B for batch 13 took 77 seconds on
`906e73b` and 77.47 seconds on parent `13e7968`. The final checkpoint therefore
adds no measurable formatter cost; the wider variation is host scheduling and
batch composition rather than a candidate-induced performance regression.

Three independent read-only reviews found the generated notation, ordinary
prefixes, delimited proof bodies, calc layout, GraphQL output, and quantum output
sound. The broad review reconfirmed the high-risk deferred families already in
the queue. A focused proof/comment review found the generic comment-ownership
family now placed first in the queue: continuations after line comments and
trailing comments inside bodies can lose their body indentation. The validated
candidate is clean on diagnostics, builds, intended output, and performance,
but the release tag waits for that one generalized consistency fix.

### 2026-08-09: Final blocker fixes awaiting one validation rerun

The generated-notation fix keeps source-adjacent generated suffixes attached,
gives opening-delimited prefixes one coherent base, and preserves ordinary
prefix applications as structural operands. The delimited-proof fix keeps a
fitting opener with `:= by` and rebases the complete tactic body and closer.
Focused tests cover formatting, preservation, fallback, and idempotency for the
Mathlib reproductions.

Before the ordinary-prefix correction, the complete local gate passed. Fresh
GraphQL formatting batches took 16, 10, and 6 seconds with a 33-second total and
zero output delta. Quantum formatting took 13 seconds, its final build took one
second, and its reviewed five-file output remained calc-only. Exact Mathlib
`v4.32.0` formatting passed all 83 batches at width 100. The first complete run
included a 3,572-second full build and took 6,029 seconds; after refining the
delimiter ownership, all batches passed again and the complete incremental
build took 6 seconds, for a 2,071-second rerun. No formatter-batch timing showed
a performance-regression trend.

The validated Mathlib tree changed 7,553 files by 336,410 insertions and 295,079
deletions. Its diff had SHA-256 digest
`14fc18f3704a0f99ad57ea59d320adee1b39ca8999fab3b744042c950e4d02b7`.
Independent review accepted the generated notation and delimited proof output.
Two reported hanging-lambda examples were byte-identical to the preceding
formatted baseline and remain in the deferred stale-column family above.

A final test audit then exposed the unary-prefix fixture regression and the
missing user-defined generated-prefix application case. The generalized fix
restores the fixture and passes the focused suite, but it postdates the timings,
statistics, digest, and external review in this entry. Those values are retained
as the comparison baseline for the one remaining validation run.

### 2026-08-09: Structural calc relation checkpoint under review

This candidate removes `.calcRelation` and `.calcOperand`, the specialized calc
relation rule, and calc-operand original-tree islands. Each proof-bearing calc
step now contains a `.suffixGroup` header followed by its proof body. The header
retains the parser's complete relation tree and `:=`; `by`, `do`, and nested
`calc` introducers are also attached to that header. The step gives the proof
body a one-level break and the multiline relation header a two-level tail floor.
Consequently the RHS uses ordinary zero-level infix indentation while the proof
body remains one level inside the row. A proofless first term stays structurally
attached to `calc`.

Focused tests cover the logical tree shape, all attached proof introducers,
proofless initials, ordinary and indexed infix relations, multi-operator and
custom relations, application and nested-infix RHS layout, proof-body rebasing,
overflow diagnostics, code preservation, fallback, and idempotency. A generic
paired-delimiter fit correction adds `‖` to the existing opening/closing suffix
delimiter classification; this makes nested infix fitting count the closing
norm delimiter and `:= by` instead of accepting a locally fitting but globally
overflowing line.

The complete local release gate passed: build, suite, development linter,
fixture regeneration and dry checking, self-formatting, code preservation,
actionable overflow, missing-rule, fallback, idempotency, and `git diff --check`
were all clean. No fixture output changed.

Fresh GraphQL and quantum runs used automatic worker counts and no `--jobs`
option. GraphQL's initial build, three formatter batches, and final build took
78, 24/11/5, and 48 seconds. Quantum's cache, initial build, formatter batch,
and final build took 13, 36, 12, and 14 seconds. Every diagnostic and both
post-format builds passed. Each formatted tree is byte-for-byte identical to
its preceding reviewed calc candidate, so the paired-delimiter correction
caused no external churn or performance-regression signal.

The definitive Mathlib run used exact `v4.32.0` commit
`81a5d257c8e410db227a6665ed08f64fea08e997`, width 100, only the 8,264 tracked
files under `Mathlib`, the Lake cache, and automatic formatter workers. Cache
restoration took 24 seconds and restored 8,265 artifacts. The redundant clean
build took 3 seconds. All 83 formatter batches passed preservation,
actionable-overflow, missing-rule, fallback, and idempotency checks. The full
8,654-job post-format build passed in 3,145 seconds; total validation took 5,767
seconds. This is materially faster than the previous 3,960-second build and
6,851-second total, and no formatter batch showed a regression trend.

The candidate Mathlib tree changes 7,553 files by 336,640 insertions and
295,079 deletions and has SHA-256 diff digest
`791f7036e3ff9770ac915f4deecbace29ff8d6ee4e4a5ddf01dde306e0b2bb76`.
Against the verified v0.2.18 pristine calc baseline, the isolated candidate
delta is 125 files, 732 additions, and 694 deletions, with digest
`6f9cdabd0c27b8d882a300e0eb72453a046960b985d277a405b2232e2d53e75d`.

Three independent reviewers covered the complete isolated delta. The ordinary
calc relation, proof indentation, proofless initial, nested sum/product,
subtype, and delimiter changes were sound. Review found four candidate-only
errors: generated notation splits `∂μ`, `∂.pi`, and `#{`, and one delimited
proof detaches `{` from `:= by` without coherent body rebasing. These are the
two blocking families at the top of this document. A later GraphQL review also
found that inherited suffix measurement could charge a declaration signature
for `calc` after the proof had broken following `by`; the generic proof-body
suffix boundary fixed that regression while preserving fitting `by classical`
and `by calc` forms. The final local, GraphQL, and quantum gates passed, and the
checkpoint was committed as `13e7968`. The two Mathlib blocker families are
carried into the final initial-release checkpoint.

### 2026-08-07: Single-boundary infix ownership checkpoint

This checkpoint makes infix break ownership consistent. Ordinary and indexed
infix families own only the boundary before the complete operator; `<|` remains
the sole infix family whose existing `.lowPriorityInfixRhs` group owns a second
discretionary boundary after the operator. The change removes the specialized
Asymptotics relation rule and the generic bar-separated-RHS exception. The
general `.indexedInfix` rule now uses balanced layout, lifts the indentation of
an internally reflowed right operand, and never separates the indexed
operator's closing delimiter from the operator.

Focused coverage checks the boundary ownership of `<|`, every known generated
and named indexed-infix syntax kind, source-break flattening after an indexed
operator, multiline lambda and application right operands, `matches`
alternatives, code preservation, fallback, and idempotency. The dedicated
proposition fixture records the source-level indexed relation and `matches`
shapes. The architecture and style documents now state the same one-boundary
invariant and identify `<|` as the only exception.

The complete local release gate passed: `lake build`, `lake test`, `make lint`,
fixture regeneration and dry checking, self-formatting, preservation,
actionable-overflow, missing-rule, fallback, idempotency, and
`git diff --check` were all clean. Only the dedicated infix fixture changed.

Fresh GraphQL and quantum validation used the automatic worker count and no
`--jobs` option. GraphQL's initial build, three formatter batches, and final
build took 92, 23/11/7, and 67 seconds. Every diagnostic passed, and its six-file
218-insertion, 215-deletion output is byte-for-byte identical to the preceding
accepted checkpoint. Quantum's cache, initial build, formatter, and final build
took 16, 40, 14, and 1 seconds; every diagnostic passed and the formatter
produced no diff. The small timing variation is consistent with prior runs and
shows no performance-regression signal.

The definitive Mathlib run used pristine exact `v4.32.0` commit
`81a5d257c8e410db227a6665ed08f64fea08e997`, the populated Lake cache, width
100, only the 8,264 tracked Lean files under `Mathlib`, and no `--jobs`
override. It intentionally skipped the pre-format build because the input is a
released commit. All 83 formatter batches passed code preservation,
actionable-overflow, missing-rule, fallback, and idempotency checks. The full
post-format build passed all 8,654 jobs in 3,960 seconds; total validation took
6,851 seconds. This is faster than the preceding candidate's 4,046-second build
and 7,163-second total, while batch timings showed no increasing trend.

The resulting Mathlib tree changes 7,552 files by 333,961 insertions and
293,416 deletions, has SHA-256 diff digest
`97ab344110218e6d219041058e1081ce3651cabe3f1864a039ee580d9dd167b7`, and
passes `git diff --check`. Formatting identical pristine inputs with commit
`202ec07` and the candidate isolates 32 files, 73 hunks, 147 additions, and 144
deletions. Every hunk is an indexed-infix leading-operator realignment, an
attached and internally reflowed right operand, or the removal of the
bar-separated `matches` exception.

Three independent reviews covered every isolated hunk and found no logical
line-break or indentation error. They specifically rechecked the previously
flagged reflow cases, nested indexed arrows, multiline lambdas, and the
`matches` bar alignment. Some attached right operands retain deep hanging
indentation or exceed 100 columns, but each begins at the correct logical base
and preserves coherent internal alignment. The complete build emitted only
accepted Mathlib long-line and long-file warnings.

### 2026-08-07: Non-delimited inline proof-body checkpoint

This checkpoint fixes a general protected-layout consistency bug without adding
a line-break rule, syntax regrouping, renderer syntax check, exception, or rule
API. When an inline proof introducer moves horizontally and has no opening
delimiter, its protected body now starts at least one indentation level below
the surrounding output layout base. An existing structural target at that base
or deeper remains authoritative. Proofs whose introducer starts an output line,
and bodies owned by parentheses, constructors, or other opening delimiters,
retain their established anchors.

Focused coverage changes the previously accepted outdented `<| by` shape to:

```lean
theorem pipedProof : True :=
  id <| by
    exact True.intro
```

It also checks code preservation, fallback, and idempotency. The complete local
release gate passed: `lake build`, `lake test`, `make lint`, fixture regeneration
and dry checking, self-formatting, preservation, actionable-overflow,
missing-rule, fallback, idempotency, and `git diff --check` were all clean. No
fixture output changed.

Fresh GraphQL and quantum validation used the automatic worker count and no
`--jobs` option. Both projects passed every formatter batch, preservation and
idempotency checks, and their final builds. GraphQL's build, three formatter
batches, and final build took 76, 20/10/6, and 59 seconds. Its six-file output
is byte-for-byte identical to the preceding accepted checkpoint. Quantum's
cache, build, formatter, and final build took 23, 36, 12, and 1 seconds and
produced no diff. These timings are faster than the preceding baselines and
show no performance-regression signal.

The definitive Mathlib run used pristine exact `v4.32.0` commit
`81a5d257c8e410db227a6665ed08f64fea08e997`, the populated Lake cache, width
100, only the 8,264 tracked Lean files under `Mathlib`, and no `--jobs`
override. It intentionally skipped the pre-format build because the input is a
released commit. All 83 formatter batches passed code preservation,
actionable-overflow, missing-rule, fallback, and idempotency checks. The full
post-format build then passed all 8,654 jobs in 2,385 seconds; total validation
took 4,982 seconds. Batch timings had isolated outliers comparable to prior
runs, immediately returned to their usual range, and showed no increasing
trend.

The resulting Mathlib tree changes 7,552 files by 333,956 insertions and
293,423 deletions, has SHA-256 diff digest
`faa38aefdab046c4820a62775c6898a70a4c97e8f5833bcf2de4b427031aa9a6`, and
passes `git diff --check`. Formatting identical pristine inputs with the
released and current binaries isolates one true checkpoint delta: the three
tactic lines below `<| by` in
`Mathlib/AlgebraicGeometry/ProjectiveSpectrum/Basic.lean` move from the
surrounding expression base to one level below it. The 262-file delta from the
rejected broad implementation is gone.

Three independent reviews found no logical formatting error. One reviewed the
exact Mathlib delta, one audited all 1,503 tracked `<| by` line endings and a
96-case broad sample, and one verified that the five previously sensitive
parenthesized, constructor, application, and delimiter representatives are
byte-for-byte unchanged. The complete build emitted only accepted Mathlib
long-line and long-file warnings.

### Attached structure-field body checkpoint

This checkpoint fixes an existing line-break consistency bug for structure
fields. Declarations and local bindings already use `delimiterValueBreak?` to
keep a `by` or `do` value introducer attached to `:=`; structure fields
duplicated older delimiter logic and always offered a break after `:=`. The
structure-field rule now reuses the same helper, so fields format as
`field := by` or `field := do` and the body receives its normal indentation.
The change adds no rule API, syntax grouping, renderer syntax check, exception,
or specialized rule.

Focused coverage uses a narrow-width nested, multi-field structure value. It
checks that a proof introducer stays attached, its `cases` body remains
properly nested, an ordinary long field value can still break after `:=`, and
formatting preserves code without fallback and is idempotent. The normative
style documentation now records the same attachment rule.

The complete local release gate passed: `lake build`, `lake test`, `make lint`,
fixture regeneration and dry checking, self-formatting, preservation,
actionable-overflow, missing-rule, fallback, idempotency, and
`git diff --check` were all clean.

Fresh GraphQL and quantum validation used the automatic worker count and no
`--jobs` option. Both projects passed their initial build, every formatter
batch, preservation and idempotency checks, and the final build. GraphQL
formatted 280 Lean files in three batches, rebuilt in 62 seconds, and retained
the preceding checkpoint's six-file, 218-insertion, 215-deletion diff exactly.
Quantum restored its Lake cache, built in 42 seconds, formatted in 15 seconds,
rebuilt in 3 seconds, and produced no diff. The combined run took 330 seconds,
down from 391 seconds at the preceding checkpoint.

The definitive Mathlib run used a pristine checkout of exact `v4.32.0` commit
`81a5d257c8e410db227a6665ed08f64fea08e997`, the populated Lake cache, width
100, only the 8,264 tracked Lean files under `Mathlib`, and no `--jobs`
override. The initial and final builds each passed all 8,654 jobs in 3,705 and
3,706 seconds. All 83 formatter batches passed code preservation,
actionable-overflow, missing-rule, fallback, and idempotency checks. The full
validation took 11,109 seconds. The approximately 3,698-second formatter phase
is 4.3 percent above the preceding 3,546-second sweep, within observed
run-to-run and logging variance; batch times showed no increasing trend, and
GraphQL was faster. There is no performance-regression signal.

The resulting Mathlib tree changes 7,552 files by 333,953 insertions and
293,420 deletions, has SHA-256 diff digest
`d4f8006fd6d22db911f1ada4f96171a282aad5baf39ff7b8f64d780fb04cddc2`,
and passes `git diff --check`. A raw comparison with the preceding reused
checkout included four files whose differences came from its intermediate
formatting history. Reformatting identical pristine inputs with the committed
and current binaries isolated the true checkpoint delta: 32 files, 63 hunks,
69 `:= by` or `:= do` attachments, 603 insertions, and 673 deletions.

Four independent reviews covered disjoint file sets and a complete global
scan. They found no incorrect or missing break, stranded comment, indentation
regression, or out-of-scope change. Nested tactics, `match`, `if`, loops,
quotations, exception handlers, constructors, and multiline strings retain
their relative indentation. Two expressions now fit on one line at 100
columns because the corrected field-body base gives them more room; both are
valid direct consequences of the fix. Long indivisible lines begin at the
correct structural base. The full build emitted only accepted Mathlib
long-line and long-file warnings.

The initially considered `<| by`, `(by`, and structure-field `:= by` examples
did not share one clean implementation boundary. This checkpoint intentionally
handled only structure fields; the later non-delimited proof-body checkpoint
handled the moved `<| by` case independently.

### Trailing proof-argument ownership checkpoint

This checkpoint fixes nested elimination layout inside a direct proof argument
without adding a line-break rule, renderer syntax check, exception, or rule
API. Syntax regrouping may expose the complete final proof argument of a
non-owner tactic through transparent parser or local-declaration wrappers. Its
introducer remains attached to the argument, so `:= by` stays on one line when
it fits, while the existing elimination owner gives `cases` and `induction`
alternative bodies their normal two-level indentation. A tactic shell, a
nested term owner, or a later token-bearing sibling stops the traversal.

The GraphQL review caught the important ownership detail. Detaching `by` from
`:=` made the following `cases` appear too far right. Keeping `:= by` together
establishes the proof body's correct base, after which the new indentation is
right. The corrected output has this shape:

```lean
  have hprefixCollect :
      LongResultType := by
    cases prefixFields with
    | nil =>
        contradiction
    | cons firstPrefix restPrefix =>
        simpa using ...
```

An initially broader recursive search found a `by` inside a nested `match` arm
and treated it as the surrounding `exact` tactic's direct proof argument. In
`Data/Seq/Parallel.lean` that moved a `have` out of the arm, changed how Lean
reparsed the intermediate text, and correctly triggered preservation fallback.
The final implementation instead follows only direct proof arguments and
declaration envelopes. Focused coverage now checks nested `have` and
`suffices`, a previously detached `:= by`, the nested-`match` boundary, code
preservation, fallback, and idempotency.

The complete local release gate passed: `lake build`, `lake test`, `make lint`,
fixture regeneration and dry checking, self-formatting, preservation,
actionable-overflow, missing-rule, fallback, idempotency, and
`git diff --check` were all clean.

Fresh GraphQL and quantum validation used the automatic worker count and no
`--jobs` option. Both projects passed their initial build, every formatter
batch, preservation and idempotency checks, and the final build. GraphQL
formatted 280 Lean files in three batches, rebuilt successfully, and changed
six files by 218 insertions and 215 deletions. Quantum restored its Lake cache,
formatted cleanly in 18 seconds, rebuilt in 3 seconds, and produced no diff.
The combined run took 391 seconds. Its timing profile is consistent with the
preceding checkpoints and shows no performance regression.

The definitive Mathlib run used exact `v4.32.0` commit
`81a5d257c8e410db227a6665ed08f64fea08e997`, the Lake cache, width 100, only
the 8,264 tracked Lean files under `Mathlib`, and no `--jobs` override. All 83
formatter batches passed code preservation, actionable-overflow, missing-rule,
fallback, and idempotency checks. Most batches took 33 to 61 seconds; the
historically heavier batch 47 took 70 seconds, and batch 22 took 64 seconds
after the invalid broad implementation had taken 109 seconds. There was no
increasing timing trend, worker failure, or memory pressure. The complete
formatted-tree build passed all 8,654 jobs in 7 seconds, and the definitive
validation took 3,546 seconds.

The Mathlib tree changes 7,553 files by 334,303 insertions and 293,696
deletions, has SHA-256 diff digest
`f34d2c9cd5e513ab11f41014b82e394fd03c97f83730d82eba4e7e2678ee1971`,
and passes `git diff --check`. Relative to the preceding validated formatting
checkpoint, this change affects 88 files by 632 insertions and 602 deletions.
Review confirms the intended nested `cases` and `induction` body movement in
representatives such as `Logic/Relation.lean` and
`Computability/AkraBazzi/GrowsPolynomially.lean`. The build emitted only the
accepted Mathlib long-line and long-file warnings; no warning identified a new
logical indentation error from this checkpoint.

The review also separated broader protected-argument and nested-alternative
ownership from this direct proof-argument fix. Later checkpoints resolved the
structure-field and non-delimited `<| by` cases; surviving ownership families
are maintained in the queue at the top of this document.

### Multiline-original overflow checkpoint

The syntax tree and line-break rule were already correct for the remaining
`RuleOfSigns`-style examples: an induction alternative exposed its protected
proof body directly, and the shared elimination rule assigned that body two
indentation levels. The stale indentation came from renderer candidate
selection instead. When moving an original-layout body made one of its
unbreakable lines exceed width 100, the source-break candidate was rejected.
The following flat probe could not actually remove the body's physical source
break, but it was still accepted and emitted that break at its old source
column.

The renderer now handles that general inconsistency in the existing
`useExistingBreaks` path. If a source-break candidate fails its fit check and
the segment contains a multiline original-layout emission, it applies the
rule layout rather than accepting a flat probe that cannot flatten the child.
This adds no syntax or token knowledge to the renderer, no new rule API, and no
specialized elimination rule. Focused coverage checks formatting, code
preservation, and idempotency when required alternative-body indentation turns
an otherwise fitting protected line into an accepted overlong line.

The complete local release gate passed: `lake build`, `lake test`, `make lint`,
fixture regeneration and dry checking, self-formatting, preservation,
actionable-overflow, missing-rule, fallback, idempotency, and `git diff --check`
were all clean. The formatter and test sources required no generated formatting
changes.

Fresh GraphQL and quantum validation used the automatic worker count and passed
without exceptions, idempotency failures, build failures, or formatting diffs.
GraphQL's clean build took 93 seconds, its formatter batches took 17, 9, and 7
seconds, and its up-to-date post-format build took less than one second. Quantum
restored its cache in 14 seconds, built in 48 seconds, formatted in 17 seconds,
and rebuilt in 3 seconds. The combined run took 289 seconds. These timings are
within ordinary run-to-run variance of the preceding checkpoint and show no
performance trend.

The exact Mathlib `v4.32.0` commit
`81a5d257c8e410db227a6665ed08f64fea08e997` was validated at width 100 using the
existing Lake cache, only the 8,264 tracked Lean files under `Mathlib`, and no
`--jobs` override. All 83 formatter batches passed code preservation,
actionable-overflow, missing-rule, fallback, and idempotency checks. The
formatter phase and script overhead took approximately 3,545 seconds, with
most batches between 33 and 60 seconds, one isolated 74-second batch, and no
increasing timing or memory-pressure trend. The full post-format build passed
all 8,654 targets in 3,880 seconds; the complete validation took 7,425 seconds.
The formatted tree changes 7,553 files by 333,747 insertions and 293,170
deletions, has SHA-256 diff digest
`cd35eb89b1436be0989ae7b8de6bdfe6023f5f503d9f99435d18f0353d8c7d13`, and
passes `git diff --check`. Relative to the preceding documented output, the
file count is unchanged and both insertions and deletions increase by 2,578,
consistent with moving protected source lines to their structural columns.

The full build emitted only accepted Mathlib long-line and long-file warnings.
In particular, the corrected protected bodies in
`Algebra/Polynomial/RuleOfSigns.lean` and
`Algebra/Homology/DerivedCategory/Ext/MapBijective.lean` build cleanly even
where required indentation makes an indivisible line longer than 100 columns.

Five independent reviews covered disjoint Mathlib domains plus a global pattern
scan. They found no checkpoint-specific regression: direct alternative bodies
now consistently use the required four-column offset, including newly overlong
lines in `Algebra/BigOperators/Fin.lean` and
`FieldTheory/AbelRuffini.lean`, and no structural suffix detached as a result of
this renderer change. The review separated protected alternatives, line-comment
continuations, trailing `where`, comment-forced `<|`, peer staircases, and
token-relative continuations into independent ownership families. Any
surviving items are maintained in the queue above.

### Tactic-sequence, identifier-clause, and renderer consistency checkpoint

The current working tree was validated against exact Mathlib `v4.32.0` commit
`81a5d257c8e410db227a6665ed08f64fea08e997`. The run used the Lake cache,
selected all 8,264 tracked Lean files under `Mathlib`, set width 100, and did
not pass `--jobs`. All 83 formatter batches passed code preservation,
actionable-overflow, missing-rule, fallback, and idempotency checks. The first
full post-format build passed all 8,654 targets in 3,724 seconds. Its resumed
validation invocation took 4,079 seconds, with no increasing timing trend,
worker failure, or memory pressure. After the peer-flow correction described
below, the final formatter reran all 83 batches in 3,434 seconds and the
incremental 8,654-target build passed in 7 seconds. The final tree changes 7,553
files by 331,169 insertions and 290,592 deletions, and `git diff --check`
passes.

Fresh `graphql-lean` and `quantum-computing-lean` validation also passed with
the automatic worker count. GraphQL's clean build took 85 seconds, its three
formatter batches took 17, 9, and 8 seconds, and its post-format build took 67
seconds. Twenty files changed by 449 insertions and 448 deletions; review found
the `cases`, named-discriminant, ordinary-induction, and sibling-tactic changes
logically consistent. Quantum restored its cache in 14 seconds, built in 45
seconds, formatted in 15 seconds, rebuilt in 3 seconds, and produced no diff.
The combined fresh external run took 340 seconds and reported no formatter
exception or performance trend. After the peer-flow correction, all three
GraphQL batches and its incremental build passed in 38 seconds; quantum
formatting and its complete cached build passed in 20 seconds with no diff.

This checkpoint repairs five general consistency gaps without adding a rule
API. A same-indented tactic continuation that Lean stores inside a preceding
non-owner tactic returns to the surrounding tactic sequence, so a preceding
`classical` or ordinary sibling no longer changes elimination-body indentation.
Induction headers now own flat `generalizing` identifier clauses, giving every
name one continuation base while keeping `with` attached. Generic flow
measurement counts comment trivia immediately before the next candidate break.
Comment-boundary rendering distinguishes authored continuations from comments
aligned with the following tree. Overflow diagnostics now recognize an
indivisible qualified line head and an unchanged protected line shifted by
required structural indentation.

Six independent reviews covered non-overlapping Mathlib domains. They found no
new direct `cases`, named-discriminant, `with`, or ordinary `induction`
regression. The GraphQL diff review did find that recursively nested
`generalizing` names formed a staircase when more than one internal boundary
broke. Flattening those names into semantic peers makes every continuation use
the same base; focused preservation and idempotency coverage, GraphQL, quantum,
and the final 83-batch Mathlib rerun all pass. The reviews also confirmed that
the corpus still has actionable families beyond this checkpoint:

- protected or nested elimination bodies can retain the alternative's base,
  including `Algebra/Polynomial/RuleOfSigns.lean:308` and
  `CategoryTheory/Action/Monoidal.lean:293`;
- standalone comments can detach to column zero or add an extra body level,
  including `Geometry/RingedSpace/Stalks.lean:62`,
  `Tactic/Linter/DocString.lean:168`, and
  `Analysis/Normed/Group/Seminorm.lean:61`;
- low-priority `<|` can occupy a line apart from a comment-forced operand, as in
  `MeasureTheory/Measure/Haar/InnerProductSpace.lean:179`;
- a trailing declaration `where` can detach at the wrong base, represented by
  `MeasureTheory/Measure/Stieltjes.lean:524`;
- protected proof, declaration-binder, and expression continuations can retain
  stale token-relative columns, represented by
  `Tactic/TacticAnalysis.lean:120` and
  `RingTheory/PrincipalIdealDomain.lean:120`.

Two targeted reviews after the final build found no staircase,
detached `with`, named-discriminant regression, or direct elimination-body
error. Both independently isolated protected or nested alternative ownership
as a separate family, which later tactic-ownership checkpoints addressed
without mixing in comment, `<|`, `where`, or peer-continuation behavior.

### Ordinary induction and tactic-context checkpoint

The post-rebase baseline used exact Mathlib `v4.32.0` commit
`81a5d257c8e410db227a6665ed08f64fea08e997`, the Lake cache, width 100, only
the `Mathlib` directory, and no formatter-jobs override. All 83 batches retained
the previous checkpoint's zero code-change, missing-rule, fallback, and
idempotency counts. Its seven known actionable-width reports were unchanged.
The baseline output changed 7,530 files by 315,024 insertions and 274,841
deletions. Its complete post-format build passed all 8,654 jobs in 4,636
seconds; this was slower than the prior 3,706-second checkpoint build, while
formatter batch times remained stable.

The current checkpoint makes ordinary `induction` a structural layout owner,
groups its complete `... with` header separately from its alternatives, and
groups each parser-owned alternative header separately from its `=>` body.
The shared elimination-owner rule then gives both `cases` and `induction`
bodies two indentation levels without checking token text in the line-break
rule. Arrowless alternatives remain outer tactic-sequence peers because Lean
does not parse them as body owners.

The first full review found that an induction's default tactic and following
explicit alternatives were still grouped together. The shared default-tactic
split now isolates only that default body: it receives the two-level body
indent, while later `|` alternatives return to the induction base. Focused
coverage and targeted formatting/builds include
`Computability/TuringMachine/Config.lean`,
`Computability/TuringMachine/StackTuringMachine.lean`,
`Analysis/Calculus/ContDiff/Basic.lean`, and `Data/Nat/Digits/Defs.lean`.

The same run exposed a missing rule for `Congr!.congr!`. Its declared name does
not contain a `Tactic` namespace even though Lean places it directly in a tactic
sequence. Tactic entries are now annotated from that parser context, and the
original-layout classifier trusts the structural annotation. This avoids a
named exception and covers other project tactics with arbitrary namespaces.
Because protected tactic text is emitted without internal rule boundaries, it
now receives the same unbreakable-overflow exemption as protected proof text.
That makes overflow diagnostics consistent with renderer ownership instead of
hiding a formatter breakpoint that could actually be used.

The definitive final-binary sweep passed all 83 batches in 3,151 seconds with
zero code-change, actionable-overflow, missing-rule, fallback, and idempotency
counts. Batch times were usually 31 to 56 seconds; the historically heavy batch
47 completed in 62 seconds. There was no worker failure, memory pressure, or
worsening timing trend. The final tree changes 7,551 files by 329,544
insertions and 288,982 deletions, has SHA-256 diff digest
`acd99e8d1e56bb2b9078ff2b40672366a7b56c92c4842abcf607e830d75435fb`,
and passes `git diff --check`.

A complete post-format build before the reviewer correction passed all 8,654
jobs in 3,716 seconds. After correcting the default-alternative grouping, a
focused 1,998-job build and then a complete incremental 8,654-job build passed
on the definitive tree. Build output contained only accepted Mathlib long-line
and long-file warnings.

Independent review found no further regression in ordinary `=>` bodies,
arrowless alternatives, nested induction, comments, delimiters, or custom
tactics. Three separate ownership families remain intentionally deferred:

- the long protected branch in `RingTheory/PowerSeries/Binomial.lean:91`;
- nested `cases` beneath an outer protected alternative, represented by
  `Computability/AkraBazzi/GrowsPolynomially.lean:279`;
- some `induction ... using` headers, represented by
  `Analysis/Meromorphic/Divisor.lean:333` and
  `CategoryTheory/Filtered/Basic.lean:229`.

### Direct `cases` body checkpoint through `d386d69`

This checkpoint narrows the Mathlib `lemma` original-layout exception by one
existing syntax fact: a lemma remains protected only when it contains no
structurally rendered tactic layout owner.
It does not add a rule API, inspect tokens in a line-break rule, or teach the
renderer about commands or tactics. Leaf lemma proofs remain complete source
islands; a lemma containing transparent `cases` or induction alternatives
exposes the existing owner so its direct children can use that owner's rule.
An original-layout owner such as `calc` remains part of the protected lemma and
cannot open its parent island.

Focused coverage verifies that a direct multiline `cases` body is indented two
levels below its alternative, formatting preserves code, and a second pass is
stable. Architecture coverage separately verifies both sides of the exception:
a leaf lemma remains a `.proofLemma` island, while a lemma with a structural
proof owner does not.

The first complete Mathlib pass exposed one over-broad part of the ownership
condition. A lemma containing `calc` was opened even though `calc` remained an
original-layout island, which caused a preservation fallback around a nested
`#adaptation_note`. Commit `d386d69` now requires a transparent structural owner
and does not let a protected owner open its parent. The focused reproduction,
local release gate, and the affected Mathlib batch all pass without fallback.

The complete local release gate passed: build, tests, linter, fixture update and
dry check, self-formatting, preservation, overflow, missing-rule, and idempotency
checks were all clean. A fresh GraphQL and quantum validation passed in 305
seconds with no formatting changes, exceptions, build failures, or worsening
batch-time trend.

At width 100, eight initially affected Mathlib modules passed preservation and
idempotency formatting, and their combined 3,020-target build completed
successfully. Direct
`cases` bodies in `Algebra/CharP/MixedCharZero.lean`,
`Analysis/Meromorphic/Order.lean`, `Data/ENat/Lattice.lean`,
`Data/EReal/Operations.lean`, and
`LinearAlgebra/Projectivization/Cardinality.lean` now use the intended two-level
body indentation. The build emitted only accepted 100-column linter warnings;
formatter diagnostics found no actionable overflow.

The complete Mathlib `v4.32.0` validation used the Lake cache, line width 100,
only the `Mathlib` directory, and no formatter-jobs override. The clean
pre-format build passed all 8,654 jobs in 5 seconds. All 83 formatter batches
were covered with the final formatter; code preservation, missing-rule,
fallback, and idempotency counts were zero. The seven previously documented
actionable-width diagnostics were unchanged. The formatted tree changed 7,538
files by 315,476 insertions and 275,279 deletions, and `git diff --check` passed.
The full post-format build passed all 8,654 jobs in 3,706 seconds. After batches
1-24 were rerun to ensure that every file used `d386d69`, a complete incremental
build checked the current tree successfully, rebuilding or replaying 179 stale
targets in 18 seconds. Batch times remained broadly stable, normally 30 to 60
seconds, without worker failure or memory pressure.

Independent review then isolated one owned-alternative family. A multiline
body parsed after `=>` can remain only one level below its alternative when its
protected source layout is reached through the parser's `null` wrapper or a
protected `induction` shell. The structural fix groups the pattern and `=>` as
one suffix header, exposes the existing proof body directly, and applies the
shared two-level indentation at that semantic boundary. It also groups an
`induction ... with` header separately from its alternatives and routes that
owner through the same elimination-layout rule as `cases`. The line-break rule
no longer checks the `=>` token, and no renderer behavior or rule API changes.

Focused Mathlib formatting and builds passed for ordinary induction bodies in
`Combinatorics/Derangements/Finite.lean` and
`Combinatorics/SimpleGraph/Walk/Operations.lean`. The long protected body in
`RingTheory/PowerSeries/Binomial.lean:91` and the `induction ... using` shape in
`Analysis/Meromorphic/Divisor.lean:333` remain unchanged; they are separate
protected-layout and header-ownership follow-ups rather than extensions of this
checkpoint.

The superficially similar arrowless alternatives in
`Combinatorics/SimpleGraph/Walk/Operations.lean:360,853,862` are not body owners.
Lean parses their following tactics as peers in the outer tactic sequence;
indentation beneath the alternative leaves its goal unsolved and produces an
unexpected command. They must remain at the sequence indentation unless the
author writes `=>`.

This checkpoint also deliberately does not reach through an outer structural
owner. Nested `cases` bodies under induction alternatives remain
source-preserved in `RingTheory/Etale/QuasiFinite.lean` and
`Tactic/ComputeAsymptotics/Multiseries/Monomial/Basic.lean`. That is a distinct
induction-alternative ownership family and should be the next review target, not
an extension of this condition. Two previously documented `calc` shared-base
examples also remain in
`Analysis/Complex/ValueDistribution/CharacteristicFunction.lean:108` and
`Analysis/InnerProductSpace/Projection/Basic.lean:468`. No detached comments or
extension-tactic regressions were found.

### Structural `cases` checkpoint after `c9f4e8c`

The structural `cases` change after `c9f4e8c` groups a direct target collection,
the complete header, and the outer alternatives as separate semantic layout
owners. This makes alternative boundaries structural without forcing optional
wrapping inside the header. Target collections reuse the existing discriminant
flow, so multiple targets and named discriminants receive the same continuation
and `:` alignment as `match`. Direct role classification excludes proofs,
`using` clauses, and nested tactics; the line-break rule does not search token
text or descendants. No renderer behavior or rule API changed.

On GraphQL's `FieldGroup/PrefixAppend.lean`, formatter time fell from more than
ten hours to 31.7 seconds. A fresh GraphQL validation passed its clean build,
all three formatter batches, and its post-format build in 228 seconds. The
formatted tree changed 26 files by 183 insertions and 201 deletions. Independent
review found the `cases ... with` headers, named discriminants, alternatives,
and nested bodies logically consistent. Quantum validation passed in 163
seconds and produced no formatting diff. Both projects had zero preservation,
overflow, missing-rule, fallback, and idempotency exceptions.

The complete Mathlib `v4.32.0` audit used commit
`81a5d257c8e410db227a6665ed08f64fea08e997`, the Lake cache, line width 100,
only the `Mathlib` directory, and no `--jobs` override. The cache restored 8,451
artifacts with 188 already present, and the clean pre-format build passed all
8,654 jobs in 5 seconds. All 83 formatter batches were covered. Code
preservation, missing-rule, fallback, and idempotency counts were zero. The
formatted tree changed 7,527 files by 314,094 insertions and 273,931 deletions,
and `git diff --check` passed. The post-format build passed all 8,654 jobs in
4,394 seconds. Most formatter batches took roughly 30 to 55 seconds; isolated
heavy batches took roughly 90 to 100 seconds without an increasing trend,
worker failure, or memory pressure.

Seven actionable-width diagnostics remain. They are checkpoint-known or
reproduce with the committed `c9f4e8c` formatter and are therefore independent
of this `cases` change:

- `AlgebraicGeometry/Gluing.lean:119`, 101 columns;
- `AlgebraicGeometry/StructureSheaf.lean:426`, 104 columns;
- `Analysis/CStarAlgebra/GelfandNaimarkSegal.lean:116`, 101 columns;
- `NumberTheory/Bernoulli.lean:285`, 101 columns;
- `NumberTheory/Bernoulli.lean:388`, 103 columns;
- `NumberTheory/Bernoulli.lean:395`, 102 columns;
- `Tactic/GCongr/Core.lean:819`, 104 columns.

Focused tests cover plain, default-only, default-plus-explicit, named,
proof-bearing, nested, `using`, and multiple-target `cases` forms, including
preservation and idempotency. Independent review found no regression in the
changed named-discriminant, `using`, `with`, explicit-alternative, or
default-alternative layouts. A broad review reproduced only the existing
protected-body and standalone-comment families recorded below. A targeted
review also found that source-preserved `cases` branch bodies can remain at the
alternative's indentation; this predates the header change and was deliberately
excluded from the structural-header checkpoint. That protected-body family is
maintained in the queue above. The seven width shapes remained separate
generalized consistency work rather than `cases` exceptions.

### Validation through `21b19ae`

The renderer-side comment boundary work is committed through `21b19ae` in
three independent changes: `6882d77` handles comment-forced tree boundaries,
`66621fc` preserves the relative indentation of an inline multiline block
comment, and `21b19ae` rebases inline syntax-comment continuations when their
surrounding original-layout tree moves. These changes keep comments as source
trivia. They add neither comment nodes to the syntax tree nor a new rule API.

Fresh GraphQL and quantum validation passed at `21b19ae`. GraphQL formatted 264
files with automatic worker count, zero exceptions, and a clean post-format
build. Its optional cache command was unavailable; the initial build, three
formatter batches, and final build took 59, 13/10/7, and 24 seconds. Five files
changed by 36 insertions and 18 deletions, only at the intended multiline
parenthesized proof-argument boundary. Quantum formatted 21 files with zero
exceptions and no diff; its cache, initial build, formatter, and final build took
14, 42, 16, and 3 seconds. The combined run, including building leanfmt and fresh
clones, took 281 seconds. The syntax-comment continuation refinement also passed
the complete local gate and focused width-100 Mathlib checks. Five affected
Mathlib modules built successfully in 19 seconds.

A complete Mathlib `v4.32.0` run used commit
`81a5d257c8e410db227a6665ed08f64fea08e997`, selected all 8,264 tracked Lean
files under `Mathlib`, used line width 100 and the automatic worker count, and
restored the Lake cache. All 83 formatter batches were covered. Code
preservation, missing-rule, fallback, and idempotency counts were zero. Four
overflow-only diagnostics remain accepted: the 101-column qualified projection
in `AlgebraicGeometry/Gluing.lean:119`, the 104-column protected proof line in
`AlgebraicGeometry/StructureSheaf.lean:426`, and authored trailing comments in
`Tactic/FBinop.lean:225` and `Tactic/GCongr/Core.lean:820`. The complete
post-format build passed all 8,654 jobs in 3,863 seconds. The formatted tree
changed 7,524 files with 311,282 insertions and 271,209 deletions, and
`git diff --check` passed.

The isolated slow geometry/manifold batch was not a regression. On the same
clean 100-file batch, `21b19ae` took 47.40 seconds and an experimental comment
generalization took 46.39 seconds. Focused comparisons against `6f705af` also
showed equivalent formatter time for the three dominant files. No increasing
batch trend, worker failure, or memory pressure was observed.

### Rejected standalone-comment generalization

An experiment removed `preserveNextStandaloneCommentIndent` and attempted to
derive standalone-comment indentation at every pending renderer boundary from
the preceding token's source column and the pending indentation. The complete
83-batch width-100 Mathlib formatter pass remained preservation- and
idempotency-clean, but comparison with the preceding full output changed 33
files and was not visually consistent. It correctly restored several proof-body
comments, including the examples in `Analysis/Calculus/Deriv/Prod.lean` and
`Analysis/LocallyConvex/WithSeminorms.lean`, but it also over-indented peer
comments in inductive declarations, parameter groups, structures, and command
bodies. A continued declaration-result comment in
`CategoryTheory/Limits/HasLimits.lean` could still move to column zero.
Three independent reviews classified the 33 changed files as 20 wholly correct,
9 wholly incorrect, 2 mixed, and 2 ambiguous.

The experiment also initially suppressed the established relocation of a line
comment beside an unchanged `(` or declaration `:`. Giving
`movePendingCommentAfterToken` priority fixed that regression and received
focused coverage, but did not resolve the mixed 33-file indentation result. The
entire experiment was therefore backed out and was not committed. The branch is
clean at `21b19ae`.

The failed attempt establishes a useful constraint for the next fix: a token's
source column does not reveal whether its containing layout moved. A clean
general solution should translate a standalone comment through the existing
`sourceLayoutBaseColumn` and `outputLayoutBaseColumn` anchors before comparing
it with the pending structural indentation. This can distinguish an unchanged
peer comment from a comment inside a body whose parent moved, without checking
Lean syntax kinds or adding a rule API. Before implementation, focused tests
must cover all four shapes: a trailing proof comment, an inductive peer comment,
a moved function-body comment, and comment relocation beside stationary and
moved `(` and `:` tokens.

### Comment-created tree boundaries after `6f705af`

The working tree now treats line comments and multiline block comments as
source trivia with intrinsic, non-removable breaks. The renderer establishes a
generic tree boundary from that break, rebases the complete comment and its
following token to the surrounding tree indentation, and may move the leading
comment beside the preceding token when that complete line fits. Comments are
not added to the syntax tree, and no syntax-specific line-break rule or new rule
API was introduced. Single-line block comments remain inline when the complete
tree fits; ordinary width pressure may break the enclosing tree or the boundary
between the comment and its following token.

The complete local gate passed, including build, tests, development linter,
fixture regeneration and dry check, self-formatting, code preservation,
actionable overflow, missing-rule, fallback, idempotency, and the final
`git diff --check`. A fresh targeted validation at Mathlib `v4.32.0` passed for
`Mathlib/Algebra/Module/Projective.lean`, and the formatted module rebuilt
successfully. The detached result comment now formats as
`: -- then P is projective.` with the result type indented below the comment.
The build reported only the accepted long proof line at line 156. A full
Mathlib rerun has not yet been performed for this working-tree change.

Fresh combined validation also passed for `graphql-lean` and
`quantum-computing-lean` without a `--jobs` override. GraphQL's optional cache
was unavailable; its uncached initial build took 71 seconds, formatter batches
took 13, 13, and 7 seconds, and its post-format build took 27 seconds. Five
files changed by 36 insertions and 18 deletions, solely to move multiline
parenthesized proof arguments onto their ordinary application continuation;
the proof bodies and token sequence were unchanged. Quantum's cache, initial
build, formatter batch, and post-format build took 15, 47, 18, and 3 seconds,
and its formatted tree had no diff. Both projects reported zero code-change,
overflow, missing-rule, fallback, and idempotency exceptions.

The combined run took 296 seconds, 39 seconds above the prior 257-second
baseline. Formatter work increased only from 30 to 33 seconds for GraphQL and
from 16 to 18 seconds for Quantum. The remaining increase was build, clone, or
local Lake-package setup variance, with no increasing batch trend, worker
failure, or memory pressure.

### Working-tree validation after `61d472a`

Four low-risk consistency fixes were validated in the working tree after
`61d472a`. Core postfix indexing and generated prefix-index syntax now use one
delimiter-shape rule: breaks are available inside the index and after the
closing delimiter, but never before the closing `]`. Core `#[...]` arrays now
retain balanced existing layouts for both singleton and multi-item forms. The
opening-delimiter suffix classifier now implements its stated suffix semantics,
so a prefixed opener such as `#[` does not lose the structural break before an
item beginning with `(`. Authored trailing line comments now remain attached to
their code even when the complete line exceeds the configured width; this
removes width-dependent comment relocation from the renderer and leaves comment
attachment to the parsed/source structure. None of these changes adds a rule
API or syntax decision to the renderer.

The complete local gate passed: build, tests, development linter, fixture
regeneration and dry check, self-formatting, code preservation, actionable
overflow, missing-rule, fallback, idempotency, and `git diff --check`. Fresh
external validation then passed for `graphql-lean` and
`quantum-computing-lean` without a `--jobs` override. In the final fresh run,
GraphQL's initial build took 57 seconds, its formatter batches took 11, 12, and
7 seconds, and its post-format build took 24 seconds. Five files changed only
at the already intended parenthesized multiline proof-argument boundary.
Quantum's cache, initial build, formatting, and post-format build took 16, 42,
16, and 3 seconds respectively and produced no diff. The combined run took 257
seconds.

The full Mathlib run used the exact `v4.32.0` commit
`81a5d257c8e410db227a6665ed08f64fea08e997`, selected the 8,264 tracked Lean
files under `Mathlib`, set the line width to 100, and did not pass `--jobs`.
The Lake cache restored 7,970 artifacts in 11 seconds, and the cached
pre-format build passed all 8,654 jobs in 5 seconds. All 83 formatter batches
were exercised. Code preservation, missing-rule, fallback, and idempotency
counts were zero throughout.

Four batches required acceptance of overflow-only diagnostics. Two are the
previously recorded correctly indented lines in
`Mathlib/AlgebraicGeometry/Gluing.lean:119` and
`Mathlib/AlgebraicGeometry/StructureSheaf.lean:426`. Two are the expected
consequence of preserving authored trailing comments:
`Mathlib/Tactic/FBinop.lean:225` is 101 columns and
`Mathlib/Tactic/GCongr/Core.lean:820` is 104 columns. Both comments remain
attached to the code they qualify and begin at the correct logical
indentation. Formatter batches were generally 31 to 59 seconds, with isolated
87-, 95-, 90-, and 76-second outliers at batches 13, 22, 51, and 63. There was
no increasing trend, worker failure, or memory pressure.

The first complete post-format build passed all 8,654 jobs in 3,351 seconds.
After the array fixes, a complete 83-batch rerun and complete build also passed.
The final reviewed executable then exercised all 83 batches once more from
batch 1 without repeating the already clean pre-format build. Formatter batches
took 3,071 seconds in aggregate, with a 35-second median, 45-second 90th
percentile, and 58-second maximum at the known heavy batch 47. There was no
increasing trend, worker failure, or memory pressure. The complete post-format
build passed in 6 seconds, and the final invocation took 3,090 seconds.

The final formatted tree changed 7,524 files, with 310,983 insertions and
270,934 deletions, and `git diff --check` passed. The indexed `MDiff[...]`
representative keeps its closing bracket attached and gives the following
operand its ordinary continuation. The three semantic `shake: keep` import
comments remain attached to their imports. The multi-item `#[...]` in
`Mathlib/Tactic/CategoryTheory/Elementwise.lean:159` now breaks after the
prefixed opener, indents its first tuple item, and closes at the array base.

Three independent final reviews covered the implementation, targeted delimiter
and comment cases, and a broad Mathlib sample. The targeted review found no
issue. The broad review confirmed the new array and indexed layouts and
reproduced only the existing high-risk protected-body rebasing family recorded
below. The implementation review found a separator-classification mismatch, a
generated three-child delimiter wrapper that could be misclassified as a
prefix-index application, and two test gaps. Those were corrected with the
existing rule APIs before the final external runs. The final implementation
requires a following operand for generated prefix-index dispatch and uses the
same lexeme-based trailing-separator classification as breakpoint
normalization.

### Full validation at `61d472a`

The current revision was validated from a fresh checkout of Mathlib `v4.32.0`
at commit `81a5d257c8e410db227a6665ed08f64fea08e997`. The run used the Lake cache,
selected only the 8,264 tracked `.lean` files under `Mathlib`, set the line width
to 100, and did not pass `--jobs`. Cache restoration took 41 seconds and the
cached pre-format build passed all 8,654 jobs in 4 seconds.

All 83 formatter batches were exercised. Code preservation, missing-rule,
fallback, and idempotency counts were zero throughout. Two batches stopped on
accepted indentation-induced line overflows: a 101-column qualified projection
in `Mathlib/AlgebraicGeometry/Gluing.lean:119` and a 104-column protected proof
line in `Mathlib/AlgebraicGeometry/StructureSheaf.lean:426`. The run resumed
after each diagnostic so the remaining corpus was still covered. Formatter
batches took 3,565 seconds in aggregate, with a 37-second median, 59-second
90th percentile, and 104-second maximum at batch 47. The isolated slow batches
did not form an increasing trend, and there was no worker failure or memory
pressure.

The complete post-format build passed all 8,654 jobs in 3,362 seconds. The
formatted tree changed 7,525 files, with 310,964 insertions and 270,916
deletions; `git diff --check` passed. Eight independent domain reviews found no
code-preservation issue, but confirmed that the corpus was not yet visually
release-ready at that checkpoint. The review identified these general
families:

- protected parenthesized `by` bodies can retain the shell column after the
  shell moves; 27 examples were found across the reviewed domains;
- `calc` rows can still use either the `calc` column or a preceding proof body's
  column instead of one shared row base;
- standalone `<|` and its operand can detach from their governing application;
- branch bodies, inline record fields, and nested attribute children can retain
  an obsolete source or opener column;
- declaration-result comments and continued line comments can consume or lose
  their pending structural indentation;
- semantic trailing comments such as `shake: keep` can detach from the import
  they qualify;
- indexed delimiter groups can separate a closing `]` and then over-indent the
  following argument.

These findings seeded the later checkpoints in this history. Items that still
apply are maintained in the queue above; none justify path-specific rules or a
new rule API.

### Earlier validation and fixes

The complete Mathlib validation baseline used leanfmt commit `3f3bd05` against
Mathlib `v4.32.0`. The final invocation resumed at batch 75 after the preceding
batches had passed. Batches 75 through 83 took 31 to 42 seconds each and passed
code preservation, missing-rule, actionable-overflow, fallback, and
idempotency checks. Combined with the persisted state for batches 1 through 74,
all 83 formatter batches passed. The run used the Lake cache, selected only
tracked `.lean` files under `Mathlib`, and did not pass `--jobs`; the formatter
used its default automatic worker count.

The complete post-format build passed all 8,654 jobs in 3,867 seconds. The
resumed validation took 4,203 seconds overall. There were no formatter
exceptions, missing rules, non-idempotent files, worker failures, or memory
pressure. The build emitted only Mathlib long-line and long-file lints. These
remain accepted when an unbreakable line begins at its logical indentation or
the additional file length comes from otherwise sound formatting.

The formatted tree changed 7,512 files. Four independent reviewers scanned
separate Mathlib domains for wrong or missing line breaks and incorrect
indentation. Eight representative findings were then copied to temporary files
and formatted again with the current executable under Mathlib's Lake
environment. Every representative remained unchanged, so the findings below
describe current formatter behavior rather than output left by an earlier
batch. The corpus is build-clean and diagnostics-clean, but it is not yet
visually release-ready.

Three general fixes from this review are now implemented independently. Commit
`8ca47da` gives multiline source slices a continuation margin relative to their
rendered anchor. Commit `9d6eada` rebases `calc` rows from the rendered `calc`
introducer. Commit `e7ba1a3` prevents fit recovery from moving a structural,
multi-token child below the base selected by its parent; atomic recovery remains
available for genuinely unbreakable tokens. These changes refine existing
planner and renderer contracts without adding a public or rule-facing API.

At `e7ba1a3`, focused width-100 checks of ten representatives passed code
preservation, missing-rule, actionable-overflow, fallback, and idempotency in
13 seconds. Their targeted build passed all 3,163 required jobs in 824 seconds,
with only the accepted Mathlib long-line and long-file lints. The
source-comment, detached-`calc`, and moved structural-lambda representatives now
have the intended shape when the comment is one multiline source slice. The
split line-comment and peer-continuation observations were kept outside those
fixes and are maintained in the queue above when still applicable.

The same revision passed fresh complete validation of `graphql-lean` and
`quantum-computing-lean` without a `--jobs` override. GraphQL's three formatter
batches took 10, 12, and 7 seconds. Quantum's cache phase took 16 seconds, its
initial build took 41 seconds, formatting took 17 seconds, and its post-format
build took 2 seconds. The combined run took 231 seconds. Both formatted
checkouts were byte-clean, and independent diff reviews found no formatting
regression.

That revision resolved the boundary before a parenthesized multiline
proof argument in the focused representative. The syntax tree already kept each
`by` shell structural and protected only its proof body; the missing invariant
was in flow rendering. A fitting multiline original-layout child no longer
makes its complete flow segment count as flat, and an existing boundary before
that child is taken. The full-corpus review showed that this was only the
shell-level part of the invariant: protected proof bodies could retain the
shell's column after the shell moved. This added no rule API or syntax-specific
renderer check.

Fresh validation passed without a `--jobs` override. GraphQL's initial build
took 56 seconds, its formatter batches took 11, 11, and 8 seconds, and its
post-format build took 24 seconds. Five files changed to put parenthesized proof
arguments on separate continuation lines; independent review found no logical
formatting error. Quantum's cache, initial build, formatter, and post-format
build took 16, 41, 17, and 2 seconds respectively and produced no diff. The
combined run took 257 seconds. The width-100 Mathlib representative passed
preservation and idempotency in 7 seconds, then its 1,331-job target graph
replayed and built successfully in 5 seconds with only accepted lints.

### Follow-up validation: 2026-08-01

The formatter was validated again at leanfmt commit `dc968e7` against the same
Mathlib `v4.32.0` commit. The run used the Lake cache, selected only tracked
`.lean` files under `Mathlib`, and used the repository's default formatter job
count. All 83 formatter batches passed preservation, missing-rule, overflow,
fallback, and idempotency checks. The complete post-format build passed, and
7,503 changed files were reviewed. The only reported overflow was an accepted
102-column unbreakable line at `Mathlib/Tactic/Ring/Basic.lean:399`; it starts
at the correct logical indentation.

The same formatter revision also passed complete validation and post-format
builds for `graphql-lean` and `quantum-computing-lean`. The GraphQL run changed
eight files without exposing a logical layout error. The quantum run produced
no formatting diff. No formatter exception or material performance regression
was observed in any of the three projects.

Post-fix verification at leanfmt commit `0722403` remained clean:

- `graphql-lean`: the initial 265-job build took 56 seconds, the three formatter
  batches took 11, 12, and 7 seconds, and the post-format build took 31 seconds.
  The same eight files changed, with no new formatting family or exception. Its
  optional cache command was unavailable and was skipped.
- `quantum-computing-lean`: the Lake cache phase took 16 seconds, the initial
  2,653-job build took 42 seconds, formatting took 17 seconds, and the final
  build took 2 seconds. Formatting produced no diff.
- Targeted Mathlib checks took 8 seconds for
  `Mathlib/FieldTheory/SplittingField/Construction.lean` and 5 seconds for
  `Mathlib/GroupTheory/GroupAction/SubMulAction/OfFixingSubgroup.lean`. Both
  passed preservation, missing-rule, overflow, fallback, and idempotency checks.
  These targeted runs intentionally skipped the already-completed full builds.

### Follow-up rule-family fixes

The follow-up review produced three bounded consistency fixes. Explicitly named
indexed infix notation is recognized from its delimiter shape, so its closing
`]` does not detach. A multiline named argument owns the break before its value,
while its closing `)` remains a tight suffix unless a comment forces a new line.
Low-priority pipes align `let`, `have`, and `haveI` operands consistently and
keep the first line of ordinary `by`, `do`, and `calc` operands attached.

These fixes stayed in syntax grouping and line-break rules, used no
project-specific conditions, and passed targeted Mathlib preservation and
idempotency checks. The high-risk layout-base observations from this review are
maintained in the remaining-issue queue at the top of this document.

### Initial validation baseline

- Review date: 2026-07-30
- leanfmt commit: `935dc60`
- Mathlib tag: `v4.32.0`
- Mathlib commit: `81a5d257c8e410db227a6665ed08f64fea08e997`
- Selected files: tracked `.lean` files under `Mathlib`
- Line width: 100
- Formatter batches: 83 batches covering 8,264 files
- Result: every preservation, missing-rule, overflow, fallback, and idempotency
  check passed
- Post-format build: all 8,654 jobs passed
- Changed files visually reviewed: 7,505

Unbreakable long lines are accepted when they begin at the logical indentation
established by the formatting rules. They are not findings by themselves. The
review below is limited to wrongly inserted line breaks, detached syntax, and
incorrect indentation bases.

### Initial reviewed findings

#### 1. Infix continuations form diagonal staircases

Status: resolved.

Same-precedence operators can inherit the preceding operand's ending column
instead of sharing a structural continuation base.

Representative:
`Mathlib/AlgebraicGeometry/EllipticCurve/Projective/Formula.lean:252`.

```lean
2 * ...
                                                            - 8 * ...
                                                          + 9 * ...
                                                        - 6 * ...
```

The same root problem appears in:

- `Mathlib/Geometry/Euclidean/MongePoint.lean:230`
- `Mathlib/Tactic/GRewrite/Core.lean:432`
- `Mathlib/Tactic/TFAE.lean:74`
- `Mathlib/Tactic/DepRewrite.lean:309`

The representatives had several related causes. Mixed infix operators now
flatten when Lean's trailing parser descriptions report equal binding powers,
and nested pipe projections regroup as one peer chain. `do if-let` action
continuations inherit the conditional base, `leading_parser` arguments use
application flow, and a generated notation break before trailing punctuation
moves after that separator in the renderer.

#### 2. Enclosing breakpoints lose priority over nested expression breaks

Status: resolved.

Dependent binders, custom-command arguments, applications, notation parser
categories, and type ascriptions sometimes remain inline until a nested child
breaks from a far-right token column.

Representative cases:

- `Mathlib/CategoryTheory/Abelian/Projective/Resolution.lean:84`: a dependent
  `Σ'` body
- `Mathlib/MeasureTheory/Measure/MeasureSpaceDef.lean:438`:
  `add_aesop_rules` arguments
- `Mathlib/LinearAlgebra/LinearIndependent/Lemmas.lean:757`: nested
  application and type ascription
- `Mathlib/MeasureTheory/Integral/Average.lean:102`: notation parser category

For example, sibling custom-command arguments form a staircase:

```lean
add_aesop_rules safe
                  tactic
                    (rule_sets := [Measurable])
                      (index := [target @AEMeasurable ..])
                        (by fun_prop (disch := measurability))
```

The enclosing comma, operator, or command-argument breakpoint should be
selected before internal child breakpoints when that establishes a normal
structural base.

Generated binder terms are now recognized from their binder shape, recursive
command argument sequences share one continuation base, and notation header
groups expose a flowing outer breakpoint before nested parser-category syntax.

#### 3. Moved subtrees retain stale source indentation

Status: resolved.

When formatting moves a parent expression or scoped command, some protected
proofs, custom-command bodies, or nested structure instances retain an old
absolute source indentation.

Representative:
`Mathlib/AlgebraicGeometry/ProjectiveSpectrum/Scheme.lean:294`.

```lean
              ⟨m * i, ⟨proj 𝒜 i a ^ m, by
      rw [← smul_eq_mul]; mem_tac⟩,
```

Other cases:

- `Mathlib/Data/Fin/VecNotation.lean:189`: `dsimproc` moves under
  `open Qq in`, but its `do` body does not move with it
- `Mathlib/RingTheory/HopkinsLevitzki.lean:112`: `by` and its proof body
  receive the same indentation
- `Mathlib/Tactic/Widget/Calc.lean:44`: nested structure instances accumulate
  opener and source columns

Source-preserved subtrees must be rebased relative to the formatted position of
their owning syntax. Structural formatting of a nested structure instance must
also use a parent-relative block base instead of recursively using each visual
opener column.

Protected layouts are now rebased when their parent moves. Singleton `#[…]`
wrappers propagate the enclosing expression base, and tail lifting no longer
replaces a base that a nested structure instance explicitly inherits.

#### 4. Branches inherit the wrong owning base

Status: resolved.

An outer `else` can align with an inner `match`, inner `then` body, or other
final child rather than the `if` that owns it.

Representative cases:

- `Mathlib/Util/Notation3.lean:499`
- `Mathlib/Tactic/Explode.lean:154`
- `Mathlib/Tactic/Linter/DeprecatedSyntaxLinter.lean:142`

Related record-valued branches in
`Mathlib/Probability/Kernel/Composition/ParallelComp.lean:47` remain level
with `then` instead of receiving one branch-body indentation level.

Branch keywords should use their owning conditional's base. Branch bodies
should then use one structural level under that base.

Ordinary, dependent, and `if let` conditionals now expose the same owning-base
break structure. Their branch keywords return to that base and branch bodies
receive one child level.

#### 5. Declaration colons detach around intervening comments

Status: resolved.

An intrinsic comment break between the declaration type separator and result
type establishes the result continuation. When the complete comment line fits,
the renderer moves the detached comment beside the separator:

```lean
    (h ...)
    : -- then `P` is projective.
      Projective R P := by
```

Representative cases:

- `Mathlib/Algebra/Module/Projective.lean:280`
- `Mathlib/CategoryTheory/Limits/HasLimits.lean:444`
- `Mathlib/Logic/Function/Basic.lean:1252`
- `Mathlib/RepresentationTheory/Rep/Basic.lean:789`

The declaration colon retains its ordinary breakpoint. Comment trivia owns its
physical newline, and the renderer applies the result indentation to the token
after it without requiring a comment-sensitive declaration rule.

#### 6. Custom declaration modifiers detach

Status: resolved.

Modifiers are split from the extensible `irreducible_def` command:

```lean
protected
irreducible_def add ...
```

Representative cases:

- `Mathlib/Data/Real/Basic.lean:78`
- `Mathlib/FieldTheory/RatFunc/Basic.lean:79`
- `Mathlib/MeasureTheory/Measure/Stieltjes.lean:523`

Command modifiers should attach to the following command keyword regardless of
whether the command is core syntax or an extension.

Syntax regrouping now separates extension-owned modifier containers from their
command and places both in the annotated-declaration flow.

#### 7. Structure-value `abbrev` declarations detach `where`

Status: resolved.

The structure-value suffix is broken as:

```lean
abbrev ... : CompleteAtomicBooleanAlgebra α
  where
```

Representative: `Mathlib/Order/Atoms.lean:561`. The same shape occurs across
Order declarations and in, among others:

- `Mathlib/RepresentationTheory/Continuous/TopRep.lean:236`
- `Mathlib/RingTheory/Localization/Defs.lean:148`
- `Mathlib/SetTheory/ZFC/Basic.lean:79`

This is distinct from an auxiliary definition block. A structure-value
`where` should remain a suffix of the declaration signature, consistently with
other declaration commands.

Flattened declaration values now retain `whereStructInst` as the value child,
so `where` remains attached while the structure fields own their following
breaks.

#### 8. Let-fallback bars become orphan lines

Status: resolved.

The fallback separator in `let` pattern syntax can be emitted as a line
containing only `|`.

Representative cases:

- `Mathlib/Tactic/ClickSuggestions.lean:134`
- `Mathlib/Tactic/Coe.lean:23`
- `Mathlib/Tactic/Translate/Core.lean:512`

The fallback bar should remain attached to the scrutinee suffix or fallback
body; it must not become an independent visual segment.

The fallback clause and its continuation are distinct logical nodes. Renderer
comment-boundary handling can force the structural continuation without making
the bar an independent breakable piece.

### Completed initial fix sequence

Each logical fix was kept in a separate commit with focused regression
coverage. The formatter's self-format gate and affected Mathlib representatives
were rerun as the fixes progressed.

#### Phase 1: low-risk syntax-boundary fixes (completed)

1. Resolved issue 5 by retaining the declaration's ordinary break before `:`.
   Comments on the following line use the result indentation; comments explicitly
   attached as `: -- comment` remain on the separator line.
2. Fixed issue 8 by regrouping the `let` fallback separator with its owning
   fallback syntax and giving that syntax an explicit low-risk line-break rule.
3. Fixed issue 6 by making command modifiers and the following extensible command
   keyword one header segment, covering both `private irreducible_def` and
   `protected irreducible_def`.
4. Fixed issue 7 by mapping `abbrev` structure values to the same declaration
   suffix behavior used by other `... where` declarations while preserving the
   distinct layout of auxiliary `where` blocks.
5. Revalidated the files and Mathlib batches containing these examples.
   No standalone `:`, `|`, modifier, or structure-value `where` remains.

These fixes stayed in syntax regrouping or line-break rules and did not add
file- or declaration-name checks to the renderer.

#### Phase 2: high-risk layout-base fixes (completed)

1. Addressed issue 4 by making conditional branch ownership explicit in the
   syntax tree or rule data. `else` uses the owning `if` base, and each branch
   body uses one child level. Nested `if let`, `match`, and record-valued
   branches are covered together.
2. Addressed issue 3 by defining one relative-rebasing contract for original
   subtrees and applying it to proofs, `do` bodies, scoped custom commands, and
   nested structure instances without separate renderer exceptions for each
   syntax kind.
3. Addressed issue 2 by changing candidate selection so an enclosing structural
   breakpoint wins before nested breaks that would inherit a far-right inline
   column. Dependent binders, application arguments, custom commands, notation
   categories, and type ascriptions use the same mechanism.
4. Addressed issue 1 after issue 2, since both depend on continuation-base
   semantics. Same-precedence infix and pipe-projection chains now share one
   base without changing Lean's parsed syntax or hardcoding operator spellings.
5. Every high-risk step received focused unit coverage, self-format exception
   and idempotency checks, and targeted width-100 Mathlib validation.

Do not change issue 9 or the intentional `<|` spacing as part of these fixes.
