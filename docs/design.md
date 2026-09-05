# leanfmt formatting design

This document describes how leanfmt formats Lean source code. It is written for
Lean programmers evaluating the formatter and for users who want to understand
the changes it makes.

leanfmt is a conservative, structure-preserving formatter. It parses a complete
Lean file with Lean's parser, recognizes common Lean constructs, and chooses
whitespace and line breaks around the existing source tokens.

For implementation architecture, see [architecture.md](architecture.md). For build,
test, and debugging commands, see [development.md](development.md).

## Formatting at a glance

leanfmt turns a line-wrapped proposition whose nesting is difficult to scan:

```lean
def parenthesizedConjunctionChain (schema : Schema) : Prop :=
  namesAreUnique (schema.allTypes.map TypeDefinition.name) ∧
    schema.objectType schema.queryType ∧
    (∀ typeDefinition, typeDefinition ∈ schema.types
      -> typeDefinitionWellFormed schema typeDefinition) ∧ (∀ typeName objectTypeName,
          objectTypeName ∈ schema.getPossibleTypes typeName
    -> schema.objectType objectTypeName)
```

into a layout where each leading `∧` connects a peer operand and indentation
shows the structure inside each operand:

<!-- leanfmt-test -->
```lean
def parenthesizedConjunctionChain (schema : Schema) : Prop :=
  namesAreUnique (schema.allTypes.map TypeDefinition.name)
  ∧ schema.objectType schema.queryType
  ∧ (∀ typeDefinition,
      typeDefinition ∈ schema.types -> typeDefinitionWellFormed schema typeDefinition)
  ∧ (∀ typeName objectTypeName,
      objectTypeName ∈ schema.getPossibleTypes typeName
      -> schema.objectType objectTypeName)
```

## Design philosophy

### Preserve code, format structure

Formatting changes whitespace only. Token text and token order remain the same.

### Prefer a clear rule over a clever guess

leanfmt has rules for common Lean constructs. Unknown syntax is still lossless and
receives a generic structural layout, but leanfmt does not guess at the meaning of custom
syntax.

Proofs receive an even more conservative treatment. Proof subtrees are retained
from their original source so that formatting declarations and propositions
does not accidentally damage tactic layout.

### Keep fitting code compact

leanfmt uses a 90-character default line limit and two-space indentation. The
line limit is configurable for projects with a different convention. Most
constructs are first considered in a single-line form. A construct breaks only
when it is structurally multiline, an accepted source break applies, or the flat
form does not fit.

The line limit counts displayed Lean characters in the formatter's string
model: symbols such as `∀`, `∧`, and `→` count as one character.

### Make continuation structure visible

Indentation shows block structure under constructs such as `def` and `theorem`.
It also shows a local continuation when an application wraps:

```lean
def result :=
  veryLongFunctionName child children additionalArgumentOne
    additionalArgumentTwo additionalArgumentThree
    additionalArgumentFour
```

For infix expressions, a leading operator indicates continuation without adding
another logical nesting level:

<!-- leanfmt-test -->
```lean
def propositionContinuation : Prop :=
  sourceSelectionSetIsWellFormed
  ∧ normalizedSelectionSetPreservesResponseKeys
  ∧ fragmentExpansionPreservesRuntimeSemantics
```

leanfmt generally breaks before operators for this reason. Bodies after `:=`,
`=>`, `with`, quantifier commas, and similar separators are indented instead.
The low-priority application operator `<|` is the one exception: its grouped
right operand can expose a boundary after the operator for flowing suffixes.
Other infix operators expose only their leading boundary. A non-suffix operand
keeps `<|` with its first line, so the outer infix boundary moves the complete
`<| operand` group and cannot leave the operator alone. Established suffixes
such as `by`, `do`, and `calc` keep using suffix attachment and may break their
body after the attached introducer. An authored source break alone does not
protect the post-operator boundary. A protected operand moves beside `<|` as a
complete source-layout island; an indivisible long first line is accepted at
that logically correct indentation.
Layout-sensitive `let` and `have` operands align their keyword to an indentation
column after `<|`; this can require two spaces after the operator, and keeps the
binding body at the same valid Lean layout base.

Parser-owned modifiers stay with the argument they introduce. For example,
`simpa only [` remains one header even when the bracketed collection wraps
internally. An attached body introducer likewise remains a suffix of an
alternative, so generated term syntax uses `=> do` while an ordinary
non-suffix alternative body begins on the following indented line.
Parser-defined tactic suffixes follow the same principle: a fitting body may stay
beside a suffix such as `says`, while a broken body continues from the suffix
owner's base. Likewise, `show ... from` keeps `from` with the following
application head and lets that application wrap at its own argument boundaries.
An optional parser child with no source tokens does not separate a declaration
prefix from its header, so `have`, `let`, and extension forms built from
`letDecl` keep their keyword with the declaration name.

### Preserve intentional source breaks selectively

Line breaks from the input source code are meaningful in some places and incidental in
others. leanfmt preserves a source break only where the rule for that construct accepts
one. It always computes the resulting indentation itself.

For example, a multiline function application may retain well-chosen argument
breaks after the flat form overflows. A fitting infix expression is flattened
even if its source had an arbitrary break.

Input source code with intentional line breaks:

```lean
      semanticEquality schema someLongContextParameter
        (normalize left)
        (normalize right)
```

We don't want to force wrap it like:

```lean
      semanticEquality schema someLongContextParameter (normalize left)
        (normalize right)
```

Definitions, theorems, parameter lists, and match pattern lists also have
specific boundaries where source line breaks may be preserved.

Source-break preservation follows the rule's layout mode:

- a flow rule retains accepted source boundaries and may add only the other boundaries
  needed by its fitting layout;
- a non-flow rule is balanced: once an accepted source break activates the rule,
  every break point returned by that rule is applied together.

This prevents partially broken branch, collection, header, and peer layouts. A
non-flow conditional cannot preserve only the break before `else`, for example;
it formats the `then` and `else` branches as one balanced structure.

### Keep separators with their headers

The assignment and arm separators `:=`, `←`, and `=>` belong to the header on
their left. Their syntax rules do not offer a break immediately before the
separator. If the right-hand side must move, the break occurs after it:

```lean
def result :=
  longDefinitionBody

let value :=
  longComputation

let value ←
  longAction

| pattern =>
    longArmBody
```

This rule applies consistently to declarations, ordinary and destructuring
`let` bindings, monadic bindings, lambdas, match alternatives, and
equation-style declaration arms.

The same header-suffix principle keeps `instance ... where` and `match ... with`
together; the body breaks after `where` or `with`, not before it.

It also keeps an assignment marker on an opaque declaration's final signature
line and keeps a terminal delimited tactic argument with its introducer:

```lean
opaque generatedValueWithALongName
    : VeryLongReturnType :=
  implementation

example : True := by
  refine {
    property := proof
  }

example : True := by
  · exact ⟨
      witness,
      proof
    ⟩
```

Term-taking tactics use this suffix attachment even when their operand contains
nested proof layout or has already been regrouped as an application. An attached
tactic-sequence wrapper forwards that ownership without exposing unrelated proof
text. An ordinary function application or direct command term still breaks before
a delimited argument when necessary; the delimiter does not become part of the
function head.

The introducer keyword is also part of a binding header. leanfmt never emits a
line containing only `let`; it keeps `let` with the pattern, identifier, or
anonymous type colon:

```lean
let coreContext : Core.Context :=
  { fileName := inputContext.fileName, fileMap := inputContext.fileMap }

let : VeryLongTypeConstructor firstArgument secondArgument
        thirdArgument :=
  value
```

These separator rules are structural rather than renderer spelling checks. A
rule simply does not offer a break before its separator.

## File-level whitespace

These rules apply to every formatted file:

