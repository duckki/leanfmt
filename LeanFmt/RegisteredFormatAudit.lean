import LeanFmt.Formatter.SpaceRules
import Lean.PrettyPrinter.Formatter

namespace LeanFmt.RegisteredFormatAudit

open Lean

/-!
This module is an audit-only adapter for Lean's executable formatter registrations.
It translates an exactly aligned symbolic `Std.Format` into a candidate expressed in
leanfmt's structural rule vocabulary. It is never imported by the production formatter.
-/

inductive GroupBehavior where
  | allOrNone
  | fill
deriving BEq, Repr

structure GroupRef where
  id : Nat
  behavior : GroupBehavior
deriving BEq, Repr

inductive BreakKind where
  | soft
  | hard
deriving BEq, Repr

structure BreakObservation where
  tokenIndex : Nat
  indentLevels : Nat
  kind : BreakKind
  groups : Array GroupRef
  sourceTags : Array Nat
deriving BEq, Repr

structure SymbolicLayout where
  tokenCount : Nat
  breaks : Array BreakObservation
deriving BEq, Repr

inductive ChildRole where
  | missing
  | atom
  | operand
deriving BEq, Repr

structure StructuralKey where
  kind : SyntaxNodeKind
  children : Array ChildRole
deriving BEq, Repr

inductive BreakPolicy where
  | mandatory
  | allOrNone
  | fill
deriving BEq, Repr

structure ChildBreak where
  childIndex : Nat
  indentLevels : Nat
  policy : BreakPolicy
  groups : Array GroupRef
deriving BEq, Repr

inductive RuleFamily where
  | atomic
  | application
  | prefix
  | postfix
  | infix
  | delimited
  | suffixBody
  | sequence
  | structural
deriving BEq, Repr

structure RuleCandidate where
  key : StructuralKey
  family : RuleFamily
  breaks : Array ChildBreak
  nestedBreakCount : Nat
deriving BEq, Repr

structure Audit where
  layout : SymbolicLayout
  candidate : RuleCandidate
deriving BEq, Repr

inductive Rejection where
  | notRegistered
  | missingSourceSpan
  | incompleteSourceCoverage
  | sourceComment
  | formatterFailure (message : String)
  | leadingWhitespace
  | multilineToken (tokenIndex : Nat)
  | tokenMismatch (tokenIndex : Nat) (expected found : String)
  | layoutInsideToken (tokenIndex tokenOffset : Nat)
  | unsupportedWhitespace (tokenIndex : Nat)
  | unsupportedIndentation (tokenIndex : Nat) (columns : Int)
  | columnAlignment (tokenIndex : Nat) (force : Bool)
  | trailingOutput (text : String)
  | incompleteOutput (tokenIndex : Nat)
deriving BEq, Repr

inductive Result where
  | inferred (audit : Audit)
  | rejected (reason : Rejection)
deriving BEq, Repr

structure Options where
  indentWidth : Nat := 2
  leanOptions : Lean.Options := {}
deriving Inhabited

private structure InspectionState where
  tokenIndex : Nat := 0
  tokenOffset : Nat := 0
  hasBoundaryLayout : Bool := false
  breaks : Array BreakObservation := #[]
  nextGroupId : Nat := 0

private def groupBehavior : Std.Format.FlattenBehavior -> GroupBehavior
  | .allOrNone => .allOrNone
  | .fill => .fill

private def breakPolicy (observation : BreakObservation) : BreakPolicy :=
  match observation.kind with
  | .hard => .mandatory
  | .soft =>
      match observation.groups.back? with
      | some group =>
          match group.behavior with
          | .allOrNone => .allOrNone
          | .fill => .fill
      | none => .mandatory

private def indentationLevels (tokenIndex indentWidth : Nat) (columns : Int)
    : Except Rejection Nat := do
  if columns < 0 then
    throw <| .unsupportedIndentation tokenIndex columns
  let columns := columns.toNat
  if indentWidth == 0 || columns % indentWidth != 0 then
    throw <| .unsupportedIndentation tokenIndex columns
  pure <| columns / indentWidth

