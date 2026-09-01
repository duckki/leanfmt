import LeanFmt.Formatter.LineBreakRules
import LeanFmt.Formatter.Rebase
import LeanFmt.Formatter.SpaceRules

namespace LeanFmt
namespace Formatter
namespace OriginalTree

def indentationSpaces : Nat :=
  2

private def lineWidth (text : String) : Nat :=
  text.length

private def spaces (count : Nat) : String :=
  String.ofList <| List.replicate count ' '

private def charsAfterLastNewline (text : String) : String :=
  let rec loop : List Char → List Char → String
    | [], current => String.ofList current.reverse
    | '\n' :: rest, _ => loop rest []
    | char :: rest, current => loop rest (char :: current)
  loop (SpaceRules.normalizeLineEndings text).toList []

private def leadingWhitespace (line : String) : String :=
  (line.takeWhile SpaceRules.isHorizontalWhitespace).toString

private def shiftLineIndent (sourceColumn targetColumn : Nat) (line : String) : String :=
  if line.isEmpty then
    line
  else if sourceColumn <= targetColumn then
    spaces (targetColumn - sourceColumn) ++ line
  else
    let removeCount := min (sourceColumn - targetColumn) (leadingWhitespace line).length
    (line.drop removeCount).toString

private def shiftBoundaryIndent (sourceColumn targetColumn : Nat) (line : String)
    : String :=
  if line.isEmpty && sourceColumn <= targetColumn then
    spaces (targetColumn - sourceColumn)
  else
    shiftLineIndent sourceColumn targetColumn line

private def rebaseLines (sourceColumn targetColumn : Nat) : List String → List String
  | [] => []
  | [line] => [shiftBoundaryIndent sourceColumn targetColumn line]
  | line :: rest =>
      shiftLineIndent sourceColumn targetColumn line
      :: rebaseLines sourceColumn targetColumn rest

private def rebaseTextIndent (sourceColumn targetColumn : Nat) (text : String) : String :=
  if sourceColumn == targetColumn then
    text
  else
    match (SpaceRules.normalizeLineEndings text).splitOn "\n" with
    | [] => text
    | first :: rest =>
        String.intercalate "\n" <| first :: rebaseLines sourceColumn targetColumn rest

def sourceContinuationIndent? (text : String) : Option Nat :=
  (SpaceRules.normalizeLineEndings text).splitOn "\n"
  |>.drop 1
  |>.foldl
      (fun minimum? line =>
        let indentation := (leadingWhitespace line).length
        if indentation == line.length then
          minimum?
        else
          match minimum? with
          | some minimum => some (min minimum indentation)
          | none => some indentation)
      none

private def treeContinuationIndent?
    (sourceMap : SyntaxTree.SourcePositionMap) (tree : SyntaxTree.Tree)
    : Option Nat := do
  let firstToken ← tree.firstToken?
  let firstLine := sourceMap.lineNumberAt firstToken.span.start
  tree.tokens.foldl
    (fun minimum? token =>
      if firstLine < sourceMap.lineNumberAt token.span.start then
        let column := sourceMap.columnAt token.span.start
        match minimum? with
        | some minimum => some (min minimum column)
        | none => some column
      else
        minimum?)
    none

private def treeTrailingDelimiterIndent?
    (sourceMap : SyntaxTree.SourcePositionMap) (tree : SyntaxTree.Tree)
    : Option Nat := do
  let firstToken ← tree.firstToken?
  let firstLine := sourceMap.lineNumberAt firstToken.span.start
  tree.tokens.toList.reverse
  |>.takeWhile (fun token => SpaceRules.isDelimiterCloserToken token.lexeme)
  |>.foldl
      (fun minimum? token =>
        if firstLine < sourceMap.lineNumberAt token.span.start
            && SpaceRules.hasLineStructure token.leading.text then
          let column := sourceMap.columnAt token.span.start
          match minimum? with
          | some minimum => some (min minimum column)
          | none => some column
        else
          minimum?)
      none

private def rebaseMultilineSourceSlice (targetColumn : Nat) (text : String) : String :=
  match (SpaceRules.normalizeLineEndings text).splitOn "\n" with
  | [] | [_] => text
  | first :: rest =>
      let sourceContinuationColumn := (sourceContinuationIndent? text).getD targetColumn
      String.intercalate "\n"
      <| first :: rebaseLines sourceContinuationColumn targetColumn rest

private def floorLineIndent (minimum : Nat) (line : String) : String :=
  if line.isEmpty then
    line
  else
    let indentation := (leadingWhitespace line).length
    if minimum <= indentation then line else spaces (minimum - indentation) ++ line

private def floorContinuationIndent (minimum : Nat) (text : String) : String :=
  match (SpaceRules.normalizeLineEndings text).splitOn "\n" with
  | [] => ""
  | first :: rest =>
      String.intercalate "\n" <| first :: rest.map (floorLineIndent minimum)

private def rebaseTokenLexeme
    (treeSourceColumn treeTargetColumn sourceColumn targetColumn : Nat)
    (token : SyntaxTree.Token)
    : String :=
  if SpaceRules.isCommentLexeme token.lexeme
      && SpaceRules.hasLineStructure token.lexeme then
    let rebased := SpaceRules.reindentCommentLexeme token.lexeme sourceColumn targetColumn
    if (sourceContinuationIndent? token.lexeme).any (· < treeSourceColumn) then
      floorContinuationIndent treeTargetColumn rebased
    else
      rebased
  else
    token.lexeme

private inductive RebaseUnit where
  | sourceToken (token : SyntaxTree.Token)
  | syntaxComment (span : SyntaxTree.Span)