- CRLF and CR line endings become LF.
- Trailing spaces and tabs are removed.
- A run of blank lines becomes at most one blank line.
- A nonempty file ends with exactly one newline.
- Empty formatted output remains empty.

## Ignored Regions

Use `-- leanfmt: off next` before syntax to preserve the next complete syntax
node exactly:

```lean
-- leanfmt: off next
def handAligned   :   Nat:=
       1
```

The marker attaches to the next parsed Lean syntax node, not the next indentation
block. At the top level, it preserves the complete command. Within a declaration,
it can preserve a nested term such as a manually aligned function body:

```lean
def handAlignedFunction : Nat → Nat :=
  -- leanfmt: off next
  fun n =>
      n + 1
```

Use `-- leanfmt: off` and `-- leanfmt: on` on their own line-comment lines to
preserve a manual source region exactly:

```lean
def formattedBefore:Nat:=0

-- leanfmt: off
def handAligned   :   Nat:=
       1
-- leanfmt: on

def formattedAfter:Nat:=2
```

leanfmt formats the parseable chunks before and after the region, then splices
the ignored marker lines and enclosed lines back unchanged. An `off` marker
without a matching `on` marker preserves the rest of the file.

## Comments

Line comments, block comments, nested block comments, and doc comments keep
their text. leanfmt cleans surrounding whitespace and reindents comment trivia
when a containing construct moves. When a multiline module or declaration doc
comment moves, every line shifts with its opening delimiter so internal relative
indentation remains unchanged.

```lean
-- module comment

/- block comment -/
def f : Nat :=
  -- body comment
  0
```

A trailing line comment stays on its line:

```lean
def answer : Nat := 0 -- trailing comment
```

An authored trailing line comment remains attached when the line is longer than
the configured width. The formatter may break the surrounding construct at its
ordinary structural boundaries, but it does not turn the comment into a
standalone comment.

Consecutive line comments attached to trailing code move as one comment group.
Later lines retain their authored offset from the first comment opener. A line
authored immediately one column left of that opener is treated as aligned and
cannot rebase to its left; a more distant line keeps its distinct offset. A
standalone comment after a protected proof body follows its source nesting: a
comment deeper than the next peer remains in the proof body, while a comment at
the peer's indentation follows the peer.

Comment contents are not wrapped or rewritten. Module and declaration documentation
comments retain their line shape and their exact internal whitespace relative to the
opening delimiter.

## Token spacing

leanfmt normally inserts one space between adjacent ordinary tokens and keeps
punctuation tight.

```lean
def identity : Nat → Nat :=
  fun x => x

def optionConstructor :=
  some .null
```

The main punctuation rules are:

- no space after `(`, `[`, `⟨`, `⟪`, `@`, or `@[`;
- no space before `)`, `]`, `⟩`, `⟫`, `,`, `;`, or `@`;
- dots stay tight in projections and qualified names;
- the two-backtick prefix of fully qualified name quotations stays tight;
- ordinary operators and declaration punctuation receive surrounding spaces;
- compact `!value` remains compact when `!` and the following token were
  adjacent; otherwise `! value` retains a space.

Source-tight edge pieces of generated notation remain structural units when
the surrounding term wraps. This keeps forms such as `#{...}`, `∂μ`, and
`∂.pi` from splitting at a boundary where the notation supplied no whitespace.

Braces retain the source's tight or spaced style where adjacency makes that
distinction safe:

```lean
{data := .null}
{ data := .null }
```

When a brace-delimited term contains multiple comma-separated items and does not
fit, it uses the same balanced layout as other collections:

```lean
{
  first,
  second
}
```

leanfmt does not infer that whitespace before a dot is always removable. In
Lean, a dot after an expression can also begin an anonymous constructor, so the
syntax tree and original adjacency are respected.

Interpolated strings are single atoms. The `s!` prefix stays attached to the
string, and neither source breaks nor width wrapping introduce breaks inside an
interpolation:

```lean
s!"expected three operands, got {repr other}"
```

The containing application may break before the whole interpolated string.

## Modules and commands

Imports and top-level commands start on separate lines. Their order is
preserved. A `module` command, consecutive `public import` commands,
consecutive ordinary imports, and the following command form separate groups
with one blank line. Imports within one group have no blank lines between them.

```lean
module

public import Lean
public import Std

import Lean.Elab
import Lean.Parser

/-! # Example -/

namespace Example

def answer : Nat := 42

end Example
```

A module docstring is separated from the first declaration. Leading comments
and declaration docstrings stay attached to the command they describe. When a
syntax form takes a doc comment as its own payload, an inline comment stays
inline if the form fits; after a break, the comment and following body share the
form's base indentation. A comment-bearing term form retains its source break
before the following term and keeps the directive with its doc payload. This
applies in command, tactic, and term positions.

Multiline top-level declarations have a blank line between them and adjacent
declarations. Short one-line declarations may remain grouped without blank
lines:

```lean
structure Point where
  x : Nat
  y : Nat

def origin := Point.mk 0 0
def unitX := Point.mk 1 0

structure Segment where
  start : Point
  stop : Point
```

Existing blank lines may still separate short declaration groups and other
top-level commands.

The same declaration boundary applies inside a `mutual` block. Adjacent multiline
declarations are separated even when the input omitted the blank line:

```lean
mutual
  theorem first : True := by
    trivial

  theorem second : True := by
    trivial
end
```

A long individual import is not split internally. Syntax declarations and
other command forms keep their tokens and use either an explicit command rule
or the generic structural layout.

```lean
import Very.Long.Module.Name.ThatRemainsOneImportCommand

syntax "widget" : term
```

A single-expression `initialize` command keeps its keyword with the expression
head. Its top-level application arguments remain on that header line because a
command-base continuation would be parsed as another implicit initializer
statement. Nested bodies still use the command base:

```lean
initialize registerBuiltinAttribute {
  name := `sample
  descr := "sample attribute"
}

initialize cleanupRef.set fun expression => do
  return (← cleanup expression).value
```

Long `assert_not_exists` commands put their identifier list on continuation
lines and fill each line up to the configured width:

```lean
assert_not_exists
  FirstForbiddenDeclaration SecondForbiddenDeclaration ThirdForbiddenDeclaration
  FourthForbiddenDeclaration
```

Command binder lists expose their binders as direct peers of the command keyword.
Whether the binders are identifiers or structured instance binders, continuation
lines therefore return to one command-relative base instead of staircasing through
the parser's nested list wrapper:

```lean
include u v w veryLongUniverseName
  anotherLongUniverseName

omit [FirstClass α] [SecondClass α]
  [ThirdClass α] [FourthClass α]
```

Other registered word-headed lists use the same flowing continuation base when Lean
stores their simple operands in one anonymous parser container. This applies to
universe-level lists, level `max` operands, and constructor arguments in `match_expr`
patterns:

```lean
universe u v w veryLongUniverseName
  anotherLongUniverseName
```

Lake package commands keep `where` on the header and indent configuration fields one
level. A multiline Git dependency breaks after `git`, and its revision separator keeps
ordinary source spacing:

```lean
package example where
  srcDir := "."

require mathlib from git
  "https://github.com/leanprover-community/mathlib4.git" @ "vX.Y.Z"
```

An attribute may share the line of any top-level command that accepts declaration
attributes when the source keeps them together and the complete command fits on
that line. This applies equally to built-in declarations and commands added by
syntax extensions:

```lean
@[simp] theorem eraseP_nil : [].eraseP p = [] := rfl
```

A source break between an attribute and its command is preserved. A multiline
command breaks after the attribute before trying breaks inside the command:

```lean
@[ext]
structure Point where
  x : Nat