private def recordBreak
    (tokens : Array SyntaxTree.Token) (indentWidth : Nat) (columns : Int)
    (kind : BreakKind) (groupPath : List GroupRef) (tagPath : List Nat)
    (state : InspectionState)
    : Except Rejection InspectionState := do
  if state.tokenOffset != 0 then
    throw <| .layoutInsideToken state.tokenIndex state.tokenOffset
  if state.tokenIndex == 0 then
    throw .leadingWhitespace
  if tokens.size <= state.tokenIndex then
    throw <| .trailingOutput "line break"
  if state.hasBoundaryLayout then
    throw <| .unsupportedWhitespace state.tokenIndex
  let indentLevels <- indentationLevels state.tokenIndex indentWidth columns
  pure
    {
      state with
        hasBoundaryLayout := true
        breaks :=
          state.breaks.push
            {
              tokenIndex := state.tokenIndex
              indentLevels
              kind
              groups := groupPath.reverse.toArray
              sourceTags := tagPath.reverse.toArray
            }
    }

private def consumeText
    (tokens : Array SyntaxTree.Token) (indentWidth : Nat) (columns : Int)
    (groupPath : List GroupRef) (tagPath : List Nat)
    : List Char -> InspectionState -> Except Rejection InspectionState
  | [], state => pure state
  | char :: rest, state => do
      if state.tokenOffset == 0 && (char == ' ' || char == '\n') then
        if char == '\n' then
          let state <- recordBreak tokens indentWidth columns .hard groupPath tagPath
                        state
          consumeText tokens indentWidth columns groupPath tagPath rest state
        else if state.tokenIndex == 0 then
          throw .leadingWhitespace
        else if tokens.size <= state.tokenIndex then
          throw <| .trailingOutput "space"
        else if state.hasBoundaryLayout then
          throw <| .unsupportedWhitespace state.tokenIndex
        else
          consumeText tokens indentWidth columns groupPath tagPath rest
            { state with hasBoundaryLayout := true }
      else if char == '\t' || char == '\r' then
        throw <| .unsupportedWhitespace state.tokenIndex
      else
        let some token := tokens[state.tokenIndex]?
        | throw <| .trailingOutput (toString char)
        let chars := token.lexeme.toList
        let some expected := chars[state.tokenOffset]?
        | throw <| .tokenMismatch state.tokenIndex token.lexeme (toString char)
        if expected != char then
          throw <| .tokenMismatch state.tokenIndex (toString expected) (toString char)
        let tokenOffset := state.tokenOffset + 1
        let state :=
          if tokenOffset == chars.length then
            {
              state with
                tokenIndex := state.tokenIndex + 1
                tokenOffset := 0
                hasBoundaryLayout := false
            }
          else
            { state with tokenOffset, hasBoundaryLayout := false }
        consumeText tokens indentWidth columns groupPath tagPath rest state

private partial def inspectDocument
    (tokens : Array SyntaxTree.Token) (indentWidth : Nat)
    (columns : Int) (groupPath : List GroupRef) (tagPath : List Nat)
    (document : Std.Format) (state : InspectionState)
    : Except Rejection InspectionState := do
  match document with
  | .nil => pure state
  | .line => recordBreak tokens indentWidth columns .soft groupPath tagPath state
  | .align force => throw <| .columnAlignment state.tokenIndex force
  | .text text =>
      consumeText tokens indentWidth columns groupPath tagPath text.toList state
  | .nest indentation document =>
      inspectDocument tokens indentWidth (columns + indentation) groupPath tagPath
        document state
  | .append left right =>
      let state <- inspectDocument tokens indentWidth columns groupPath tagPath left state
      inspectDocument tokens indentWidth columns groupPath tagPath right state
  | .group document behavior =>
      let reference := { id := state.nextGroupId, behavior := groupBehavior behavior }
      let state := { state with nextGroupId := state.nextGroupId + 1 }
      inspectDocument tokens indentWidth columns (reference :: groupPath) tagPath
        document state
  | .tag sourcePosition document =>
      inspectDocument tokens indentWidth columns groupPath (sourcePosition :: tagPath)
        document state