private def RebaseUnit.span : RebaseUnit → SyntaxTree.Span
  | .sourceToken token => token.span
  | .syntaxComment span => span

private partial def rebaseUnits
    : List SyntaxTree.Token → List SyntaxTree.Span → List RebaseUnit
  | [], _ => []
  | token :: tokens, [] => .sourceToken token :: rebaseUnits tokens []
  | token :: tokens, span :: spans =>
      if span.stop <= token.span.start then
        rebaseUnits (token :: tokens) spans
      else if span.start == token.span.start then
        let remaining := tokens.dropWhile fun token => token.span.stop <= span.stop
        .syntaxComment span :: rebaseUnits remaining spans
      else
        .sourceToken token :: rebaseUnits tokens (span :: spans)

private def columnAfterAppend (column : Nat) (text : String) : Nat :=
  if SpaceRules.hasLineStructure text then
    lineWidth <| charsAfterLastNewline text
  else
    column + lineWidth text

private def rebaseTreeText
    (source : String) (sourceMap : SyntaxTree.SourcePositionMap)
    (tree : SyntaxTree.Tree)
    (sourceColumn targetColumn : Nat)
    (rebaseTrivia : Bool := true)
    : String :=
  let rec loop (cursor : String.Pos.Raw) (outputColumn : Nat) (parts : List String)
      : List RebaseUnit → List String
    | [] => parts
    | unit :: rest =>
        let span := unit.span
        let trivia := SyntaxTree.sourceText source cursor span.start
        let trivia :=
          if rebaseTrivia then
            rebaseTextIndent sourceColumn targetColumn trivia
          else
            trivia
        let outputColumn := columnAfterAppend outputColumn trivia
        let text :=
          match unit with
          | .sourceToken token =>
              rebaseTokenLexeme sourceColumn targetColumn
                (sourceMap.columnAt token.span.start) outputColumn token
          | .syntaxComment span =>
              let comment := SyntaxTree.sourceText source span.start span.stop
              let rebased :=
                SpaceRules.reindentCommentLexeme comment
                  (sourceMap.columnAt span.start) outputColumn
              if (sourceContinuationIndent? comment).any (· < sourceColumn) then
                floorContinuationIndent targetColumn rebased
              else
                rebased
        loop span.stop (columnAfterAppend outputColumn text) (text :: trivia :: parts)
          rest
  match rebaseUnits tree.tokens.toList tree.syntaxCommentSpans with
  | [] => ""
  | units@(first :: _) =>
      String.join <| (loop first.span.start targetColumn [] units).reverse

private def fittingTargetColumn
    (source : String) (sourceMap : SyntaxTree.SourcePositionMap)
    (tree : SyntaxTree.Tree) (sourceText : String)
    (sourceColumn targetColumn lineWidthLimit suffixWidth : Nat)
    : Nat :=
  if targetColumn <= sourceColumn then
    targetColumn
  else
    let rebasedText := rebaseTreeText source sourceMap tree sourceColumn targetColumn
    let sourceLines := (SpaceRules.normalizeLineEndings sourceText).splitOn "\n"
    let rebasedLines := (SpaceRules.normalizeLineEndings rebasedText).splitOn "\n"
    let rec maximumOverflow (lineIndex maximum : Nat) : List String → List String → Nat
      | sourceLine :: sourceRest, rebasedLine :: rebasedRest =>
          let sourceWidth :=
            sourceLine.length
            + (if lineIndex == 0 then sourceColumn else 0)
            + (if sourceRest.isEmpty then suffixWidth else 0)
          let rebasedWidth :=
            rebasedLine.length
            + (if lineIndex == 0 then targetColumn else 0)
            + (if rebasedRest.isEmpty then suffixWidth else 0)
          let allowedWidth := max lineWidthLimit sourceWidth
          let overflow :=
            if allowedWidth < rebasedWidth then
              rebasedWidth - allowedWidth
            else
              0
          maximumOverflow (lineIndex + 1) (max maximum overflow) sourceRest rebasedRest
      | _, _ => maximum
    let overflow := maximumOverflow 0 0 sourceLines rebasedLines
    let roundedReduction :=
      ((overflow + indentationSpaces - 1) / indentationSpaces) * indentationSpaces
    targetColumn - min (targetColumn - sourceColumn) roundedReduction

private def currentLineAfterAppend (currentLine text : String) : String :=
  if text.contains '\n' || text.contains '\r' then
    charsAfterLastNewline text
  else
    currentLine ++ text

private def tokenStartsCurrentLine (currentLine : String) (token : SyntaxTree.Token)
    : Bool :=
  if !currentLine.endsWith token.lexeme then
    false
  else
    let prefixLength := currentLine.length - token.lexeme.length
    (currentLine.take prefixLength).all SpaceRules.isHorizontalWhitespace

private def bodyColumnAfterOpeningDelimiter?
    (currentLine : String) (token : SyntaxTree.Token)
    : Option Nat :=
  if !currentLine.endsWith token.lexeme then
    none
  else
    let prefixLength := currentLine.length - token.lexeme.length
    let precedingText :=
      SpaceRules.stripLineEndWhitespace <| (currentLine.take prefixLength).toString
    if SyntaxTree.lexemeEndsWithOpeningDelimiter precedingText then
      some (precedingText.length - 1 + indentationSpaces)
    else
      none

private def isProofBodyTree (tree : SyntaxTree.Tree) : Bool :=
  match tree with
  | .node (.proofBody _) _ => true
  | _ => false

private partial def containsProofTree : SyntaxTree.Tree → Bool
  | .missing => false
  | .leaf _ => false
  | tree@(.node _ children) =>
      isProofBodyTree tree || children.any containsProofTree