```

For example, a declaration that wraps because of width moves below its attribute:

<!-- leanfmt-test -->
```lean
@[simp]
theorem normalizedSelectionSetExecutionPreservesFieldResponseOrdering
    (value : NormalizedSelectionSet)
    : SelectionSetExecutionResult :=
  proof
```

Keyword modifiers remain on the declaration header:

```lean
private theorem helper : True := by
  trivial
```

Macro signatures form a header flow independently of their expansion body. A
fitting header remains on one line even when the body is multiline; an
overflowing header may flow between parser-owned pattern arguments before it
breaks before its type, and the body then starts one level inside the command.
A leading `do` or `by` stays with `=>` as the body's introducer suffix. When a
macro renders multiline, it has the same blank command boundary before its next
declaration as other multiline declarations, including through attributes.

```lean
local macro "map_simp" : tactic =>
  `(tactic| simp)

macro "run_generated" : command => do
  emitCommand
```

Continuation indentation is measured from the beginning of the command line,
not from the declaration keyword after its modifiers:

```lean
private inductive Aligned : List α -> Prop where
  | nil : Aligned []
  | cons : Aligned values -> Aligned (value :: values)
```

## Declaration headers

### Names

A declaration name normally stays with its command keyword and modifiers. If that
prefix makes the name overflow, the name moves to the ordinary four-space declaration
continuation. Parameters and the return type then keep using the same declaration base:

<!-- leanfmt-test -->
```lean
private theorem
    normalizedSelectionSetPreservesDirectiveEvaluationAcrossFragmentExpansion
    (value : InputType)
    : OutputType :=
  proof
```

This name flow is shared by definitions, theorems, structures, inductives, and other
commands that use Lean's declaration identifier syntax.

### Parameters

Declaration parameters flow at binder boundaries. leanfmt keeps as many
binders as fit and places later binders on continuation lines indented four
spaces from the declaration base.

<!-- leanfmt-test -->
```lean
def lookupObject (schema : Schema) (requestedTypeName : Name)
    (fallbackObjectType : ObjectType)
    : Option ObjectType :=
  body
```

Existing parameter breaks can be retained after the header no longer fits.

```lean
def shapeExample (arg1 : VeryLongTypeNameUsedForLayout)
    (arg2 : AnotherVeryLongTypeNameUsedForLayout)
    : VeryLongReturnInputTypeWithEnoughCharactersForLayoutTesting
      -> VeryLongReturnOutputTypeWithEnoughCharactersForLayoutTesting :=
  body
```
Grouping inside a binder remains logically intact, such as `(x y : Nat)` and
`{ObjectRef : Type}`. A long sequence of names may wrap within the same pair of
delimiters; it is not rewritten into separate binders.

```lean
def compareSelections
    (rootSelectionSet leftInitialSelectionSet rightInitialSelectionSet
      leftCurrentSelectionSet rightCurrentSelectionSet
      : List Selection) :=
  body
```

If one binder is too long, it may break before its type annotation:

<!-- leanfmt-test -->
```lean
def binderExample
    (hknown
      : ∀ name value,
          everyReferencedObjectValueBelongsToTheDeclaredCompositeSchemaType name value) :=
  body
```

### Return types

When a declaration header is too long, the return type moves to a line beginning
with `:`. This line uses the declaration continuation indentation rather than
the body indentation.

```lean
def lookupVariableValue? (variableValues : VariableValues) (name : Name)
    : Option InputValue :=
  body
```

An author may attach a result comment to the declaration colon. A detached line
comment between the colon and result type moves beside the colon when the
complete `: -- comment` line fits. The comment's own newline then establishes
the indented result continuation:

<!-- leanfmt-test -->
```lean
theorem projective_of_lifting_property (h : LiftingProperty P)
    : -- The lifting property makes `P` projective.
      Projective R P := by
  exact proof
```

Comments immediately inside a delimiter follow the same boundary behavior. A
line comment or multiline block comment may move beside the opening delimiter;
its intrinsic newline establishes the body indentation. A single-line block
comment remains ordinary inline trivia while the complete tree fits. Under
width pressure, the renderer may use the enclosing tree's ordinary break and,
when needed, break between the comment and its following token.

Long function return types break before arrows:

```lean
def nestedReturnChain
    : A -> VeryLongIntermediateReturnTypeWithEnoughCharactersForLayoutTesting
      -> VeryLongFinalReturnTypeWithEnoughCharactersForLayoutTesting :=
  body
```

Return-type arrow chains use flow layout: only the boundaries required to fit
the line are broken.

### Definition bodies

A body that does not fit on the header starts after `:=` and is indented one
level:

```lean
def wrappedApplicationArgument : Result :=
  singleFieldResult responseName
    (completeValue schema resolvers variableValues
      fuel' fieldDefinition.outputType
      (field :: fields) resolved)
```

An existing break immediately after `:=` is an accepted source break, even when
the body itself would fit on the header. This allows a project to retain a
deliberately multiline definition style.

Bodies beginning with `do` or `by` keep that keyword attached to `:=`; the
nested construct owns its body layout.

```lean
def lookupObject (schema : Schema) (typeName : Name) : Option ObjectType := do
  body
```

### `where` blocks

`where` returns to the declaration's base column. Nested declarations are
indented one level.

```lean
def outer : Nat :=
  inner
where
  inner : Nat := 0
```

Nested and local declarations give the signature and value separate layout ownership.
The assignment boundary is therefore tried before splitting a fitting signature,
independently of the source line on which the value begins:

<!-- leanfmt-test -->
```lean
def outer : Nat :=
  helper 0
where
  helper (n : Nat) : Nat → Nat :=
    computeNormalizedRecursiveSelectionResultWithAccumulatedErrors n anotherArgument
```

The same ownership applies to a local tactic assignment whose value is a `by`
proof. When the complete assignment does not fit, `by` remains attached to `:=`
and the first break is before the proof body:

```lean
have hpreserve' :
    veryLongLeftFunctionName firstArgument secondArgument =
      shortRight firstArgument := by
  simpa [a, b] using hpreserve
```

Parser-owned tactic headers use the same hierarchy. Their assignment value
breaks first; if the remaining typed header is still too long, it may then
break before `:` without detaching the pattern from the tactic head:

```lean
obtain ⟨radius, radiusPositive, bound⟩
  : ∃ radius > 0, predicate radius :=
  eventualWitness
```

Termination clauses follow the same ownership rule. `termination_by` and
`decreasing_by` return to the base column of the declaration they modify. A
fitting `termination_by` parameter lambda and measure stay on one line:

```lean
termination_by patternList => body
```

When the clause does not fit, the first break is after `=>`; the measure is
indented one level:

```lean
termination_by patternList =>
  body
```

If the parameter header still does not fit, its names flow at two indentation
levels. The first names remain after `termination_by`, and `=>` remains attached
to the final parameter. The four-space parameter continuation is deliberately
distinct from the two-space measure:

```lean
termination_by firstPattern secondPattern thirdPattern
    fourthPattern =>
  body
```

The tactic after `decreasing_by` retains its source layout, rebased beneath the
formatted clause.

```lean
def outer (n : Nat) : Nat :=
  helper n
termination_by n
decreasing_by
  exact outerProof
where
  helper (n : Nat) : Nat := helper (n - 1)
  termination_by n
  decreasing_by
    exact helperProof
```

```lean
termination_by _schema _variableDefinitions fragments _parentType selection _field _hvalid
    _hbodies _hfield =>
  (fragments.length, sizeOf selection, 0)
```

Declarations inside `mutual` remain peers at the mutual-body indentation even
when a preceding declaration ends with a termination clause. A declaration's
documentation comment shares that same base:

<!-- leanfmt-test -->
```lean
mutual
  def first (n : Nat) : Nat :=
    second n
  termination_by n

  /-- Calls `first`. -/
  def second (n : Nat) : Nat :=
    first n
  termination_by n
end
```