def inspectFormat
    (tokens : Array SyntaxTree.Token) (document : Std.Format) (indentWidth : Nat := 2)
    : Except Rejection SymbolicLayout := do
  for index in List.range tokens.size do
    let some token := tokens[index]?
    | throw <| .incompleteOutput index
    if token.lexeme.contains '\n' || token.lexeme.contains '\r' then
      throw <| .multilineToken index
  let state <- inspectDocument tokens indentWidth 0 [] [] document {}
  if state.tokenIndex != tokens.size || state.tokenOffset != 0 then
    throw <| .incompleteOutput state.tokenIndex
  pure { tokenCount := tokens.size, breaks := state.breaks }

def sourceHasInterTokenComment (source : String) (tokens : Array SyntaxTree.Token)
    : Bool :=
  let rec go : List SyntaxTree.Token -> Bool
    | left :: right :: rest =>
        Formatter.SpaceRules.hasCommentStart
          (SyntaxTree.sourceText source left.span.stop right.span.start)
        || go (right :: rest)
    | _ => false
  go tokens.toList

def sourceTokensForSyntax (moduleTree : SyntaxTree.Module) (stx : Syntax)
    : Except Rejection (Array SyntaxTree.Token) := do
  let some start := stx.getPos? (canonicalOnly := true)
  | throw .missingSourceSpan
  let some stop := stx.getTailPos? (canonicalOnly := true)
  | throw .missingSourceSpan
  let tokens :=
    moduleTree.sourceOrderedTokens.filter
      fun token =>
        SyntaxTree.tokenComesFromSource moduleTree.source token
        && start <= token.span.start
        && token.span.stop <= stop
  let some first := tokens[0]?
  | throw .incompleteSourceCoverage
  let some last := tokens.back?
  | throw .incompleteSourceCoverage
  if first.span.start == start && last.span.stop == stop then
    pure tokens
  else
    throw .incompleteSourceCoverage

private structure ChildRange where
  childIndex : Nat
  startToken : Nat
  stopToken : Nat

private def tokenStartIndex? (tokens : Array SyntaxTree.Token) (position : String.Pos.Raw)
    : Option Nat :=
  (List.range tokens.size).find?
    fun index =>
      tokens[index]?.any fun token => token.span.start == position

private def tokenStopIndex? (tokens : Array SyntaxTree.Token) (position : String.Pos.Raw)
    : Option Nat := do
  let index <- (List.range tokens.size).find?
                fun index =>
                  tokens[index]?.any fun token => token.span.stop == position
  pure <| index + 1

private def childRanges (tokens : Array SyntaxTree.Token) (children : Array Syntax)
    : Array ChildRange :=
  ((List.range children.size).filterMap
    fun childIndex => do
      let child <- children[childIndex]?
      let start <- child.getPos? (canonicalOnly := true)
      let stop <- child.getTailPos? (canonicalOnly := true)
      let startToken <- tokenStartIndex? tokens start
      let stopToken <- tokenStopIndex? tokens stop
      if startToken < stopToken then
        some { childIndex, startToken, stopToken }
      else
        none).toArray