private partial def containsAttachedProofTerm : SyntaxTree.Tree → Bool
  | .missing | .leaf _ => false
  | .node (.raw `Lean.Parser.Term.byTactic) _
  | .node (.raw `Lean.Parser.Term.byTactic') _ => true
  | .node _ children => children.any containsAttachedProofTerm

private def proofBodyContainsTacticLayoutOwner : SyntaxTree.Tree → Bool
  | .node (.proofBody containsOwner) _ => containsOwner
  | _ => false

private def proofBodyContainsNestedProof : SyntaxTree.Tree → Bool
  | .node (.proofBody _) children => children.any containsAttachedProofTerm
  | _ => false

private def isQuotationTree : SyntaxTree.Tree → Bool
  | .node (.raw `Lean.Parser.Term.quot) _ => true
  | .node (.raw `Lean.Parser.Term.precheckedQuot) _ => true
  | .node (.raw `Lean.Parser.Term.dynamicQuot) _ => true
  | .node (.raw `Lean.Parser.Command.quot) _ => true
  | .node (.raw `Lean.Parser.Tactic.quot) _ => true
  | .node (.raw `Lean.Parser.Tactic.quotSeq) _ => true
  | .node (.tactic `Lean.Parser.Tactic.quot _ _ _ _) _ => true
  | .node (.tactic `Lean.Parser.Tactic.quotSeq _ _ _ _) _ => true
  | .node (.raw `token_antiquot) _ => true
  | .node kind _ =>
      let kindName := SyntaxTree.nodeKindName kind
      kindName == "antiquotName" || SpaceRules.containsSubstring kindName ".antiquot"
  | _ => false

private partial def containsQuotationTree : SyntaxTree.Tree → Bool
  | .missing => false
  | .leaf _ => false
  | tree@(.node _ children) =>
      isQuotationTree tree || children.any containsQuotationTree

private def isQqSyntaxTree : SyntaxTree.Tree → Bool
  | .node (.raw `Qq.«termQ(__)») _ => true
  | .node (.infixChain `Qq.«term_=Q_») _ => true
  | _ => false

private def isProofWidgetsJsxSyntaxTree : SyntaxTree.Tree → Bool
  | .node kind _ =>
      (SyntaxTree.nodeKindName kind).startsWith "ProofWidgets.Jsx."
  | _ => false

private def isLeanJsonSyntaxTree : SyntaxTree.Tree → Bool
  | .node kind _ =>
      (SyntaxTree.nodeKindName kind).startsWith "Lean.Json."
  | _ => false

private def isBatteriesLibraryNoteSyntaxTree : SyntaxTree.Tree → Bool
  | .node kind _ =>
      (SyntaxTree.nodeKindName kind).startsWith "Batteries.Util.LibraryNote."
  | _ => false

private def isLayoutSensitiveCommand : SyntaxTree.Tree → Bool
  | .node (.raw `Lean.Parser.Command.syntax) _ => true
  | .node (.raw `Lean.Parser.Command.syntaxAbbrev) _ => true
  | .node (.raw `Lean.Parser.Command.macro_rules) _ => true
  | .node (.raw `Lean.Parser.Command.elab) _ => true
  | .node (.raw `Lean.Parser.Command.elab_rules) _ => true
  | .node (.raw `Lean.Parser.«command_Simproc_decl_(_):=_») _ => true
  | .node (.raw `Lean.Parser.«command__Simproc__[_]_(_):=_») _ => true
  | .node (.raw `Lean.Parser.«command_Dsimproc_decl_(_):=_») _ => true
  | .node (.raw `Lean.Parser.«command__Dsimproc__[_]_(_):=_») _ => true
  | .node (.raw `Lean.runCmd) _ => true
  | .node (.raw `Batteries.Tactic.Alias.alias) _ => true
  | .node (.raw `Batteries.Tactic.Alias.aliasLR) _ => true
  | _ => false

private def isTacticSequenceKind (kind : Lean.SyntaxNodeKind) : Bool :=
  SyntaxTree.Tree.isTacticSequenceKind kind

private def coreTacticKindName (kindName : String) : Bool :=
  SyntaxTree.isCoreTacticKindName kindName

private def isCalcTree : SyntaxTree.Tree → Bool
  | tree => SyntaxTree.Tree.isCalcTree tree

private def isStructuredCalcTree : SyntaxTree.Tree → Bool
  | .node _ children =>
      children.any
        fun
        | .node .calcBody _ => true
        | _ => false
  | _ => false

private def isProtectedTacticTree : SyntaxTree.Tree → Bool
  | .node (.raw `Mathlib.Tactic.dsimpPercent) _ => false
  | .node (.tactic `Mathlib.Tactic.dsimpPercent _ _ _ _) _ => false
  | tree@(.node kind _) =>
      let kindName := SyntaxTree.nodeKindName kind
      if isQuotationTree tree then
        false
      else
        match kind with
        | .tactic rawKind _ isOwner containsOwner _ =>
            !isTacticSequenceKind rawKind
            && !isOwner
            && !containsOwner
            && !(tree.isSpacedApplicationTactic && containsAttachedProofTerm tree)
        | .infixChain rawKind =>
            coreTacticKindName (toString rawKind) && !tree.containsTacticLayoutOwner
        | .raw rawKind =>
            coreTacticKindName kindName
            && !isTacticSequenceKind rawKind
            && !SyntaxTree.Tree.isTacticLayoutOwner tree
        | _ => false
  | _ => false

private def tokenHasCommentTrivia (token : SyntaxTree.Token) : Bool :=
  SpaceRules.hasCommentStart token.leading.text
  || SpaceRules.hasCommentStart token.trailing.text

private partial def treeHasCommentTrivia : SyntaxTree.Tree → Bool
  | .missing => false
  | .leaf token => tokenHasCommentTrivia token
  | .node _ children => children.any treeHasCommentTrivia

private def tokenHasLineBreakTrivia (token : SyntaxTree.Token) : Bool :=
  SpaceRules.hasLineStructure token.leading.text
  || SpaceRules.hasLineStructure token.trailing.text

private partial def treeHasLineBreakTrivia : SyntaxTree.Tree → Bool
  | .missing => false
  | .leaf token => tokenHasLineBreakTrivia token
  | .node _ children => children.any treeHasLineBreakTrivia

private def treeHasInternalLineBreakTrivia (tree : SyntaxTree.Tree) : Bool :=
  match tree.tokens.toList with
  | [] | [_] => false
  | tokens =>
      let internalLeadingHasLineBreak :=
        tokens.drop 1
        |>.any
            fun token =>
              SpaceRules.hasLineStructure token.leading.text
      let internalTrailingHasLineBreak :=
        tokens.dropLast.any
          fun token =>
            SpaceRules.hasLineStructure token.trailing.text
      internalLeadingHasLineBreak || internalTrailingHasLineBreak

private def isCustomBracedTermSyntaxKindName (kindName : String) : Bool :=
  kindName != "«term{_}»"
  && (kindName.startsWith "«term" || SpaceRules.containsSubstring kindName ".«term")
  && SpaceRules.containsSubstring kindName "{_}"

private def isCustomBracedTermSyntaxTree : SyntaxTree.Tree → Bool
  | tree@(.node kind _) =>
      isCustomBracedTermSyntaxKindName (SyntaxTree.nodeKindName kind)
      && treeHasLineBreakTrivia tree
  | _ => false

private def isCustomSubalgebraAdjoinSyntaxTree : SyntaxTree.Tree → Bool
  | .node
      (.raw `Algebra.Subalgebra.AlgHom.Subalgebra.Subalgebra.Algebra.subalgebra_adjoin)
      _ =>
      true
  | _ => false

private def isCommentSensitiveMatchExpr : SyntaxTree.Tree → Bool
  | tree@(.node (.raw `Lean.Parser.Term.matchExpr) _) =>
      treeHasCommentTrivia tree
  | _ => false

private def isSyntaxCommentTree : SyntaxTree.Tree → Bool
  | .node (.raw kind) _ => SyntaxTree.isSyntaxCommentKind kind
  | _ => false

private def isProofLambdaTree (tree : SyntaxTree.Tree) : Bool :=
  LineBreakRules.treeFirstLexeme? tree == some "fun" && containsProofTree tree

private def isQuotationLayoutIsland (tree : SyntaxTree.Tree) : Bool :=
  match tree with
  | .node (.raw `Lean.Parser.Term.set_option) _ =>
      containsQuotationTree tree
  | _ => false

private def isProofLayoutIsland (tree : SyntaxTree.Tree) : Bool :=
  match tree with
  | tree@(.node (.tactic `Lean.Parser.Tactic.paren _ _ _ _) children) =>
      treeHasInternalLineBreakTrivia tree
      && (SyntaxTree.Tree.node (.proofBody true) children).proofBodyHasMultipleTactics
  | .node .application children =>
      let rec laterArgumentHasProofLambda (previous : List SyntaxTree.Tree)
          : List SyntaxTree.Tree → Bool
        | [] => false
        | argument :: rest =>
            (isProofLambdaTree argument
              && previous.any
                  fun previousArgument =>
                    containsProofTree previousArgument
                    && treeHasInternalLineBreakTrivia previousArgument)
            || laterArgumentHasProofLambda (argument :: previous) rest
      match children.toList.drop 1 with
      | [] | [_] => false
      | first :: rest => laterArgumentHasProofLambda [first] rest
  | .node (.raw `Lean.Parser.Command.declValEqns) _ =>
      containsProofTree tree
  | .node (.raw `«term{_}») _ =>
      containsProofTree tree
  | .node (.raw `Lean.Parser.Term.show) children =>
      let hasFromTerm :=
        children.any
          fun child =>
            match child with
            | .node (.raw `Lean.Parser.Term.fromTerm) _ => true
            | _ => false
      let hasQuantifiedResult :=
        children.any
          fun child =>
            match child with
            | .node (.raw kind) _ => LineBreakRules.rawKindIsQuantifier kind
            | _ => false
      containsProofTree tree && !(hasFromTerm && hasQuantifiedResult)
  | _ => false

private def proofLayoutRebasesFromFirstToken : SyntaxTree.Tree → Bool
  | .node (.raw `Lean.Parser.Term.anonymousCtor) _
  | .node (.tactic `Lean.Parser.Tactic.paren _ _ _ _) _
  | .node (.raw `«term{_}») _ => true
  | _ => false

private def isAttributeModifierBlock (tree : SyntaxTree.Tree) : Bool :=
  match tree with
  | .node (.raw `Lean.Parser.Command.declModifiers) _ =>
      LineBreakRules.treeContainsLexeme "@[" tree
  | .node (.raw `Lean.Parser.Term.attrInstance) _ => true
  | .node (.raw `Lean.Parser.Term.attributes) _ => true
  | _ => false

private def isLayoutSensitiveSyntaxChoice : SyntaxTree.Tree → Bool
  | tree@(.node (.raw `choice) _) => treeHasInternalLineBreakTrivia tree
  | _ => false

private def ignoreNextMarker : String :=
  "-- leanfmt: off next"

private def isIgnoreNextTarget (tree : SyntaxTree.Tree) : Bool :=
  match tree with
  | .node (.raw `Lean.Parser.Module.module) _
  | .node (.raw `null) _ => false
  | .node _ _ =>
      tree.firstToken?.any fun token => token.leading.text.contains ignoreNextMarker
  | _ => false

inductive LayoutIslandKind where
  | ignored
  | proof
  | proofLayout
  | attributes
  | syntaxChoice
  | calc
  | commentSensitiveMatch
  | quotationLayout
  | quotation
  | qq
  | proofWidgetsJsx
  | leanJson
  | batteriesLibraryNote
  | layoutSensitiveCommand
  | mathlibTactic
  | customBracedTerm
  | customSubalgebraAdjoin
  | syntaxComment
deriving BEq, Repr

def classify? (tree : SyntaxTree.Tree) : Option LayoutIslandKind :=
  let tree :=
    match tree with
    | .node (.command kind) children => .node (.raw kind) children
    | tree => tree
  if isIgnoreNextTarget tree then
    some .ignored
  else if isProofBodyTree tree
          && !proofBodyContainsTacticLayoutOwner tree
          && !proofBodyContainsNestedProof tree then
    some .proof
  else if isProtectedTacticTree tree then
    some .mathlibTactic
  else if isProofLayoutIsland tree then
    some .proofLayout
  else if isAttributeModifierBlock tree then
    some .attributes
  else if isLayoutSensitiveSyntaxChoice tree then
    some .syntaxChoice
  else if isCalcTree tree && !isStructuredCalcTree tree then
    some .calc
  else if isCommentSensitiveMatchExpr tree then
    some .commentSensitiveMatch
  else if isQuotationLayoutIsland tree then
    some .quotationLayout
  else if isQuotationTree tree then
    some .quotation
  else if isQqSyntaxTree tree then
    some .qq
  else if isProofWidgetsJsxSyntaxTree tree then
    some .proofWidgetsJsx
  else if isLeanJsonSyntaxTree tree then
    some .leanJson
  else if isBatteriesLibraryNoteSyntaxTree tree then
    some .batteriesLibraryNote
  else if isLayoutSensitiveCommand tree then
    some .layoutSensitiveCommand
  else if isCustomBracedTermSyntaxTree tree then
    some .customBracedTerm
  else if isCustomSubalgebraAdjoinSyntaxTree tree then
    some .customSubalgebraAdjoin
  else if isSyntaxCommentTree tree then
    some .syntaxComment
  else
    none

@[inline]
def shouldEmit (tree : SyntaxTree.Tree) : Bool :=
  (classify? tree).isSome

inductive ContentLayout where
  | ordinary
  | proof
  | proofLayout
  | calc
  | quotation
deriving BEq, Repr

inductive MultilineLayoutPolicy where
  | structural
  | preserveWithoutRuleBreaks
deriving BEq, Repr

inductive FirstLinePolicy where
  | breakable
  | unbreakable
deriving BEq, Repr

inductive RelativeLayoutPolicy where
  | structural
  | retain
deriving BEq, Repr

inductive PendingIndentPolicy where
  | ignore
  | useWhenAvailable
deriving BEq, Repr

inductive AnchorPolicy where
  | layoutBase
  | preferParentRelative
deriving BEq, Repr

inductive FollowingCommentPolicy where
  | formatNormally
  | preserveSourceIndent
deriving BEq, Repr

inductive LeadingBoundaryPolicy where
  | preserveWithIsland
  | formatStructurally
deriving BEq, Repr

structure IslandPolicy where
  content : ContentLayout := .ordinary
  multiline : MultilineLayoutPolicy := .structural
  firstLine : FirstLinePolicy := .breakable
  relativeLayout : RelativeLayoutPolicy := .structural
  pendingIndent : PendingIndentPolicy := .ignore
  anchor : AnchorPolicy := .layoutBase
  followingComment : FollowingCommentPolicy := .formatNormally
  leadingBoundary : LeadingBoundaryPolicy := .preserveWithIsland
deriving BEq, Repr

structure IslandPlan where
  kind : LayoutIslandKind
  policy : IslandPolicy
deriving BEq, Repr

def policyFor : LayoutIslandKind → IslandPolicy
  | .proof =>
      {
        content := .proof
        multiline := .preserveWithoutRuleBreaks
        firstLine := .unbreakable
        relativeLayout := .retain
        pendingIndent := .useWhenAvailable
        followingComment := .preserveSourceIndent
      }
  | .proofLayout => { content := .proofLayout, firstLine := .unbreakable }
  | .attributes =>
      {
        multiline := .preserveWithoutRuleBreaks
        relativeLayout := .retain
        pendingIndent := .useWhenAvailable
      }
  | .syntaxChoice =>
      { multiline := .preserveWithoutRuleBreaks }
  | .calc =>
      {
        content := .calc
        firstLine := .unbreakable
        leadingBoundary := .formatStructurally
      }
  | .quotationLayout | .quotation =>
      {
        content := .quotation
        firstLine := .unbreakable
        relativeLayout := .retain
        pendingIndent := .useWhenAvailable
      }
  | .proofWidgetsJsx =>
      {
        firstLine := .unbreakable
        relativeLayout := .retain
        pendingIndent := .useWhenAvailable
        anchor := .preferParentRelative
      }
  | .layoutSensitiveCommand =>
      {
        relativeLayout := .retain
        pendingIndent := .useWhenAvailable
        followingComment := .preserveSourceIndent
      }
  | .mathlibTactic =>
      {
        firstLine := .unbreakable
        relativeLayout := .retain
        pendingIndent := .useWhenAvailable
      }
  | .syntaxComment => { pendingIndent := .useWhenAvailable }
  | .qq =>
      {
        firstLine := .unbreakable
        leadingBoundary := .formatStructurally
      }
  | .ignored
  | .commentSensitiveMatch
  | .leanJson
  | .batteriesLibraryNote
  | .customBracedTerm
  | .customSubalgebraAdjoin => {}

def planForKind (kind : LayoutIslandKind) : IslandPlan :=
  { kind, policy := policyFor kind }

def plan? (tree : SyntaxTree.Tree) : Option IslandPlan :=
  (classify? tree).map planForKind

private partial def wrapsBracketedCollection : SyntaxTree.Tree → Bool
  | .node _ children =>
      if SyntaxTree.outerDelimiterKind? children == some .bracket then
        true
      else
        let content := children.filter fun child => child.firstToken?.isSome
        content.size == 1 && content[0]?.any wrapsBracketedCollection
  | _ => false

def canUseStructuralOverflowFallback : SyntaxTree.Tree → Bool
  | .node (.raw `Lean.Parser.Term.anonymousCtor) _ => true
  | .node (.tactic _ _ _ _ true) _ => true
  | tree => classify? tree == some .mathlibTactic && wrapsBracketedCollection tree

def canUseStructuralLayoutAfterParentMove : SyntaxTree.Tree → Bool
  | .node .application _
  | .node (.raw `Lean.Parser.Term.anonymousCtor) _
  | .node (.raw `«term{_}») _ => true
  | _ => false

partial def startsWithEmission : SyntaxTree.Tree → Bool
  | .missing => false
  | .leaf _ => false
  | tree@(.node _ children) =>
      if (classify? tree).isSome then
        true
      else
        let rec loop (index : Nat) : Bool :=
          match children[index]? with
          | some child =>
              if SyntaxTree.Tree.firstToken? child |>.isSome then
                startsWithEmission child
              else
                loop (index + 1)
          | none => false
        loop 0

structure EmissionRequest where
  source : String
  sourceMap : SyntaxTree.SourcePositionMap
  currentLine : String
  currentIndent : Nat
  lastToken? : Option SyntaxTree.Token
  formattedLeadingWhitespace? : Option String
  pendingLeadingWhitespace? : Option String
  segmentIndentation : Nat
  layoutAnchor : Rebase.Anchor
  lineWidth : Nat
  lineFitSuffixWidth : Nat
  respectPendingIndent : Bool := false
  rebaseSourceTextTargetColumn? : Option Nat := none

structure Emission where
  text : String
  lastToken : SyntaxTree.Token
  preserveNextStandaloneCommentIndent : Bool

private def emitRebased? (request : EmissionRequest) (tree : SyntaxTree.Tree)
    (islandPlan? : Option IslandPlan)
    : Option Emission := do
  let firstToken ← SyntaxTree.Tree.firstToken? tree
  let lastToken ← SyntaxTree.Tree.lastToken? tree
  let content := islandPlan?.map (·.policy.content) |>.getD .ordinary
  let proof := content == .proof
  let proofLayout := content == .proofLayout
  let calcLayout := content == .calc
  let quotation := content == .quotation
  let usesPendingIndent :=
    (request.respectPendingIndent
      || islandPlan?.any fun plan => plan.policy.pendingIndent == .useWhenAvailable)
    && request.pendingLeadingWhitespace?.isSome
  let originalLeading :=
    match request.lastToken? with
    | some leftToken =>
        SyntaxTree.sourceText request.source leftToken.span.stop firstToken.span.start
    | none => firstToken.leading.text
  let leading :=
    request.formattedLeadingWhitespace?.getD
      (if usesPendingIndent then
          request.pendingLeadingWhitespace?.getD originalLeading
        else
          originalLeading)
  let quotationStartsOnLine :=
    quotation
    && (currentLineAfterAppend request.currentLine leading).all
        SpaceRules.isHorizontalWhitespace
  let leadingColumn := lineWidth <| currentLineAfterAppend request.currentLine leading
  let sourceText :=
    SyntaxTree.sourceText request.source firstToken.span.start lastToken.span.stop
  let sourceColumn := request.sourceMap.columnAt firstToken.span.start
  let retainsRelativeLayout :=
    islandPlan?.any fun plan => plan.policy.relativeLayout == .retain
  let retainsInlineRelativeLayout := retainsRelativeLayout || proofLayout || calcLayout
  let hasLineBreakTrivia :=
    retainsInlineRelativeLayout
    && (treeHasLineBreakTrivia tree
        || (quotation && SpaceRules.hasLineStructure sourceText))
  let originalLeadingHasLineStructure := SpaceRules.hasLineStructure originalLeading
  let formattedLeadingDetachesIsland :=
    !originalLeadingHasLineStructure && SpaceRules.hasLineStructure leading
  let detachedInlineProofBody :=
    proof
    && hasLineBreakTrivia
    && usesPendingIndent
    && !originalLeadingHasLineStructure
    && SpaceRules.hasLineStructure leading
  let multilineDelimitedProofBody :=
    proof
    && hasLineBreakTrivia
    && request.lastToken?.any
        fun token =>
          token.isOpeningDelimiter && request.currentLine.endsWith token.lexeme
  let inlineMultilineLayoutIsland :=
    retainsInlineRelativeLayout
    && hasLineBreakTrivia
    && (!originalLeadingHasLineStructure || proofLayout || quotationStartsOnLine)
    && !detachedInlineProofBody
    && !multilineDelimitedProofBody
  let inlineContinuationColumns? :=
    if !inlineMultilineLayoutIsland then
      none
    else
      let continuationIndent? :=
        (treeContinuationIndent? request.sourceMap tree).orElse
          fun _ => sourceContinuationIndent? sourceText
      match continuationIndent?, request.lastToken? with
      | some sourceIndent, some leftToken =>
          let sourceAnchor := request.sourceMap.columnAt leftToken.span.start
          let outputAnchor := lineWidth request.currentLine - leftToken.lexeme.length
          let movedIndent :=
            ({ sourceColumn := sourceAnchor, outputColumn := outputAnchor }
              : Rebase.Anchor).shiftColumn
              sourceIndent
          let movedIndent :=
            if quotationStartsOnLine then
              ({ sourceColumn, outputColumn := leadingColumn }
                : Rebase.Anchor).shiftColumn
                sourceIndent
            else
              movedIndent
          let structuralIndent :=
            if proof then
              (request.segmentIndentation + 1) * indentationSpaces
            else if proofLayout then
              if originalLeadingHasLineStructure then
                ({ sourceColumn, outputColumn := leadingColumn }
                  : Rebase.Anchor).shiftColumn
                  sourceIndent
              else if proofLayoutRebasesFromFirstToken tree then
                sourceIndent
              else
                request.currentIndent + indentationSpaces
            else if calcLayout then
              (leadingColumn / indentationSpaces + 1) * indentationSpaces
            else if quotationStartsOnLine then
              (leadingColumn / indentationSpaces + 1) * indentationSpaces
            else if quotation then
              request.currentIndent + indentationSpaces
            else if usesPendingIndent then
              leadingColumn
            else
              request.currentIndent
          let movedIndent :=
            if sourceAnchor < sourceIndent then
              movedIndent
            else
              sourceIndent
          let targetIndent :=
            if proofLayout
                && !originalLeadingHasLineStructure
                && !proofLayoutRebasesFromFirstToken tree then
              structuralIndent
            else if proofLayout
                    && request.respectPendingIndent
                    && originalLeadingHasLineStructure then
              structuralIndent
            else
              max movedIndent structuralIndent
          some (sourceIndent, targetIndent)
      | _, _ => none
  let inlineContinuationColumns? :=
    match if inlineMultilineLayoutIsland && quotationStartsOnLine then
            treeTrailingDelimiterIndent? request.sourceMap tree
          else
            none with
    | some sourceIndent => some (sourceIndent, leadingColumn)
    | none => inlineContinuationColumns?
  let inlineContinuationColumns? :=
    match inlineContinuationColumns? with
    | some (sourceIndent, targetIndent) =>
        if proofLayout && request.respectPendingIndent then
          some (sourceIndent, targetIndent)
        else if quotationStartsOnLine then
          some (sourceIndent, targetIndent)
        else if proofLayout || calcLayout || quotation then
          let fittedTarget :=
            fittingTargetColumn request.source request.sourceMap tree sourceText
              sourceIndent targetIndent request.lineWidth request.lineFitSuffixWidth
          let fittedTarget :=
            if quotation then
              let structuralTarget :=
                if quotationStartsOnLine then
                  (leadingColumn / indentationSpaces + 1) * indentationSpaces
                else
                  request.currentIndent + indentationSpaces
              max structuralTarget fittedTarget
            else
              fittedTarget
          some (sourceIndent, fittedTarget)
        else
          some (sourceIndent, targetIndent)
    | none => none
  let sourceColumnRebasedFromLayoutBase := request.layoutAnchor.shiftColumn sourceColumn
  let layoutTargetColumn? :=
    if !retainsRelativeLayout
        || inlineMultilineLayoutIsland
        || detachedInlineProofBody
        || multilineDelimitedProofBody then
      none
    else if usesPendingIndent then
      some leadingColumn
    else if originalLeadingHasLineStructure then
      some sourceColumnRebasedFromLayoutBase
    else
      none
  let targetColumn? :=
    request.rebaseSourceTextTargetColumn?.orElse fun _ => layoutTargetColumn?
  let proofBodyTargetColumn? :=
    if proof && originalLeadingHasLineStructure then
      request.lastToken?.bind
        fun token =>
          if !request.currentLine.endsWith token.lexeme then
            none
          else if request.formattedLeadingWhitespace?.isSome then
            some leadingColumn
          else if tokenStartsCurrentLine request.currentLine token then
            some (request.currentLine.length - token.lexeme.length + indentationSpaces)
          else
            let outputTokenColumn := request.currentLine.length - token.lexeme.length
            let delimiterColumn? :=
              bodyColumnAfterOpeningDelimiter? request.currentLine token
            match delimiterColumn? with
            | some delimiterColumn =>
                if request.sourceMap.columnAt token.span.start == outputTokenColumn then
                  none
                else
                  some delimiterColumn
            | none =>
                if request.sourceMap.columnAt token.span.start == outputTokenColumn then
                  none
                else if usesPendingIndent
                        && SpaceRules.hasLineStructure token.leading.text then
                  some leadingColumn
                else
                  match targetColumn? with
                  | some targetColumn =>
                      if request.layoutAnchor.outputColumn <= targetColumn then
                        none
                      else
                        some (request.layoutAnchor.outputColumn + indentationSpaces)
                  | none =>
                      some (request.layoutAnchor.outputColumn + indentationSpaces)
    else
      none
  let delimitedProofBodyTargetColumn? :=
    if multilineDelimitedProofBody then
      if SpaceRules.hasLineStructure leading then
        some leadingColumn
      else
        some (request.layoutAnchor.outputColumn + indentationSpaces)
    else
      none
  let targetColumn? :=
    match targetColumn?, proofBodyTargetColumn? with
    | _, some proofBodyTargetColumn => some proofBodyTargetColumn
    | some targetColumn, none => some targetColumn
    | none, none => none
  let targetColumn? :=
    match targetColumn?, delimitedProofBodyTargetColumn? with
    | some targetColumn, some detachedTargetColumn =>
        some (max targetColumn detachedTargetColumn)
    | some targetColumn, none => some targetColumn
    | none, some detachedTargetColumn => some detachedTargetColumn
    | none, none => none
  let targetColumn? :=
    if proof && originalLeadingHasLineStructure then
      targetColumn?.map
        fun targetColumn =>
          let minimumColumn :=
            max
              ((request.segmentIndentation + if usesPendingIndent then 0 else 1)
                * indentationSpaces)
              indentationSpaces
          let maximumColumn :=
            max minimumColumn (request.currentIndent + indentationSpaces)
          if targetColumn < minimumColumn || maximumColumn < targetColumn then
            minimumColumn
          else
            targetColumn
    else
      targetColumn?
  let targetColumn? :=
    if quotation && !quotationStartsOnLine && !inlineMultilineLayoutIsland then
      targetColumn?.map
        fun targetColumn =>
          fittingTargetColumn request.source request.sourceMap tree sourceText
            sourceColumn targetColumn request.lineWidth request.lineFitSuffixWidth
    else
      targetColumn?
  let leading :=
    let rebased :=
      match targetColumn? with
      | some targetColumn =>
          let sourceColumn :=
            if request.formattedLeadingWhitespace?.isSome || usesPendingIndent then
              leadingColumn
            else
              sourceColumn
          rebaseTextIndent sourceColumn targetColumn leading
      | none => leading
    if multilineDelimitedProofBody && !SpaceRules.hasLineStructure rebased then
      "\n"
      ++ spaces
          (targetColumn?.getD (request.layoutAnchor.outputColumn + indentationSpaces))
    else
      rebased
  let sourceTextRebase? :=
    match inlineContinuationColumns?,
          request.rebaseSourceTextTargetColumn? with
    | some continuationColumns, some targetColumn =>
        let detachedProofLayoutRebasesFromFirstToken :=
          formattedLeadingDetachesIsland
          && !LineBreakRules.treeContainsRawKind `Lean.calc tree
          && !LineBreakRules.treeContainsRawKind `Lean.calcTactic tree
          && !tree.containsNodeKind .calcBody
          && (proofLayoutRebasesFromFirstToken tree
              || sourceColumn <= continuationColumns.1)
        if proof
            || (proofLayout
                && (detachedProofLayoutRebasesFromFirstToken
                    || (originalLeadingHasLineStructure
                        && proofLayoutRebasesFromFirstToken tree))) then
          some (sourceColumn, targetColumn)
        else if calcLayout then
          some
            (
              continuationColumns.1,
              (targetColumn / indentationSpaces + 1) * indentationSpaces
            )
        else
          some continuationColumns
    | some continuationColumns, none => some continuationColumns
    | none, some targetColumn =>
        if calcLayout then
          (treeContinuationIndent? request.sourceMap tree).map
            fun sourceIndent =>
              (sourceIndent, (targetColumn / indentationSpaces + 1) * indentationSpaces)
        else if proof
                && (treeContinuationIndent? request.sourceMap tree).any
                    fun sourceIndent => sourceIndent < sourceColumn then
          none
        else
          some (sourceColumn, targetColumn)
    | none, none =>
        if calcLayout then
          (treeContinuationIndent? request.sourceMap tree).map
            fun sourceIndent =>
              (sourceIndent, (leadingColumn / indentationSpaces + 1) * indentationSpaces)
        else
          targetColumn?.map
            fun targetColumn =>
              (sourceColumn, targetColumn)
  let sourceText :=
    match islandPlan?.map (·.kind) with
    | some .syntaxComment =>
        let outputColumn :=
          lineWidth <| currentLineAfterAppend request.currentLine leading
        if SpaceRules.hasLineStructure leading then
          let commentSourceColumn :=
            tree.syntaxCommentSpans.head?.map
              (fun span => request.sourceMap.columnAt span.start)
            |>.getD sourceColumn
          if (sourceContinuationIndent? sourceText).any (· < commentSourceColumn) then
            rebaseMultilineSourceSlice outputColumn sourceText
          else
            SpaceRules.reindentCommentLexeme sourceText commentSourceColumn outputColumn
        else
          rebaseTextIndent sourceColumn outputColumn sourceText
    | _ =>
        match sourceTextRebase? with
        | some (sourceIndent, targetIndent) =>
            if sourceIndent == targetIndent then
              sourceText
            else
              rebaseTreeText request.source request.sourceMap tree sourceIndent
                targetIndent
        | none =>
            let outputColumn :=
              lineWidth <| currentLineAfterAppend request.currentLine leading
            if sourceColumn == outputColumn || !originalLeadingHasLineStructure then
              sourceText
            else
              rebaseTreeText request.source request.sourceMap tree sourceColumn
                outputColumn (rebaseTrivia := false)
  let isQq : Bool :=
    match islandPlan? with
    | some plan => plan.kind == .qq
    | none => false
  let sourceText :=
    if isQq then
      let outputColumn := lineWidth <| currentLineAfterAppend request.currentLine leading
      floorContinuationIndent outputColumn sourceText
    else
      sourceText
  some
    {
      text := leading ++ sourceText
      lastToken
      preserveNextStandaloneCommentIndent :=
        islandPlan?.any fun plan => plan.policy.followingComment == .preserveSourceIndent
    }

@[inline]
def emit? (request : EmissionRequest) (tree : SyntaxTree.Tree)
    (islandPlan? : Option IslandPlan := none)
    : Option Emission :=
  emitRebased? request tree islandPlan?

end OriginalTree
end Formatter
end LeanFmt