### Theorems and proofs

Theorem headers use the same parameter and return-type rules as definitions.
In a simple theorem, `:= by` remains on the final header line:

```lean
theorem theoremArrowChain (h : HypothesisWithEnoughCharactersForLayoutTesting)
    : FirstCondition -> SecondCondition -> FinalCondition := by
  exact proof
```

The source text of theorem proof values and nested proof bodies is preserved.
Their surrounding declarations and structure instances remain structural when
the parser exposes those proof subtrees separately. Equation blocks whose parser
layout ties their arms together remain compound islands. The tactic body after
`decreasing_by` is protected separately from the formatted termination-clause
keywords and measure. leanfmt can therefore format surrounding declarations and
propositions without imposing a tactic style.

Equation-style theorem and definition arms begin on their own lines and use the
declaration body indentation.

```lean
theorem equations : List Nat -> True
  | [] => by
      trivial
  | _ :: rest => by
      trivial
```

## Structures, inductives, and mutual declarations

Structure fields start on separate lines under `where`:

```lean
structure Point where
  x : Nat
  y : Nat
```

Named structure constructors use the same field base. Constructor documentation and
modifiers move with the constructor:

```lean
structure Wrapped where
  /-- Build a wrapped value. -/
  private mk ::
  value : Nat
```

The field break does not force a fitting `extends` clause onto a continuation
line:

```lean
structure Candidate extends CandidateKey where
  occurrenceCount : Nat
```

This also applies to fitting parameterized headers:

```lean
structure ParameterizedCandidate (α : Type) extends CandidateKey α where
  occurrenceCount : Nat
```

When an `extends` list itself wraps, parent types flow after commas one level
beyond the `extends` line:

```lean
structure MultipleParentStructure (A : Type)
    extends FirstLongParentName A, SecondLongParentName A, ThirdLongParentName A,
      FourthLongParentName A, FifthLongParentName A where
```

Long field types use the same binder/type continuation principles as other
declarations.

<!-- leanfmt-test -->
```lean
structure ResolverFixture (ObjectRef : Type := PUnit) where
  resolve
    : Name -> Name -> List Argument -> ResolverValue ObjectRef
      -> Option (ResolverValue ObjectRef)
```

Structure fields defined by equations use the field indentation as their arm
base. Parameters remain with the field name when they fit; a wrapped parser
container does not make the arms align under their source column:

```lean
def symmetricOperation : SymmetricOperation where
  symm _ _
    | 0 => firstResult
    | _ + 1 => secondResult
```

Inductive constructors also start on separate lines:

```lean
inductive Color where
  | red
  | green
  | blue
```

Documentation before an inductive constructor moves with the constructor and
uses the same alternative base:

```lean
inductive Result where
  /-- A successful result. -/
  | ok
```

Constructor parameters flow at binder boundaries. A long constructor result
type moves to a leading `:` continuation line.

```lean
inductive ConstructorResultLayout where
  | intro (fields : List Field)
    : ConstructorResultLayoutForInput schema (ConstructorValue.object fields)
        (TypeRef.named typeName)
```

The arm base remains stable while long constructor binders flow beneath it:

```lean
inductive ConstructorBinderLayout where
  | intro (first : FirstTypeWithEnoughCharactersForLayoutTesting)
    (second : SecondTypeWithEnoughCharactersForLayoutTesting)
    : Result
```

This is the same base/flow relationship used by equation arms: `|` owns the
arm base, while binders and patterns own continuation opportunities.

`deriving` begins on its own line when it follows a multiline structure or
inductive declaration:

```lean
structure Response where
  data : Nat
  errors : Nat := 0
deriving Repr
```

Mutual declaration bodies are indented beneath `mutual`, and `end` returns to
the `mutual` column:

```lean
mutual
  def first : Nat := second
  def second : Nat := first
end
```

## Function applications

Applications use flow layout. The function and the longest fitting prefix of
arguments remain on the current line; later arguments wrap with one additional
indentation level.

```lean
veryLongFunctionName child children additionalArgumentOne
  additionalArgumentTwo additionalArgumentThree
```

Lean's `leading_parser` syntax describes a parser constructor with ordinary
positional arguments, so those arguments use the same flow layout instead of
letting a nested parser-combinator expression establish their indentation.

In a `do` conditional with an `if let ... ← action` condition, an overflowing
action breaks from the conditional's base:

```lean
if let some value ←
    lookupLongOptionalValue firstArgument secondArgument then
  use value
```

Nested applications choose their continuation from the nested application's
structural base rather than aligning every line under the first argument:

```lean
singleFieldResult responseName
  (completeValue schema resolvers variableValues
    fuel' fieldDefinition.outputType
    (field :: fields) resolved)
```

If the flat application overflows, valid argument-boundary breaks from the
source are tried before automatic flow wrapping. Original indentation is
ignored and recomputed.

An argument whose formatted shape spans multiple lines is treated as not
fitting on the current line. The application therefore breaks before that
argument, including structured arguments such as `let`, `if`, `match`, and
structure instances. No special-case preference between parent and child
breaks is needed.

A parenthesized syntax extension uses the same balanced delimiter rule as core
parenthesized syntax. Width pressure may use the body's ordinary application
breaks before considering the closing boundary; the extension does not need a
kind-specific rule.

When a tactic is parsed as a spaced application, a multiline lambda,
conditional, or nested application uses the tactic application's structural
base. It does not align beneath the final character of `exact`, `refine`, or a
similar tactic head.

When two or more structured parenthesized proof arguments require peer layout,
every parenthesized argument uses the same peer boundary. This keeps ordinary
terms, named arguments, type ascriptions, proof arguments, and their closing
delimiters on one application continuation base. An ordinary argument after a
parenthesized peer starts a new run at that base; its remaining fitting
arguments stay on the same line. When that run itself wraps, it remains a run of
peer arguments rather than treating its first argument as a new function head:

```lean
exact inductionPrinciple motives
  (by
    exact firstCase)
  firstValue secondValue thirdValue
  (by
    exact secondCase)
```

An application with exactly one simple parenthesized proof argument may test
that complete argument in its compact form. It remains on one line when the
whole application fits; multiple proof arguments keep the peer structure above.

A multiline named argument keeps its closing parenthesis attached to the final
line of the value:

```lean
Nat.recOn
  (motive :=
    fun n =>
      Nat)
  0
  fun _ ih => ih
```

When a trailing line comment prevents attachment, the closing parenthesis moves
to a new line at the opening parenthesis's column.

When the value and closing parenthesis do not fit together, the value break after
`:=` takes priority over detaching the parenthesis:

```lean
f
  (right :=
    [longApplication firstArgument secondArgument thirdArgument])
```

Projection chains do not break before a dot. The application around a
projection may still wrap:

```lean
def postfixProjection (schema : Schema) (typeName objectName : Name) :=
  (schema.getPossibleTypes typeName).contains objectName
```

## Unary prefix operators

A unary prefix operator stays on the first line of its operand. If the operand
is a long application, the application wraps at its own argument boundaries;
the formatter does not leave the prefix on a line by itself.

```lean
theorem duplicateArgumentNamesRejected
    : ¬ GraphQL.Validation.argumentsValid sampleSchema
          [testEpisodeArgumentDefinition] [] duplicateEpisodeArguments := by
  exact proof
```

This applies consistently to logical negation `¬`, compact bang `!`, numeric
negation `-`, and bitwise complement `~~~`. Postfix operators follow their own
right-attached layout.

## Tail indentation

leanfmt breaks before an infix operator so the operator visually connects the
lines in its chain:

```lean
  f argumentOne argumentTwo
  + g argumentOne argumentTwo
  + h argumentOne argumentTwo
```