private partial def flattenLogicalChild (parentKind : SyntaxNodeKind) (stx : Syntax)
    : Array Syntax :=
  match stx with
  | .node _ childKind children =>
      if childKind == parentKind || childKind == `null then
        children.foldl
          (fun flattened child =>
            flattened ++ flattenLogicalChild parentKind child)
          #[]
      else
        #[stx]
  | _ => #[stx]

def normalizedChildren (stx : Syntax) : Array Syntax :=
  stx.getArgs.foldl
    (fun flattened child => flattened ++ flattenLogicalChild stx.getKind child) #[]

private def childRole : Syntax -> ChildRole
  | .missing => .missing
  | .atom .. => .atom
  | .ident .. | .node .. => .operand

def structuralKey (stx : Syntax) : StructuralKey :=
  {
    kind := stx.getKind
    children := (normalizedChildren stx).map childRole
  }

private def ChildRole.isAtom : ChildRole -> Bool
  | .atom => true
  | _ => false

private def ChildRole.isOperand : ChildRole -> Bool
  | .operand => true
  | _ => false

private def directChildIndex? (ranges : Array ChildRange) (tokenIndex : Nat)
    : Option Nat :=
  let matching := ranges.filter fun range => range.startToken == tokenIndex
  if matching.size == 1 then matching[0]?.map (·.childIndex) else none

private def isDelimited (tokens : Array SyntaxTree.Token) : Bool :=
  match tokens[0]?, tokens.back? with
  | some first, some last => first.isOpeningDelimiter && last.isClosingDelimiter
  | _, _ => false

private def inferFamily
    (facts : ParserLayout.KindFacts) (tokens : Array SyntaxTree.Token)
    (roles : Array ChildRole) (breaks : Array ChildBreak) (nestedBreakCount : Nat)
    : RuleFamily :=
  let breakIndexes := breaks.map (·.childIndex)
  let breaksCoverOperandTail :=
    1 < roles.size
    && roles.all (·.isOperand)
    && (List.range' 1 (roles.size - 1)).all fun index => breakIndexes.contains index
  if breaks.isEmpty then
    if nestedBreakCount == 0 then .atomic else .structural
  else if facts.infixPrecedence?.isSome then
    .infix
  else if facts.ownedBody?.isSome then
    .suffixBody
  else if facts.spacedApplication then
    .application
  else if isDelimited tokens then
    .delimited
  else if breaksCoverOperandTail then
    .application
  else
    match roles[0]?, roles.back? with
    | some first, some last =>
        if roles.size == 3
            && first.isOperand
            && roles[1]?.any (·.isAtom)
            && last.isOperand then
          .infix
        else if first.isAtom && last.isOperand then
          .prefix
        else if first.isOperand && last.isAtom then
          .postfix
        else if 1 < breaks.size then
          .sequence
        else
          .structural
    | _, _ => .structural

private def inferCandidate
    (facts : ParserLayout.KindFacts) (tokens : Array SyntaxTree.Token)
    (stx : Syntax) (layout : SymbolicLayout)
    : RuleCandidate :=
  let children := normalizedChildren stx
  let ranges := childRanges tokens children
  let childBreaks :=
    layout.breaks.filterMap
      fun observation => do
        let childIndex <- directChildIndex? ranges observation.tokenIndex
        some
          {
            childIndex
            indentLevels := observation.indentLevels
            policy := breakPolicy observation
            groups := observation.groups
          }
  let roles := children.map childRole
  let nestedBreakCount := layout.breaks.size - childBreaks.size
  {
    key := { kind := stx.getKind, children := roles }
    family := inferFamily facts tokens roles childBreaks nestedBreakCount
    breaks := childBreaks
    nestedBreakCount
  }

def stableRuleCandidate? (audits : Array Audit) : Option RuleCandidate :=
  match audits.toList with
  | first :: second :: rest =>
      if (second :: rest).all fun audit => audit.candidate == first.candidate then
        some first.candidate
      else
        none
  | _ => none

private def registeredFormat
    (env : Environment) (source fileName : String) (stx : Syntax)
    (options : Lean.Options)
    : IO (Except String Std.Format) := do
  let context : Core.Context :=
    {
      fileName
      fileMap := FileMap.ofString source
      options
      ref := stx
    }
  let state : Core.State := { env }
  try
    let action :=
      PrettyPrinter.format (PrettyPrinter.Formatter.formatterForKind stx.getKind) stx
    let (document, _) <- Core.CoreM.toIO action context state
    pure <| .ok document
  catch exception =>
    pure <| .error (toString exception)

def auditSyntax
    (env : Environment) (moduleTree : SyntaxTree.Module) (stx : Syntax)
    (fileName : String := "<registered-format-audit>") (options : Options := {})
    : IO Result := do
  if ParserLayout.metadataSourceForKind env stx.getKind != .registered then
    pure <| .rejected .notRegistered
  else
    match sourceTokensForSyntax moduleTree stx with
    | .error reason => pure <| .rejected reason
    | .ok tokens =>
        if sourceHasInterTokenComment moduleTree.source tokens then
          pure <| .rejected .sourceComment
        else
          let formatted <- registeredFormat env moduleTree.source fileName stx
                            options.leanOptions
          match formatted with
          | .error message => pure <| .rejected (.formatterFailure message)
          | .ok document =>
              match inspectFormat tokens document options.indentWidth with
              | .error reason => pure <| .rejected reason
              | .ok layout =>
                  let facts := ParserLayout.kindFacts env options.leanOptions stx.getKind
                  let candidate := inferCandidate facts tokens stx layout
                  pure <| .inferred { layout, candidate }

end LeanFmt.RegisteredFormatAudit