Consecutive operators with the same parser binding powers are formatted as one
chain, even when their spellings differ, such as alternating `+` and `-`.
Chained pipe projections use the same peer layout, with every `|>.member`
continuation at one base.
The same leading-operator layout applies inside an indented declaration body:

```lean
def equality : Prop :=
  veryLongLeftHandSideExpressionWithEnoughCharactersForLayoutTesting
  = veryLongRightHandSideExpressionWithEnoughCharactersForLayoutTesting
```

A multiline operand needs a visible local hierarchy. A match keeps its normal
internal arm indentation, but the whole block moves inward when it is the
non-final operand of an infix expression:

```lean
  match value with
    | first => firstResult
    | second => secondResult
  + other
```

The formatter describes this with a segment's **head indentation** and **tail
indentation**:

- A segment starts at a physical column. Its head indentation is the nearest
  indentation column at or after that start column.
- Its tail indentation is the minimum indentation for later lines when the
  segment becomes multiline.
- A non-final infix operand lifts its tail one level beyond the following
  operator. Other infix-like syntax and flow layout use the same principle.

When a segment begins between indentation columns, its head rounds up. This
keeps a nested block clear of the following operator:

```lean
  -> match value with
        | first => firstResult
        | second => secondResult
      ∧ other
```

Tail indentation is a floor, not an amount added to every rule indentation. An
application already asks for one continuation level, so a tail at that level
does not push it farther:

```lean
  someFunction firstLongArgument
    nextArgument
  + g
```

The floor accumulates through nested non-final operands. This makes each inner
operator deeper than the operator containing it, while the application keeps
its own continuation relationship:

```lean
  someFunction firstLongArgument
      nextArgument
    + g
  :: h
```

In real code, an application inside `::`, itself inside `++`, follows the same
hierarchy:

```lean
  (Selection.field responseName fieldName arguments fieldDirectives
        fieldSelectionSet
      :: inlineSelectionSet
    ++ rest)
```

Some constructs have several relative indentation levels. A multiline
structure places fields one level inside its braces while its closing brace
returns to the brace level:

```lean
something
+ {
    field1 := value1,
    field2 := value2
  }
  - g
```

When tail indentation raises such a construct, leanfmt shifts the complete
break profile together. It does not independently clamp every line, because
that would flatten the difference between fields and the closing brace:

```lean
-> {
      field1 := value1,
      field2 := value2
    }
    :: g
```

Parentheses stay tight around their expression, and the expression inside owns
the breaks. When a parenthesized chain is a non-final operand, its operators
remain one level deeper than the surrounding chain:

```lean
((executableFieldSelections [first]
    ++ middle
    ++ executableFieldSelections [later])
  ++ suffix)
```

## Propositions and arrows

leanfmt distinguishes the layout role of arrow chains from their syntactic
context:

- arrows in ordinary function types flow and wrap only where required;
- arrows in theorem statements, `Prop` definition bodies, quantifier bodies,
  and logical operands break as a balanced logical group.

<!-- leanfmt-test -->
```lean
theorem valid
    : SourceSelectionSetIsWellFormed
      -> NormalizedSelectionSetPreservesResponseKeys
      -> FragmentExpansionPreservesExecutionSemantics := by
  exact proof
```

Logical and equality operators recognized for balanced proposition layout are
`->`, `→`, `∧`, `∨`, `/\`, `\/`, and `=`. A lower-precedence outer connector
breaks before nested higher-precedence expressions.

```lean
def leadingEqualityAndOperand : Prop :=
  firstCondition = secondConditionWithEnoughCharactersForLayoutTesting
  ∧ thirdConditionWithEnoughCharactersForLayoutTesting
  ∧ finalConditionWithEnoughCharactersForLayoutTesting
```

`≠` receives normal spacing but is not included in the balanced logical group.

Nested disjunction and conjunction groups retain a visible local hierarchy:

```lean
def parenthesizedDisjunctionChain (schema : Schema) (implementation expected : Name)
    : Prop :=
  (schema.isLeafType implementation
    ∧ schema.isLeafType expected
    ∧ implementation = expected)
  ∨ (schema.isCompositeType implementation
      ∧ schema.isCompositeType expected
      ∧ ∀ objectName,
          schema.typeIncludesObject implementation objectName
          -> schema.typeIncludesObject expected objectName)
```

## Quantifiers and lambdas

A quantifier stays flat when it fits. Otherwise its body begins after the comma
and is indented one level.

<!-- leanfmt-test -->
```lean
def mixedAdjacentQuantifiersLong : Prop :=
  ∃ objectType,
    ∀ typeCondition,
      typeCondition ∈ declaredCompositeTypeConditionsForCurrentSelection
      -> objectType ∈ schema.getPossibleTypes typeCondition
```

Adjacent quantifiers of the same kind do not add another indentation level
between them:

```lean
def adjacentQuantifiers : Prop :=
  ∀ x, ∀ y, body x y
```

Different quantifiers add a level when their bodies wrap:

<!-- leanfmt-test -->
```lean
def mixedQuantifierPredicate : Prop :=
  ∃ objectType,
    ∀ typeCondition,
      selectedObjectSatisfiesTheDeclaredCompositeTypeCondition objectType typeCondition
```

Long binder sequences can flow between complete binder groups and between names
belonging to one untyped binder group. A continuation between complete binder
groups aligns with the first binder, rounded forward to the indentation grid
when necessary; wrapping does not add another indentation level. The continued
binder's internal type annotation and body then use their own structural
indentation.

<!-- leanfmt-test -->
```lean
def resolverInvariant : Prop :=
  ∀ {ObjectRef : Type} (resolvers : Resolvers ObjectRef)
    variableValues fuel (source : ResolverValue ObjectRef),
    accepts resolvers variableValues fuel source
```

Names inside one untyped binder group remain one peer flow and use that group's
ordinary continuation indentation:

```lean
∃ leftPrefixFields leftPrefixErrors rightPrefixFields rightPrefixErrors
    leftSuffixFields leftSuffixErrors rightSuffixFields rightSuffixErrors,
  predicate
```

Source breaks between fitting adjacent quantifiers are not preserved merely
because they appeared in the input.

Binder operators such as `⨆`, `⨅`, `∑`, and `∫` use the same comma/body
layout. This rule is recognized from the operator token and syntax shape, so
generated notation node names do not need individual mappings. Decorated forms
such as `∀ᵉ` share the classification of their base operator. A trailing
notation suffix after the body, such as `∂μ` on an integral, stays with the body
and does not move the comma/body break. When an extended binder's type wraps,
the `:` stays with the first line of the type.

```lean
⨆ p : Index,
  ∑ i ∈ Finset.range p.size, value p i
```

A lambda breaks after `=>` and indents its body one level:

```lean
fun objectType =>
  normalizeSelectionSet schema objectType selections
```

## `let` expressions

A `let` body always begins on a separate line. A long right-hand side begins
after `:=` with one additional indentation level:

```lean
def withLet : Result :=
  let normalizedSubselections :=
    normalizeSelectionSet schema returnType mergedSubselections
  normalizedSubselections
```

The body aligns with `let`, not with the right-hand side. When a `let` appears
after a leading operator, leanfmt may insert alignment space before `let` so the
result also satisfies Lean's indentation-sensitive parser.

For a layout-delimited `let`, Lean must be able to tell where the right-hand
side ends and the body begins. When the body starts with syntax that could also
be another function argument, leanfmt aligns `let` to an indentation column.
This may retain a space after an opening parenthesis:

```lean
result
  = ( let matching :=
        computeMatchingSelections schema responseName selections
      useMatchingSelections matching)
```

When the leading syntax cannot continue a function application, the body
boundary is already unambiguous and the opening parenthesis remains tight.
Examples include bodies starting with `match`, `if`, `let`, or `by`:

```lean
result
  = (let collectedRest :=
        collectRest selections
      match lookupField fieldName with
      | none => collectedRest
      | some field => field :: collectedRest)
```

leanfmt asks Lean's active term parser this question at function-argument
precedence. Syntax extensions declared or imported by a project therefore
follow their own declared precedence instead of a built-in keyword list.

An explicitly semicolon-delimited `let` does not depend on indentation for this
boundary and keeps tight parenthesis spacing.

A structured right-hand side keeps its own layout below `:=`:

```lean
def letMatchRhs : Result :=
  let current :=
    match selection with
    | .field responseName fieldName => collectField responseName fieldName
    | .inlineFragment selectionSet => collectFields selectionSet
  current
```

Monadic bindings follow the same header/RHS split. Both identifier and pattern
bindings keep `←` on the header and break after it when necessary:

```lean
let (normalizedSource, normalizeMs) ←
  timeIO <| pure <| normalize source
```

A `suffices` body likewise begins on a separate line after the proposition and
its `from` proof. The body remains offside from the proof expression so Lean's
layout parser cannot absorb it into that expression.

When `by` introduces the proof directly, it stays on the proposition line and
the protected proof body uses the `suffices` base rather than the proposition's
ending column:

```lean
suffices VeryLongProposition firstArgument secondArgument by
  exact proof
this
```

A `have` body also begins on a separate line. When its declaration does not fit,
the assigned value breaks after `:=` while the following body remains aligned
with the `have` expression rather than the assigned value. A dependent return
type that begins with `have` owns its layout base after the signature colon, so
both its proof and following type stay offside after the signature is reflowed.

When `have` is the right operand of a broken low-priority pipe, it uses the same
mandatory start alignment as `let`. The operator stays with the first line of
the `have` expression, and the expression and its body share one aligned base:

<!-- leanfmt-test -->
```lean
def pipeHave :=
  resolveSelectionSetWithAccumulatedFragmentAndDirectiveContext
  <|  have value := 0
      value
```

When a `by` proof is the right operand of `<|`, the introducer remains attached
to the operator and its body starts one level below the surrounding expression
base. If the tactic shell before that proof is already multiline, the proof body
uses the shell's rounded local base; it does not inherit an incidental inline
token column:

```lean
theorem pipedProof : True :=
  id <| by
    exact True.intro
```

An unparenthesized proof containing multiple tactics always starts its body on
the following line. The required layout boundary prevents the first tactic from
joining `by` and changing the scope of later tactics or declarations:

```lean
have h : NeZero value := NeZero.mk <| by
  rw [value]
  exact one_ne_zero
```

A `have` that contains a protected proof body moves with the complete `<|`
right-operand group so the proof and its following body continue to move as one
layout island.
When the final proof argument of `have`, `suffices`, or another tactic contains
a structural `cases` or `induction`, the tactic header remains protected while
the proof body exposes the existing elimination layout. Nested alternative
bodies therefore receive the same two-level indentation as a direct
elimination tactic.
A single-token tactic prefix such as `classical` shares that structural base
with a following tactic authored at the same proof indentation, even when Lean
inserts transparent tactic-sequence wrappers between them. A deeper source
continuation remains nested. An elimination tactic's `with` remains attached
to its header and alternatives align with the complete prefixed tactic.

A term-taking tactic retains its tactic prefix while the final term keeps its
own structural layout. For an ordinary application, this keeps the tactic and
function head together and lets the application indent continuation arguments:

```lean
apply veryLongProofFunction
  firstArgument secondArgument
```

The same parser-context rule covers `exact`, `refine`, and extension tactics;
structural proof operands remain governed by the existing proof-island rules.
A final parenthesized proof whose tactic content occupies one source line may
rejoin its `by` when the complete application fits:

```lean
exact Or.inl (by simp [hselected])
```

Authored multiline tactic content remains protected.
A detached braced tactic sequence moves as one protected body beneath its
owning tactic. Its internal relative indentation is retained rather than
recomputed from the brace's previous source column.
A term-taking tactic remains attached to the first line of its operand. The
operand then follows its own structural rules: an application head starts a new
base for ordinary argument flow, while a lambda keeps its introducer with the
tactic and breaks its body after `=>`. Two or more parenthesized proof arguments
break as peers rather than nesting under one another. An unbreakable head that
cannot fit with its tactic is retained as a logically indented overflow. An
authored break can remain only when the surrounding proof is emitted as a
protected source-layout island.

When attached closing delimiters or a projection member make the terminal line of a
preserved proof overflow, a parser-identified tactic application may use its ordinary
argument breaks. The closing suffix stays attached to the final argument line instead
of occupying a line by itself.

An attached proof suffix uses the same fit decision after its owner has been
laid out. Thus `<| by simp` remains together when that final line fits, while
an overflowing proof breaks after `by` and indents from the operand's base.
Earlier breaks inside the owner do not force this suffix body to break.

When a registered tactic parser ends a header with a keyword-owned term body,
the keyword stays with the body application head. A bracketed tactic argument
flows from the tactic base, while the body application's arguments use their
own structural base:

```lean
simpa [firstNormalizationLemma, secondNormalizationLemma,
  thirdNormalizationLemma]
  using veryLongProofTerm firstArgument secondArgument
    thirdArgument
```

If the bracketed collection itself cannot fit, it uses the ordinary collection
breaks from that same base. The suffix and body head remain attached:

```lean
simpa [firstNormalizationLemma,
  secondNormalizationLemma,
  thirdNormalizationLemma]
  using proof
```

A registered tactic suffix followed by a tactic sequence owns that sequence in
the same way. A source-detached body indents from the tactic header, while an
inline body remains compact:

```lean
project_simp? proposition says
  exact True.intro
```

The same body layout applies when a complete tactic-sequence entry ends in
`=>` followed by a custom parser sequence. The tactic context establishes the
ownership, so conversion sequences and similar extensions do not need
syntax-specific line-break rules. Existing structural alternatives keep their
dedicated body indentation.

## Conditionals

A fitting conditional stays on one line. A multiline conditional breaks as a
balanced branch structure:

```lean
if responseName == group.fst then
  (responseName, fields ++ group.snd) :: rest
else
  (responseName, fields) :: addExecutableGroup group rest
```

An `else if` keeps the nested `if` on the `else` line rather than adding an
extra branch indentation. The complete chain is one balanced structure: if one
branch boundary breaks, every `then` branch and the final `else` branch break
together.

```lean
if firstCondition then
  firstResult
else if secondCondition then
  secondResult
else
  finalResult
```

Dependent clauses use that same chain shape and keep each named condition with
its branch header:

```lean
if hzero : n = 0 then
  zero
else if hleft : cut = 0 then
  left
else if hright : cut = n then
  right
else
  middle
```

The final condition line keeps `then`. A long infix condition wraps by its own
infix rule before detaching the branch suffix:

```lean
else if rule.binding == .global
        && rule.head == operation.key
        && !globalCompiled[ruleIndex]! then
  secondResult
```

Accepted source breaks between branch boundaries can keep an intentional
multiline conditional even when a flatter form fits. Because conditionals are
non-flow rules, any accepted branch break activates the complete balanced
branch layout.

A dependent condition keeps a fitting `name : condition` header together. If
the condition itself must wrap, it uses the same named-discriminant layout as a
named `cases` target and breaks before `:` rather than leaving `name :` alone:

```lean
if h
    : VeryLongPredicate firstArgument secondArgument
        thirdArgument then
  firstResult
else
  secondResult
```

An authored break after `:` does not override this shared layout: a fitting
named discriminant flattens, while an overflowing one uses the structural break
before `:`.

Conditionals normally start on an indentation boundary. An immediately preceding
opening parenthesis keeps tight spacing instead; branch indentation rounds up from
the off-column `if`. This exception affects only the first line:

```lean
pure
  (if firstCheck && secondCheck && thirdCheck && fourthCheck then
      0
    else
      1)
```

Thus an input that breaks only before `else` does not remain half-broken:

```lean
if arg.startsWith "-" then
  .error s!"unknown option: {arg}"
else
  loop options (FilePath.mk arg :: files) rest
```

An infix-like condition with a bar-separated right operand, such as `matches`,
keeps its first alternative with the leading operator. Later alternatives are
packed while they fit and their bars align with that first alternative:

```lean
if kind
    matches `Monotone | `Antitone | `StrictMono
            | `StrictAnti | `MonotoneOn then
  true
else
  false
```

## Match expressions and equation arms

Match alternatives start on their own lines and align with the `match` keyword:

```lean
match variableValues with
| [] => none
| (variableName, value) :: rest =>
    if variableName = name then some value else lookupVariableValue? rest name
```

A long discriminant is formatted by its own rules before `with`:

```lean
match veryLongFunctionName child children additionalArgumentOne
        additionalArgumentTwo with
| [] => 0
| _ :: rest => rest.length
```

When the discriminant is itself a match, the outer `with` returns to the outer
match base instead of remaining on the final inner alternative:

```lean
match
    match value with
    | none => false
with
| false => fallback
| true => available
```

Multiple match discriminants are grouped as peers. They use flow layout with
breaks after commas, aligned under the first discriminant following `match`, so
only the suffix that does not fit moves:

```lean
match defaultPresentChildIndexBefore? segment index,
      defaultPresentChildIndexAfter? segment index,
      defaultPresentChildIndexAround? segment index with
| some before,
  some after,
  some around => result
```

When an explicit motive precedes the discriminants, a wrapped discriminant uses
the `match` base instead of inheriting the motive's ending column:

```lean
match (motive := (x : Input) → Property x → Result) x,
  proofOfProperty x with
| value, proof => result
```

Multiple patterns in one arm are balanced peers. If a pattern boundary breaks,
all comma-separated pattern boundaries break together. A long right-hand side
breaks after `=>` and is indented two levels from the arm start:

```lean
| .field responseName fieldName arguments directives selectionSet =>
    collectFields schema responseName fieldName arguments directives selectionSet
```

Pattern lists also flow when they become too long:

```lean
| parentType,
  _source,
  .field responseName fieldName arguments directives selectionSet =>
    body
```

Short right-hand sides stay on the arrow line. A `by` or `do` right-hand side
also stays attached to `=>`, and its nested body owns subsequent breaks.

```lean
| .some value => do
    process value
| .none => by
    exact defaultValue
```

Equation-style declaration arms follow the same alternative layout.

Tactic alternatives that own a body after `=>` use the same two-level body
indentation. An arrowless tactic alternative owns only its pattern; subsequent
tactics remain peers in the surrounding tactic sequence because indenting them
under the alternative changes Lean's parse. The owned indentation remains
structural when a protected, unbreakable proof line becomes longer than the
configured width after moving to that column.

A standalone tactic alternative similarly owns a following tactic sequence:

```lean
case branch =>
  exact True.intro
```

Correcting one owned alternative does not reformat an unrelated peer tactic
combinator chain; that chain remains an authored-layout proof island.

`cases` and `induction` keep `with` on the complete header. Their alternatives
align with the tactic, and a multiline alternative body is indented two levels
beneath it:

<!-- leanfmt-test -->
```lean
theorem casesExample (value : Nat) : True := by
  cases value with
  | zero =>
      exact True.intro
  | succ value =>
      exact True.intro
```

An unlabeled parenthesized default alternative keeps its opening parenthesis
with `with`. The enclosed tactic sequence uses one body indentation, and a
fitting closing parenthesis stays on its final line:

```lean
theorem inductionDefault (value : Nat) : True := by
  induction value with (
    simp only [Nat.add_zero]
    simp only [Nat.zero_add])
  | zero => trivial
  | succ value hypothesis => trivial
```

A long `induction ... generalizing` header wraps between generalized identifiers.
The target remains attached to `induction`, and the final identifier remains
attached to `with`:

```lean
  induction path generalizing leftVariableDefinitions
      rightVariableDefinitions
      leftCurrentSelectionSet
      rightCurrentSelectionSet leftFuel rightFuel with
  | nil => trivial
```

A pattern lambda uses its own physical start as the arm base. When `fun` starts
between indentation boundaries, as after an opening parenthesis, the arms round
up to the next boundary rather than inheriting the enclosing expression's base:

```lean
applyHandler
  (fun
    | .none => defaultValue
    | .some value => process value)
```

Alternative patterns are grouped as peers before rendering, like operands in
an infix chain. This lets multiple `|` patterns wrap in a balanced layout at
the arm base instead of inheriting accidental nesting from the raw parser
tree. A pattern alias such as `fieldSelection@(` stays attached; if its nested
pattern must wrap, the break occurs inside the parentheses before the arm's
`=>` body layout is considered.

Indentation is relative to the arm's logical base, even when the enclosing
expression starts at a shifted physical column. The formatter does not align
continuations under an incidental token column. Comments between a pattern,
separator, and body remain attached to their source tokens and are reindented
with the resulting arm rather than changing which rule wins.

## `do` expressions

`do` remains attached to the expression that introduces it, and statements
start one level below it:

```lean
def run : IO Unit := do
  IO.println "start"
  IO.println "done"
```

Statement boundaries are structural and remain on separate lines.

A semicolon explicitly joins adjacent statements. The same policy applies to
inline tactic sequences: the boundaries immediately beside `;` are suppressed
while the complete joined sequence fits. A tactic that starts on a later source
line after a trailing semicolon retains its peer boundary because that line
structure delimits the preceding proof.

```lean
IO.println usage; pure 0
```

If it does not fit, the do-sequence rules provide the normal balanced
statement boundaries, and the following statement returns to the peer
statement base:

```lean
IO.println veryLongMessage;
pure result
```

A refutable `let` with a fallback treats its value and fallback as separate
branches. A multiline value begins one level below `:=`; `|` aligns with
`let`, as required by Lean's layout parser:

```lean
let .some value :=
  lookupVeryLongValue firstArgument secondArgument thirdArgument
| return none
consume value
```

If only the fallback is long, the value can remain on the header while the
break occurs before `|`:

```lean
let .some value := candidate
| recoverVeryLongValue firstArgument secondArgument thirdArgument
consume value
```

The successful continuation also aligns with `let`. Formatting inside the
value and fallback remains the responsibility of their own expression rules.
When the fallback is a multiline `do` sequence, its statements begin one level
beneath `|`, while the successful continuation returns to the `let` column. This
applies to both `←` and `:=` fallback declarations:

```lean
let some value ← candidate
| -- Recover locally.
  let fallback ← recover
  return fallback
consume value
```

```lean
let some value := candidate
| do
    reportFailure
    return none
consume value
```

## Subtypes

A subtype stays compact when it fits:

```lean
{ target : ScopedField // target ∈ fields }
```

When it does not fit, it breaks before `//`:

```lean
{ targetField : ScopedFieldVeryLongTypeNameLikeThis
  // targetField ∈ targetFieldsWithVeryLongName }
```

The property can then use ordinary proposition layout.

Set builders keep the opening delimiter, binder, and `|` in one header. When the
predicate does not fit, it breaks after `|`, and a detached closing delimiter
aligns with `{`:

```lean
{ value |
  firstLongCondition value
    ∧ secondLongCondition value
}
```

## Arrays, tuples, anonymous constructors, and structure instances

Single-line collections remain compact:

```lean
[firstItem, secondItem, thirdItem]
(firstValue, secondValue)
{ data := .null, errors := 1 }
```

Multi-item arrays, tuples, and anonymous constructors use balanced layout: when
the collection does not fit, the opening boundary, every item boundary, and the
closing delimiter break together.

```lean
[
  veryLongFirstArrayItemNameUsedForLayoutTesting,
  veryLongSecondArrayItemNameUsedForLayoutTesting,
  veryLongThirdArrayItemNameUsedForLayoutTesting
]
```

A protected proof body does not protect its surrounding anonymous constructor or
structure instance. When the proof retains a source line break, the surrounding
construct still applies its balanced item, field, and closing-delimiter breaks.

For generated two-operand notation, a comma-like trailing separator remains
attached to the first operand and the continuation starts after it:

```lean
custom⟪firstVeryLongOperand,
  secondVeryLongOperand⟫
```

leanfmt does not add a trailing comma.

A single multiline item keeps an outer list compact around that item. This
supports common nested forms such as a list containing one structure value:

```lean
[{
  parentType := parentType,
  responseName := responseName,
  fieldName := fieldName
}]
```

An `#[...]` array literal uses balanced delimiters when its singleton item is
multiline. Existing balanced source breaks are also retained when array items
carry authored comments.

An atom ending in an opening delimiter is treated as that delimiter for line
layout. This keeps prefixed forms such as `#[...]` balanced even when the first
item begins with a normally tight token such as `(`.

Structure instances with several fields break after `{`, between fields, and
before `}`. Comma-separated fields remain flat when they fit. Newline-separated
fields without commas are structurally multiline because Lean's layout syntax
requires those boundaries.

A field value introduced by `by` or `do` keeps that introducer with `:=`, just
as a declaration value does. The body breaks after the introducer:

```lean
{
  map value := by
    exact proof
}
```

An optional `private` modifier belongs to the complete field value. When a
lambda value wraps, its body uses the field-value base instead of the source
column where `fun` happened to begin:

```lean
def wrapped : Wrapper where
  field :=
    private fun veryLongArgumentName =>
      veryLongArgumentName
```

Multiple sources in a structure update align as peers before the `with` suffix:

```lean
{
  firstParent,
  secondParent with
    field := value
}
```

The opening and closing brace breaks are balanced. A type ascription following a
multiline structure keeps `:` with its type:

```lean
response
  = ({
        data := ResponseValue.object fields,
        errors := errors
      }
      : Response)
```

A fitting constructor remains completely flat, including a nested constructor
used as a field value. If a constructor argument is too wide, its containing
application breaks before `{`. In a declaration body, the declaration first
uses its normal break after `:=`; only then does the constructor apply its own
field breaks. This avoids splitting a short constructor merely because the
source happened to break inside it.

```lean
def recordOperand :=
  {
    parentType := validParentWithEnoughCharactersForLayoutTesting,
    responseName := responseNameWithEnoughCharactersForLayoutTesting
  }
```

A multiline tuple uses the same balanced opening, item, and closing shape:

```lean
def tupleOperand :=
  (
    firstItemNameWithEnoughCharactersForLayoutTesting,
    secondItemNameWithEnoughCharactersForLayoutTesting,
  )
```

Existing punctuation is preserved, so the trailing comma above remains because
it was present in the source; leanfmt does not add one.

Anonymous constructors use the same balanced shape. Single-field constructors
remain flat when they fit.

<!-- leanfmt-test -->
```lean
def setoidWitness :=
  ⟨
    fun firstExpression secondExpression =>
      expressionsAreDefinitionallyEquivalent firstExpression secondExpression,
    fun expression => ⟨definitionallyEquivalentRefl expression⟩,
    fun equivalenceProof => equivalenceProof.symm,
    fun firstEquivalenceProof secondEquivalenceProof =>
      firstEquivalenceProof.trans secondEquivalenceProof
  ⟩
```

Structure updates follow the same field layout:

```lean
def normalizeOperation (schema : Schema) (operation : Operation) : Operation :=
  {
    operation with
      selectionSet :=
        normalizeSelectionSet schema operation.rootType operation.selectionSet
  }
```

The update source is one level inside the braces, and fields are one level
inside the `with` header. A short update remains flat, such as
`{ operation with selectionSet := selectionSet }`.

## Unknown and custom syntax

Every parser token remains present even when leanfmt has no explicit rule for a
syntax node. Core, Std, and Mathlib syntax are first-class support targets; other
packages are not expected to require one new leanfmt rule for every extension.

For imported and locally declared syntax, leanfmt first reads the active
`ParserDescr`. Printing annotations such as `ppSpace`, `ppLine`, grouping, indentation,
and dedentation become conservative syntax-layout facts. A descriptor that proves a
word-like head followed by one term or identifier operand reuses ordinary application
layout, including when `ppSpace` appears as a separate combinator. Parser-owned trailing
term and tactic bodies similarly reuse existing suffix/body ownership.

When metadata does not prove a layout, the generic rule examines only the node's
immediate child shape:

- a token between two child nodes is treated as an infix-like break point;
- otherwise, boundaries between present children become flow break points;
- token spelling is not used to guess the meaning of the syntax.

This provides conservative wrapping for long custom syntax without pretending to
understand it. A registered Lean formatter is recorded as useful coverage information,
but its executable `Std.Format` output is not used unless it can be aligned losslessly
to source tokens. Formatting developers can use `--check-exception` to identify syntax
whose parser annotations and structural shape are still insufficient.

A generated term node with exactly three present children whose first and last
children are the same atom is treated as a symmetric delimited term. Its
delimiters stay attached while the enclosed expression applies its own layout.
This covers notation such as `|x|` and `‖x‖` without enumerating delimiter
spellings. Generated postfix term nodes likewise keep their final atom attached
to the preceding expression while that expression applies its own layout.

A generated prefix-index term is recognized when its immediate opening atom
ends in `[`, a later immediate atom is `]`, and an operand follows that closing
delimiter. It may break inside the index or before following operands, but never
before the closing `]`. Requiring immediate atoms keeps this delimiter-shape
recognition from inspecting an operand's nested token spelling. Trailing
separator tokens inside the brackets do not introduce break points. A generated
three-child delimiter wrapper with no following operand remains an ordinary
delimited term.

Unknown syntax is lossless, but its whitespace is not guaranteed to remain
byte-for-byte unchanged. Multiline custom braced term syntax is a conservative
exception: leanfmt keeps its source layout instead of canonicalizing indentation for
an extension-owned DSL.

A short custom syntax declaration can remain flat:

```lean
syntax "widget" : term
```

If a larger custom node overflows, its parser-child boundaries determine the
generic wrapping until leanfmt has a dedicated rule for that syntax.

## Diagnostics

Diagnostics observe source without changing formatting behavior. The compact
bang diagnostic reports `!f a b` because it can be read as either compact
negation or a function application.

These spellings are accepted and preserved:

```lean
!value
! value
! f a b
! (f a b)
```

The ambiguous `!f a b` spelling is reported but not automatically rewritten.

## Formatting guarantees

leanfmt is designed around these checks:

1. Parsing succeeds with Lean's parser and active syntax extensions.
2. Reconstructing the syntax tree reproduces the parsed source.
3. Formatting preserves the code-token sequence and the exact text inside comments;
   whitespace between code and comment fragments is normalized for comparison.
4. Formatting is idempotent: formatting the output again produces the same
   output.

The third and fourth properties are available as internal CLI checks for
formatter development. They describe formatter correctness, not style options
that ordinary users need to select.

Formatting may require more than one parse/render pass because a first layout
can expose a different accepted source-break shape to the next pass. leanfmt
iterates to a fixed point with a hard limit of four passes. If an intermediate
result does not parse, repeats a previously seen result, or does not converge
within that limit, leanfmt emits a warning and returns the original source
rather than treating the fallback as a hard formatter error.
