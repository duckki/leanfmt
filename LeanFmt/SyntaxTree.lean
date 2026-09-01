import LeanFmt.LeanEnvironment

namespace LeanFmt
namespace SyntaxTree

open Lean

/-! ## Lossless source model -/

structure Span where
  start : String.Pos.Raw
  stop : String.Pos.Raw
deriving BEq, Repr

namespace Span

def fromSubstring (substring : Substring.Raw) : Span :=
  { start := substring.startPos, stop := substring.stopPos }

end Span

structure Trivia where
  span : Span
  text : String
deriving BEq, Repr

namespace Trivia

def fromSubstring (substring : Substring.Raw) : Trivia :=
  { span := Span.fromSubstring substring, text := substring.toString }

end Trivia

inductive TokenRole where
  | atom
  | ident
deriving BEq, Repr

structure Token where
  role : TokenRole
  kind : SyntaxNodeKind
  value : String
  lexeme : String
  leading : Trivia
  trailing : Trivia
  span : Span
deriving BEq, Repr

namespace Token

def fullSpan (token : Token) : Span :=
  { start := token.leading.span.start, stop := token.trailing.span.stop }

def fullText (token : Token) : String :=
  token.leading.text ++ token.lexeme ++ token.trailing.text

end Token

inductive DelimiterKind where
  | paren
  | bracket
  | brace
  | anonymousConstructor
  | doubleAngle
  | norm
deriving BEq, Repr

inductive NodeKind where
  | raw (kind : SyntaxNodeKind)
  | command (kind : SyntaxNodeKind)
  | tactic (kind : SyntaxNodeKind)
    (containsSequence isOwner containsOwner isSpacedApplication : Bool)
  | letExpression (kind : SyntaxNodeKind) (bodyCanStartApplicationArgument : Bool)
  | application
  | infixChain (kind : SyntaxNodeKind)
  | lowPriorityInfixRhs
  | lowPriorityOperand (canFlow hasAttachedBody : Bool)
  | indexedInfix (kind : SyntaxNodeKind)
  | delimitedCollection (kind : DelimiterKind)
  | suffixGroup
  | tacticAssignmentProof
  | tacticIdentifierClause
  | tacticEliminationTargets (containsNamed : Bool)
  | tacticEliminationHeader (targetIsNamed : Bool)
  | namedDiscriminant
  | patternLambda
  | definition
  | annotatedDeclaration
  | declarationHeader
  | signatureParameters
  | macroPattern
  | structureHeader
  | structureConstructor
  | structureDeriving
  | calcBody
  | calcStep
  | parserOwnedHeader
  | parserOwnedBody
  | parserOwnedSuffixBody
  | matchHeader
  | matchDiscriminants
  | matchPatterns
  | doForHeader
  | doFallbackClause
  | doFallbackContinuation
  | structureUpdate
  | ifThenElseClause
  | ifThenElseChain (kind : SyntaxNodeKind)
  | proofBody (containsTacticLayoutOwner : Bool)
  | derivingClause
  | unifConstraints
deriving BEq, Inhabited, Repr

def nodeKindName : NodeKind → String
  | .raw kind => toString kind
  | .command kind => s!"LeanFmt.SyntaxTree.NodeKind.command {kind}"
  | .tactic kind _ _ _ _ => toString kind
  | .letExpression kind bodyCanStartApplicationArgument =>
      s!"LeanFmt.SyntaxTree.NodeKind.letExpression {kind} {bodyCanStartApplicationArgument}"
  | .application => "LeanFmt.SyntaxTree.NodeKind.application"
  | .infixChain kind => s!"LeanFmt.SyntaxTree.NodeKind.infixChain {kind}"
  | .lowPriorityInfixRhs => "LeanFmt.SyntaxTree.NodeKind.lowPriorityInfixRhs"
  | .lowPriorityOperand _ _ => "LeanFmt.SyntaxTree.NodeKind.lowPriorityOperand"
  | .indexedInfix kind => s!"LeanFmt.SyntaxTree.NodeKind.indexedInfix {kind}"
  | .delimitedCollection kind =>
      s!"LeanFmt.SyntaxTree.NodeKind.delimitedCollection {repr kind}"
  | .suffixGroup => "LeanFmt.SyntaxTree.NodeKind.suffixGroup"
  | .tacticAssignmentProof => "LeanFmt.SyntaxTree.NodeKind.tacticAssignmentProof"
  | .tacticIdentifierClause => "LeanFmt.SyntaxTree.NodeKind.tacticIdentifierClause"
  | .tacticEliminationTargets containsNamed =>
      s!"LeanFmt.SyntaxTree.NodeKind.tacticEliminationTargets {containsNamed}"
  | .tacticEliminationHeader targetIsNamed =>
      s!"LeanFmt.SyntaxTree.NodeKind.tacticEliminationHeader {targetIsNamed}"
  | .namedDiscriminant => "LeanFmt.SyntaxTree.NodeKind.namedDiscriminant"
  | .patternLambda => "LeanFmt.SyntaxTree.NodeKind.patternLambda"
  | .definition => "LeanFmt.SyntaxTree.NodeKind.definition"
  | .annotatedDeclaration => "LeanFmt.SyntaxTree.NodeKind.annotatedDeclaration"
  | .declarationHeader => "LeanFmt.SyntaxTree.NodeKind.declarationHeader"
  | .signatureParameters => "LeanFmt.SyntaxTree.NodeKind.signatureParameters"
  | .macroPattern => "LeanFmt.SyntaxTree.NodeKind.macroPattern"
  | .structureHeader => "LeanFmt.SyntaxTree.NodeKind.structureHeader"
  | .structureConstructor => "LeanFmt.SyntaxTree.NodeKind.structureConstructor"
  | .structureDeriving => "LeanFmt.SyntaxTree.NodeKind.structureDeriving"
  | .calcBody => "LeanFmt.SyntaxTree.NodeKind.calcBody"
  | .calcStep => "LeanFmt.SyntaxTree.NodeKind.calcStep"
  | .parserOwnedHeader => "LeanFmt.SyntaxTree.NodeKind.parserOwnedHeader"
  | .parserOwnedBody => "LeanFmt.SyntaxTree.NodeKind.parserOwnedBody"
  | .parserOwnedSuffixBody => "LeanFmt.SyntaxTree.NodeKind.parserOwnedSuffixBody"
  | .matchHeader => "LeanFmt.SyntaxTree.NodeKind.matchHeader"
  | .matchDiscriminants => "LeanFmt.SyntaxTree.NodeKind.matchDiscriminants"
  | .matchPatterns => "LeanFmt.SyntaxTree.NodeKind.matchPatterns"
  | .doForHeader => "LeanFmt.SyntaxTree.NodeKind.doForHeader"
  | .doFallbackClause => "LeanFmt.SyntaxTree.NodeKind.doFallbackClause"
  | .doFallbackContinuation => "LeanFmt.SyntaxTree.NodeKind.doFallbackContinuation"
  | .structureUpdate => "LeanFmt.SyntaxTree.NodeKind.structureUpdate"
  | .ifThenElseClause => "LeanFmt.SyntaxTree.NodeKind.ifThenElseClause"
  | .ifThenElseChain kind => s!"LeanFmt.SyntaxTree.NodeKind.ifThenElseChain {kind}"
  | .proofBody _ => "LeanFmt.SyntaxTree.NodeKind.proofBody"
  | .derivingClause => "LeanFmt.SyntaxTree.NodeKind.derivingClause"
  | .unifConstraints => "LeanFmt.SyntaxTree.NodeKind.unifConstraints"

inductive Tree where
  | missing
  | leaf (token : Token)
  | node (kind : NodeKind) (children : Array Tree)
deriving BEq, Inhabited, Repr

def isSyntaxCommentKind (kind : SyntaxNodeKind) : Bool :=
  kind == `Lean.Parser.Command.moduleDoc || kind == `Lean.Parser.Command.docComment

def isCoreTacticKindName (kindName : String) : Bool :=
  kindName.startsWith "Lean.Parser.Tactic."
  || kindName.startsWith "Lean.Elab.Tactic."
  || kindName.startsWith "tactic"
  || kindName.startsWith "«tactic"
  || kindName == "Lean.cdot"
  || kindName == "Lean.cdotTk"

def isExtensionTacticKindName (kindName : String) : Bool :=
  kindName.contains ".Tactic." && !isCoreTacticKindName kindName

def lexemeEndsWithOpeningDelimiter (lexeme : String) : Bool :=
  ["(", "[", "{", "⟨", "⟪", "‖"].any fun suffix => lexeme.endsWith suffix

def Token.isOpeningDelimiter (token : Token) : Bool :=
  token.role == .atom && lexemeEndsWithOpeningDelimiter token.lexeme

def Token.isClosingDelimiter (token : Token) : Bool :=
  token.role == .atom
  && [")", "]", "}", "⟩", "⟫", "‖"].any fun delimiter => token.lexeme == delimiter

namespace Tree

private partial def appendTokens (tokens : Array Token) : Tree → Array Token
  | Tree.missing => tokens
  | Tree.leaf token => tokens.push token
  | Tree.node _ children => children.foldl appendTokens tokens

def tokens (tree : Tree) : Array Token :=
  appendTokens #[] tree

def isTacticSequenceKind (kind : Lean.SyntaxNodeKind) : Bool :=
  kind == `Lean.Parser.Tactic.tacticSeq
  || kind == `Lean.Parser.Tactic.tacticSeq1Indented
  || kind == `Lean.Parser.Tactic.tacticSeqBracketed

def tacticKindOwnsStructuralLayout (kind : Lean.SyntaxNodeKind) : Bool :=
  kind == `Lean.Parser.Tactic.cases
  || kind == `Lean.Parser.Tactic.induction
  || kind == `Lean.Parser.Tactic.match
  || kind == `Lean.Parser.Tactic.inductionAlts
  || kind == `Lean.Parser.Tactic.inductionAlt

def isCalcTree : Tree → Bool
  | .node (.raw `Lean.calc) _ => true
  | .node (.raw `Lean.calcTactic) _ => true
  | .node (.tactic `Lean.calcTactic _ _ _ _) _ => true
  | _ => false

partial def isTacticSequenceTree : Tree → Bool
  | .node (.raw kind) _ => isTacticSequenceKind kind
  | .node (.tactic kind _ _ _ _) _ => isTacticSequenceKind kind
  | .node .suffixGroup children => children[0]?.any isTacticSequenceTree
  | .node .parserOwnedSuffixBody children => children[0]?.any isTacticSequenceTree
  | _ => false

private def sharesSourceLineWith (left right : Tree) : Bool :=
  match left.tokens.back?, right.tokens[0]? with
  | some left, some right =>
      !left.trailing.text.contains '\n' && !right.leading.text.contains '\n'
  | _, _ => false

private def parserOwnedBodyHasDetachedBody : Tree → Bool
  | .node .parserOwnedBody children =>
      match children.toList with
      | [header, body] =>
          !sharesSourceLineWith header body
          || match body with
              | .node .suffixGroup bodyChildren =>
                  match bodyChildren.toList with
                  | [introducer, value] => !sharesSourceLineWith introducer value
                  | _ => false
              | _ => false
      | _ => false
  | _ => false

private def directlyOwnsAttachedTacticSequence (children : Array Tree) : Bool :=
  let contentIndexes :=
    (List.range children.size).filter
      fun index => children[index]?.any fun child => !child.tokens.isEmpty
  match contentIndexes.reverse with
  | rightIndex :: leftIndex :: _ =>
      match children[leftIndex]?, children[rightIndex]? with
      | some left, some right =>
          (left.tokens.size == 1 && left.tokens[0]?.any (·.role == .atom))
          && isTacticSequenceTree right
          && sharesSourceLineWith left right
      | _, _ => false
  | _ => false

private partial def firstTacticToken? : Tree → Option Token
  | .missing => none
  | .leaf token => if token.lexeme.isEmpty then none else some token
  | .node _ children => children.findSome? firstTacticToken?

structure TacticLayoutSummary where
  containsSequence : Bool := false
  isOwner : Bool := false
  containsOwner : Bool := false
deriving Inhabited

partial def tacticLayoutSummary : Tree → TacticLayoutSummary
  | .missing | .leaf _ => {}
  | .node (.proofBody containsOwner) _ => { containsOwner }
  | .node (.tactic _ containsSequence isOwner containsOwner _) _ =>
      { containsSequence, isOwner, containsOwner }
  | tree@(.node kind children) =>
      let childSummaries := children.map tacticLayoutSummary
      let containsSequence :=
        (match kind with
          | .proofBody _ => false
          | .raw rawKind =>
              isTacticSequenceKind rawKind || childSummaries.any (·.containsSequence)
          | _ => childSummaries.any (·.containsSequence))
      let isOwner :=
        isCalcTree tree
        || parserOwnedBodyHasDetachedBody tree
        || ((match kind with
              | .raw rawKind => tacticKindOwnsStructuralLayout rawKind
              | _ => false)
            && childSummaries.any (·.containsSequence))
      let visibleOwner :=
        isOwner
        && (!isCalcTree tree
            || (firstTacticToken? tree).any fun token => token.leading.text.contains '\n')
      let directlyOwnsSequence := directlyOwnsAttachedTacticSequence children
      let hidesNestedOwners :=
        match kind with
        | .raw rawKind =>
            let kindName := nodeKindName kind
            (isCoreTacticKindName kindName || isExtensionTacticKindName kindName)
            && !isTacticSequenceKind rawKind
            && !isOwner
            && !directlyOwnsSequence
        | _ => false
      {
        containsSequence
        isOwner
        containsOwner :=
          !hidesNestedOwners && (visibleOwner || childSummaries.any (·.containsOwner))
      }

def isTacticLayoutOwner (tree : Tree) : Bool :=
  (tacticLayoutSummary tree).isOwner

def containsTacticLayoutOwner (tree : Tree) : Bool :=
  (tacticLayoutSummary tree).containsOwner

partial def containsIntrinsicTacticLayoutOwner : Tree → Bool
  | tree@(.node (.tactic _ _ isOwner _ _) children) =>
      isOwner || isCalcTree tree || children.any containsIntrinsicTacticLayoutOwner
  | tree@(.node _ children) =>
      isCalcTree tree || children.any containsIntrinsicTacticLayoutOwner
  | _ => false

def isSpacedApplicationTactic : Tree → Bool
  | .node (.tactic _ _ _ _ isSpacedApplication) _ => isSpacedApplication
  | _ => false

partial def containsSpacedApplicationTactic : Tree → Bool
  | .node (.tactic _ _ _ _ true) _ => true
  | .node _ children => children.any containsSpacedApplicationTactic
  | _ => false

partial def isProofBodyEnvelope : Tree → Bool
  | .node (.proofBody _) _ => true
  | .node .suffixGroup children =>
      match children.find? fun child => (firstTacticToken? child).isSome with
      | some child => child.isProofBodyEnvelope
      | none => false
  | .node (.raw kind) children =>
      if kind == `Lean.Parser.Term.byTactic || kind == `Lean.Parser.Term.byTactic' then
        children.any
          fun
          | .node (.proofBody _) _ => true
          | _ => false
      else
        match children.filter fun child => (firstTacticToken? child).isSome with
        | #[child] => child.isProofBodyEnvelope
        | _ => false
  | .node _ children =>
      match children.filter fun child => (firstTacticToken? child).isSome with
      | #[child] => child.isProofBodyEnvelope
      | _ => false
  | _ => false

partial def protectNestedTacticSequences : Tree → Tree
  | tree@(.node (.tactic kind _ _ _ _) _) =>
      if isTacticSequenceKind kind then
        .node (.proofBody tree.containsTacticLayoutOwner) #[tree]
      else
        tree
  | tree@(.node (.proofBody _) _) => tree
  | .node kind children =>
      .node kind (children.map protectNestedTacticSequences)
  | tree => tree

private partial def tacticSequenceHasMultipleEntries : Tree → Bool
  | .node (.tactic kind _ _ _ _) children
  | .node (.raw kind) children =>
      if isTacticSequenceKind kind then
        children.any tacticSequenceHasMultipleEntries
      else if kind == `null then
        2 <= (children.filter fun child => (firstTacticToken? child).isSome).size
      else
        false
  | _ => false

def proofBodyHasMultipleTactics : Tree → Bool
  | .node (.proofBody _) children => children.any tacticSequenceHasMultipleEntries
  | _ => false

private def hasInternalLineBreakTrivia (tree : Tree) : Bool :=
  let rec loop : List Token → Bool
    | left :: right :: rest =>
        left.trailing.text.contains '\n'
        || right.leading.text.contains '\n'
        || loop (right :: rest)
    | _ => false
  loop tree.tokens.toList

-- Expose a final proof body while keeping its introducer in the structural shell.
private def isTrailingProofArgumentEnvelope : NodeKind → Bool
  | .suffixGroup
  | .lowPriorityInfixRhs
  | .infixChain `«term_<|_» => true
  | .infixChain `Lean.Parser.Term.proj => true
  | .raw `null => true
  | .raw `Lean.Parser.Term.paren => true
  | .raw kind =>
      let kindName := nodeKindName (.raw kind)
      kindName.startsWith "Lean.Parser.Term." && kindName.endsWith "Decl"
  | _ => false

private def exposesSimpleTrailingProofArgument : NodeKind → Bool
  | .suffixGroup
  | .lowPriorityInfixRhs
  | .infixChain `«term_<|_» => true
  | _ => false

private def proofArgumentEnvelopeCanOwnSuffix : NodeKind → Bool
  | .suffixGroup
  | .infixChain `Lean.Parser.Term.proj
  | .raw `Lean.Parser.Term.paren => true
  | _ => false

private structure OwnedProofBodySplit where
  before : Tree
  body : Tree
  after : Tree

private def nodeOrMissing (kind : NodeKind) (children : Array Tree) : Tree :=
  if children.any fun child => (firstTacticToken? child).isSome then
    .node kind children
  else
    .missing

private def splitNodeAroundChild (kind : NodeKind) (children : Array Tree)
    (index : Nat) (split : OwnedProofBodySplit)
    : OwnedProofBodySplit :=
  let prefixChildren :=
    children.mapIdx
      fun childIndex child =>
        if childIndex < index then
          child
        else if childIndex == index then
          split.before
        else
          .missing
  let suffixChildren :=
    children.mapIdx
      fun childIndex child =>
        if childIndex < index then
          .missing
        else if childIndex == index then
          split.after
        else
          child
  {
    before := nodeOrMissing kind prefixChildren
    body := split.body
    after := nodeOrMissing kind suffixChildren
  }

private def exposeAssignedProofBody? (split : OwnedProofBodySplit)
    : Option OwnedProofBodySplit := do
  if split.before.tokens.back?.map (·.lexeme) != some ":=" then
    none
  let .node bodyKind bodyChildren := split.body | none
  let .raw rawBodyKind := bodyKind | none
  if rawBodyKind != `Lean.Parser.Term.byTactic
      && rawBodyKind != `Lean.Parser.Term.byTactic' then
    none
  let proofIndex ←
    bodyChildren.findIdx?
      fun
      | .node (.proofBody _) _ => true
      | _ => false
  let proofBody ← bodyChildren[proofIndex]?
  if proofBody.containsIntrinsicTacticLayoutOwner then
    none
  let bodySplit :=
    splitNodeAroundChild bodyKind bodyChildren proofIndex
      { before := .missing, body := proofBody, after := .missing }
  if bodySplit.after != .missing then
    none
  some
    {
      before := .node .suffixGroup #[split.before, bodySplit.before]
      body := proofBody
      after := split.after
    }

private partial def splitTrailingOwnedProofBodyCore?
    (permitSimpleProof allowSimpleProof : Bool)
    : Tree → Option OwnedProofBodySplit
  | body@(.node (.proofBody containsOwner) _) =>
      if containsOwner then
        some { before := .missing, body, after := .missing }
      else
        none
  | .node (.tactic _ _ _ _ _) _ => none
  | .node kind children => do
      let kindName := nodeKindName kind
      if isCoreTacticKindName kindName || isExtensionTacticKindName kindName then
        none
      else
        let exposesSimpleBody :=
          permitSimpleProof
          && allowSimpleProof
          && (kind == .raw `Lean.Parser.Term.byTactic
              || kind == .raw `Lean.Parser.Term.byTactic')
        let directBodyIndex? :=
          children.findIdx?
            fun
            | .node (.proofBody containsOwner) _ =>
                containsOwner || exposesSimpleBody
            | _ => false
        match directBodyIndex? with
        | some index =>
            if !proofArgumentEnvelopeCanOwnSuffix kind
                && (List.range' (index + 1) (children.size - (index + 1))).any
                    fun laterIndex =>
                      children[laterIndex]?.any
                        fun child =>
                          (firstTacticToken? child).isSome then
              none
            else
              let body ← children[index]?
              match body with
              | .node (.proofBody true) _ =>
                  some
                    {
                      before := .missing
                      body := .node kind children
                      after := .missing
                    }
              | _ =>
                  let split : OwnedProofBodySplit :=
                    { before := .missing, body, after := .missing }
                  some (splitNodeAroundChild kind children index split)
        | none =>
            if !isTrailingProofArgumentEnvelope kind then
              none
            let childPermitsSimpleProof :=
              permitSimpleProof || exposesSimpleTrailingProofArgument kind
            let childAllowsSimpleProof :=
              allowSimpleProof || exposesSimpleTrailingProofArgument kind
            let (index, split) ←
              (List.range children.size).foldl
                (fun found index =>
                  found.orElse
                    fun _ => do
                      let child ← children[index]?
                      let split ←
                        splitTrailingOwnedProofBodyCore? childPermitsSimpleProof
                          childAllowsSimpleProof child
                      some (index, split))
                none
            if !proofArgumentEnvelopeCanOwnSuffix kind
                && (List.range' (index + 1) (children.size - (index + 1))).any
                    fun laterIndex =>
                      children[laterIndex]?.any
                        fun child =>
                          (firstTacticToken? child).isSome then
              none
            else
              some (splitNodeAroundChild kind children index split)
  | _ => none

private def splitTrailingOwnedProofBody? (tree : Tree) (permitSimpleProof : Bool)
    : Option OwnedProofBodySplit :=
  splitTrailingOwnedProofBodyCore? permitSimpleProof false tree

private partial def groupSimpleTrailingProofArgument? : Tree → Option Tree
  | .node kind children => do
      if kind == .raw `Lean.Parser.Term.byTactic
          || kind == .raw `Lean.Parser.Term.byTactic' then
        let proofIndex ←
          children.findIdx?
            fun
            | body@(.node (.proofBody containsOwner) _) =>
                !containsOwner
                && !body.proofBodyHasMultipleTactics
                && !hasInternalLineBreakTrivia body
            | _ => false
        let proofBody ← children[proofIndex]?
        let split :=
          splitNodeAroundChild kind children proofIndex
            { before := .missing, body := proofBody, after := .missing }
        some <| .node .suffixGroup #[split.before, split.body, split.after]
      else
        let candidateIndexes :=
          if kind == .application || kind == .raw `null then
            match (List.range children.size).reverse.find?
                    fun index =>
                      children[index]?.any
                        fun child => (firstTacticToken? child).isSome with
            | some index => [index]
            | none => []
          else if isTrailingProofArgumentEnvelope kind then
            List.range children.size |>.reverse
          else
            []
        let (index, grouped) ←
          candidateIndexes.foldl
            (fun found index =>
              found.orElse
                fun _ => do
                  let child ← children[index]?
                  let grouped ← groupSimpleTrailingProofArgument? child
                  some (index, grouped))
            none
        some <| .node kind (children.set! index grouped)
  | _ => none

private partial def containsLowPriorityInfixRhs : Tree -> Bool
  | .node .lowPriorityInfixRhs _ => true
  | .node _ children => children.any containsLowPriorityInfixRhs
  | _ => false

private def annotateTacticNode
    (kind : SyntaxNodeKind) (children : Array Tree) (isSpacedApplication := false)
    : Tree :=
  let tree := .node (.raw kind) children
  let summary := tacticLayoutSummary tree
  if summary.isOwner then
    .node
      (.tactic kind summary.containsSequence true summary.containsOwner
        isSpacedApplication)
      (children.map protectNestedTacticSequences)
  else if directlyOwnsAttachedTacticSequence children then
    .node
      (.tactic kind summary.containsSequence false summary.containsOwner
        isSpacedApplication)
      children
  else if isTacticSequenceKind kind then
    .node
      (.tactic kind summary.containsSequence false summary.containsOwner
        isSpacedApplication)
      children
  else
    let split? :=
      splitTrailingOwnedProofBody? (.node (.raw `null) children) isSpacedApplication
    match split? with
    | some split =>
        let (groupKind, split) :=
          match exposeAssignedProofBody? split with
          | some assigned => (NodeKind.tacticAssignmentProof, assigned)
          | none => (NodeKind.suffixGroup, split)
        match split.before with
        | .node _ shellChildren =>
            let shell :=
              if isSpacedApplication then
                .node (.tactic kind summary.containsSequence false false true)
                  shellChildren
              else if shellChildren.any containsLowPriorityInfixRhs then
                .node .parserOwnedHeader shellChildren
              else
                .node (.tactic kind summary.containsSequence false false false)
                  shellChildren
            .node groupKind #[shell, split.body, split.after]
        | _ =>
            .node
              (.tactic kind summary.containsSequence false summary.containsOwner
                isSpacedApplication)
              children
    | _ =>
        let children :=
          if isSpacedApplication then
            match groupSimpleTrailingProofArgument? (.node (.raw `null) children) with
            | some (.node _ grouped) => grouped
            | _ => children
          else
            children
        .node
          (.tactic kind summary.containsSequence false summary.containsOwner
            isSpacedApplication)
          children

private def lineIndentation? (token : Token) : Option String :=
  match token.leading.text.splitOn "\n" with
  | [] | [_] => none
  | lines => do
      let indentation ← lines.getLast?
      if indentation.toList.all fun char => char == ' ' || char == '\t' then
        some indentation
      else
        none

private def splitAlignedTacticSequenceContinuation? (tree : Tree)
    : Option (Tree × Tree) := do
  let .node (.tactic kind _ isOwner _ isSpacedApplication) children := tree | none
  if isOwner then
    none
  else
    let contentIndexes :=
      (List.range children.size).filter
        fun index => children[index]?.any fun child => firstTacticToken? child |>.isSome
    let continuationIndex ← contentIndexes.getLast?
    let continuation ← children[continuationIndex]?
    if !isTacticSequenceTree continuation then
      none
    else
      let head :=
        annotateTacticNode kind (children.set! continuationIndex .missing)
          isSpacedApplication
      let headIndentation ← firstTacticToken? head >>= lineIndentation?
      let continuationIndentation ← firstTacticToken? continuation >>= lineIndentation?
      if headIndentation == continuationIndentation then
        some (head, continuation)
      else
        none

private partial def annotateTacticSequenceEntry (spacedApplicationKinds : NameSet)
    : Tree → Tree
  | .node (.raw `null) children =>
      let children :=
        children.foldl
          (fun result child =>
            let child := annotateTacticSequenceEntry spacedApplicationKinds child
            match splitAlignedTacticSequenceContinuation? child with
            | some (head, continuation) => result.push head |>.push continuation
            | none => result.push child)
          #[]
      .node (.raw `null) children
  | .node kind@(.infixChain _) children =>
      .node kind
      <| children.mapIdx
          fun index child =>
            if index % 2 == 0 then
              annotateTacticSequenceEntry spacedApplicationKinds child
            else
              child
  | .node (.raw kind) children =>
      annotateTacticNode kind children (spacedApplicationKinds.contains kind)
  | tree => tree

def annotateTacticTree (tree : Tree) (spacedApplicationKinds : NameSet := {}) : Tree :=
  match tree with
  | tree@(.node (.raw kind) children) =>
      let kindName := nodeKindName (.raw kind)
      if isTacticSequenceKind kind then
        annotateTacticNode kind
          (children.map (annotateTacticSequenceEntry spacedApplicationKinds))
      else if isCoreTacticKindName kindName then
        annotateTacticNode kind children (spacedApplicationKinds.contains kind)
      else
        tree
  | tree => tree

private inductive TokenCardinality where
  | empty
  | single (token : Token)
  | multiple
deriving Inhabited

private def TokenCardinality.combine (left right : TokenCardinality) : TokenCardinality :=
  match left, right with
  | .multiple, _
  | _, .multiple
  | .single _, .single _ => .multiple
  | .single token, .empty
  | .empty, .single token => .single token
  | .empty, .empty => .empty

private partial def tokenCardinality : Tree → TokenCardinality
  | Tree.missing => .empty
  | Tree.leaf token => .single token
  | Tree.node _ children =>
      children.foldl
        (fun cardinality child =>
          match cardinality with
          | .multiple => .multiple
          | _ => cardinality.combine (tokenCardinality child))
        .empty

def singleToken? (tree : Tree) : Option Token :=
  match tokenCardinality tree with
  | .single token => some token
  | .empty
  | .multiple => none

partial def firstToken? : Tree → Option Token
  | Tree.missing => none
  | Tree.leaf token =>
      if token.lexeme.isEmpty then none else some token
  | Tree.node _ children =>
      children.findSome? firstToken?

partial def lastToken? : Tree → Option Token
  | Tree.missing => none
  | Tree.leaf token =>
      if token.lexeme.isEmpty then none else some token
  | Tree.node _ children =>
      children.findSomeRev? lastToken?

def isParenthesized (tree : Tree) : Bool :=
  match tree.firstToken?, tree.lastToken? with
  | some opening, some closing =>
      opening.role == .atom
      && opening.lexeme == "("
      && closing.role == .atom
      && closing.lexeme == ")"
  | _, _ => false

def startsWithOpeningDelimiter (tree : Tree) : Bool :=
  tree.firstToken?.any Token.isOpeningDelimiter

partial def extractLeadingLexeme? (lexeme : String) : Tree → Option (Tree × Tree)
  | .leaf token =>
      if token.lexeme == lexeme then some (.leaf token, .missing) else none
  | .node kind children => do
      let index ← children.findIdx? fun child => child.firstToken?.isSome
      let child ← children[index]?
      let (leading, remainder) ← extractLeadingLexeme? lexeme child
      some (leading, .node kind (children.set! index remainder))
  | .missing => none

partial def extractTrailingLexeme? (lexeme : String) : Tree → Option (Tree × Tree)
  | .leaf token =>
      if token.lexeme == lexeme then some (.missing, .leaf token) else none
  | .node kind children => do
      let index ←
        (List.range children.size).foldl
          (fun found candidate =>
            if children[candidate]?.bind Tree.firstToken? |>.isSome then
              some candidate
            else
              found)
          none
      let child ← children[index]?
      let (remainder, trailing) ← extractTrailingLexeme? lexeme child
      some (.node kind (children.set! index remainder), trailing)
  | .missing => none

partial def containsNodeKind (target : NodeKind) : Tree → Bool
  | Tree.missing => false
  | Tree.leaf _ => false
  | Tree.node kind children =>
      kind == target || children.any (containsNodeKind target)

def isParenthesizedTypeAscription (tree : Tree) : Bool :=
  tree.isParenthesized && tree.containsNodeKind (.raw `Lean.Parser.Term.typeAscription)

partial def firstNodeChildCount? (target : NodeKind) : Tree → Option Nat
  | Tree.missing => none
  | Tree.leaf _ => none
  | Tree.node kind children =>
      if kind == target then
        some children.size
      else
        children.foldl
          (fun found child =>
            match found with
            | some count => some count
            | none => firstNodeChildCount? target child)
          none

def firstInfixChainChildCount? (kind : SyntaxNodeKind) (tree : Tree) : Option Nat :=
  firstNodeChildCount? (.infixChain kind) tree

partial def syntaxCommentSpans : Tree → List Span
  | .missing | .leaf _ => []
  | tree@(.node (.raw kind) children) =>
      if isSyntaxCommentKind kind then
        match tree.firstToken?, tree.lastToken? with
        | some first, some last => [{ start := first.span.start, stop := last.span.stop }]
        | _, _ => []
      else
        children.toList.flatMap syntaxCommentSpans
  | tree@(.node (.command kind) children) =>
      if isSyntaxCommentKind kind then
        match tree.firstToken?, tree.lastToken? with
        | some first, some last => [{ start := first.span.start, stop := last.span.stop }]
        | _, _ => []
      else
        children.toList.flatMap syntaxCommentSpans
  | .node _ children => children.toList.flatMap syntaxCommentSpans

end Tree

structure Module where
  source : String
  rawSyntax : Syntax
  tree : Tree
  tokens : Array Token
deriving Repr

namespace Module

def containsNonSourceLexemes (moduleTree : Module) : Bool :=
  moduleTree.tokens.any
    fun token =>
      !token.lexeme.isEmpty
      && !(token.span.start < token.span.stop
            && String.Pos.Raw.extract moduleTree.source token.span.start token.span.stop
                == token.lexeme)

def sourceOrderedTokens (moduleTree : Module) : Array Token :=
  moduleTree.tokens.qsort fun left right => left.fullSpan.start < right.fullSpan.start

def reconstruct (moduleTree : Module) : String :=
  let tokens := moduleTree.sourceOrderedTokens
  let body := tokens.foldl (fun acc token => acc ++ token.fullText) ""
  match tokens.back? with
  | none => moduleTree.source
  | some token =>
      body
      ++ String.Pos.Raw.extract
          moduleTree.source token.fullSpan.stop moduleTree.source.endPos.offset

end Module

def sourceText (source : String) (start stop : String.Pos.Raw) : String :=
  String.Pos.Raw.extract source start stop

structure SourcePositionMap where
  source : String
  lineStarts : Array String.Pos.Raw
deriving Repr

namespace SourcePositionMap

def ofString (source : String) : SourcePositionMap :=
  let fileMap := Lean.FileMap.ofString source
  { source, lineStarts := fileMap.positions }

def fileMap (sourceMap : SourcePositionMap) : Lean.FileMap :=
  { source := sourceMap.source, positions := sourceMap.lineStarts }

def columnAt (sourceMap : SourcePositionMap) (position : String.Pos.Raw) : Nat :=
  (sourceMap.fileMap.toPosition position).column

def lineNumberAt (sourceMap : SourcePositionMap) (position : String.Pos.Raw) : Nat :=
  (sourceMap.fileMap.toPosition position).line

end SourcePositionMap

def syntheticTrivia : Trivia :=
  { span := { start := 0, stop := 0 }, text := "" }

def tokenOfOriginal
    (source : String)
    (role : TokenRole)
    (kind : SyntaxNodeKind)
    (value : String)
    (leading : Substring.Raw)
    (startPos : String.Pos.Raw)
    (trailing : Substring.Raw)
    (stopPos : String.Pos.Raw)
    : Token :=
  {
    role
    kind
    value
    lexeme := sourceText source startPos stopPos
    leading := Trivia.fromSubstring leading
    trailing := Trivia.fromSubstring trailing
    span := { start := startPos, stop := stopPos }
  }

def tokenOfSynthetic
    (role : TokenRole)
    (kind : SyntaxNodeKind)
    (value : String)
    (startPos : String.Pos.Raw)
    (stopPos : String.Pos.Raw)
    : Token :=
  {
    role
    kind
    value
    lexeme := value
    leading := syntheticTrivia
    trailing := syntheticTrivia
    span := { start := startPos, stop := stopPos }
  }

def tokenOfNone (role : TokenRole) (kind : SyntaxNodeKind) (value : String) : Token :=
  {
    role
    kind
    value
    lexeme := value
    leading := syntheticTrivia
    trailing := syntheticTrivia
    span := { start := 0, stop := 0 }
  }

def tokenOfSourceInfo
    (source : String)
    (role : TokenRole)
    (kind : SyntaxNodeKind)
    (value : String)
    (info : SourceInfo)
    : Token :=
  match info with
  | .original leading startPos trailing stopPos =>
      tokenOfOriginal source role kind value leading startPos trailing stopPos
  | .synthetic startPos stopPos _ =>
      tokenOfSynthetic role kind value startPos stopPos
  | .none =>
      tokenOfNone role kind value

/-! ## Raw tree extraction -/

partial def extractRawTree (source : String) : Syntax → Tree
  | .missing => .missing
  | .atom info value =>
      .leaf <| tokenOfSourceInfo source .atom .anonymous value info
  | .ident info rawValue _ _ =>
      .leaf <| tokenOfSourceInfo source .ident Lean.identKind rawValue.toString info
  | .node _ kind children =>
      .node (.raw kind) <| children.map (extractRawTree source)

def tokenComesFromSource (source : String) (token : Token) : Bool :=
  token.span.start < token.span.stop
  && sourceText source token.span.start token.span.stop == token.lexeme

partial def removeOverlappingSourceTokensAux
    (source : String) (consumedUntil : String.Pos.Raw)
    : Tree → Tree × String.Pos.Raw
  | .missing => (.missing, consumedUntil)
  | .leaf token =>
      if tokenComesFromSource source token then
        if token.span.start < consumedUntil then
          (.missing, consumedUntil)
        else
          (.leaf token, token.span.stop)
      else
        (.leaf token, consumedUntil)
  | .node kind children =>
      let (children, consumedUntil) :=
        children.foldl
          (fun (filtered, consumedUntil) child =>
            let (child, consumedUntil) :=
              removeOverlappingSourceTokensAux source consumedUntil child
            (filtered.push child, consumedUntil))
          (#[], consumedUntil)
      let children :=
        if kind == .raw `choice then
          children.filter fun child => child.firstToken?.isSome
        else
          children
      (.node kind children, consumedUntil)

def removeOverlappingSourceTokens (source : String) (tree : Tree) : Tree :=
  (removeOverlappingSourceTokensAux source 0 tree).1

def rawKind? : Tree → Option SyntaxNodeKind
  | .node (.raw kind) _ => some kind
  | .node (.command kind) _ => some kind
  | .node (.letExpression kind _) _ => some kind
  | _ => none

partial def isPatternLambdaArgument : Tree → Bool
  | .node .patternLambda _ => true
  | .node (.raw `null) children =>
      let content := children.filter fun child => child.firstToken?.isSome
      content.size == 1 && content[0]?.any isPatternLambdaArgument
  | .node (.raw `Lean.Parser.Term.explicit) children
  | .node (.raw `Lean.Parser.Term.explicitUniv) children =>
      children.back?.any isPatternLambdaArgument
  | _ => false

abbrev InfixPrecedenceMap := NameMap (Nat × Nat)

partial def parserDescrPrecedence? (kind : SyntaxNodeKind)
    : ParserDescr → Option (Nat × Nat)
  | .trailingNode nodeKind precedence leftPrecedence parser =>
      if nodeKind == kind then
        some (precedence, leftPrecedence)
      else
        parserDescrPrecedence? kind parser
  | .node _ _ parser
  | .unary _ parser =>
      parserDescrPrecedence? kind parser
  | .binary _ left right =>
      parserDescrPrecedence? kind left <|> parserDescrPrecedence? kind right
  | _ => none

unsafe def parserPrecedenceUnsafe
    (env : Environment) (options : Options) (kind : SyntaxNodeKind)
    : Option (Nat × Nat) :=
  match env.find? kind with
  | some info =>
      if info.type.isConstOf ``TrailingParserDescr then
        match env.evalConst ParserDescr options kind with
        | .ok parser => parserDescrPrecedence? kind parser
        | .error _ => none
      else
        none
  | none => none

@[implemented_by parserPrecedenceUnsafe]
opaque parserPrecedence
    (env : Environment) (options : Options) (kind : SyntaxNodeKind) : Option (Nat × Nat)

abbrev SpacedApplicationKindSet := NameSet

structure ParserOwnedBodyPolicy where
  suffixes : List String := []
  suffixOwnsBody : Bool := false
deriving Repr

abbrev ParserOwnedBodyMap := NameMap ParserOwnedBodyPolicy

partial def parserDescrSequence : ParserDescr -> List ParserDescr
  | .binary combinator left right =>
      if combinator == `andthen then
        parserDescrSequence left ++ parserDescrSequence right
      else
        [.binary combinator left right]
  | parser => [parser]

def parserDescrSymbolIsTight (symbol : String) : Bool :=
  symbol.toList.all
    fun char => char != ' ' && char != '\t' && char != '\n' && char != '\r'

def parserDescrSymbolIsApplicationHead (symbol : String) : Bool :=
  let symbol := symbol.trimAscii.toString
  parserDescrSymbolIsTight symbol && symbol.toList.any (·.isAlphanum)

def parserDescrIsApplicationHead : ParserDescr -> Bool
  | .symbol symbol
  | .nonReservedSymbol symbol _ => parserDescrSymbolIsApplicationHead symbol
  | .unicodeSymbol ascii unicode _ =>
      let ascii := ascii.trimAscii.toString
      let unicode := unicode.trimAscii.toString
      parserDescrSymbolIsTight ascii
      && parserDescrSymbolIsTight unicode
      && (ascii.toList.any (·.isAlphanum) || unicode.toList.any (·.isAlphanum))
  | _ => false

def parserDescrIsOptional : ParserDescr -> Bool
  | .unary combinator _ => combinator == `optional
  | _ => false

def parserDescrIsSpacedOperand : ParserDescr -> Bool
  | .cat category _ => category == `term || category == `ident
  | .const category => category == `ident
  | _ => false

partial def parserDescrIsSpacedApplication (kind : SyntaxNodeKind) : ParserDescr -> Bool
  | .node nodeKind _ parser
  | .nodeWithAntiquot _ nodeKind parser =>
      if nodeKind == kind then
        match parserDescrSequence parser with
        | [] | [_] => false
        | head :: rest =>
            parserDescrIsApplicationHead head
            && rest.getLast?.any parserDescrIsSpacedOperand
            && (rest.dropLast.all parserDescrIsOptional)
      else
        parserDescrIsSpacedApplication kind parser
  | .unary _ parser => parserDescrIsSpacedApplication kind parser
  | .binary _ left right =>
      parserDescrIsSpacedApplication kind left
      || parserDescrIsSpacedApplication kind right
  | _ => false

unsafe def parserDescribesSpacedApplicationUnsafe
    (env : Environment) (options : Options) (kind : SyntaxNodeKind)
    : Bool :=
  if !(KeyedDeclsAttribute.getValues
        PrettyPrinter.formatterAttribute env kind).isEmpty then
    false
  else
    match env.find? kind with
    | some info =>
        if info.type.isConstOf ``ParserDescr then
          match env.evalConst ParserDescr options kind with
          | .ok parser => parserDescrIsSpacedApplication kind parser
          | .error _ => false
        else
          false
    | none => false

@[implemented_by parserDescribesSpacedApplicationUnsafe]
opaque parserDescribesSpacedApplication
    (env : Environment) (options : Options) (kind : SyntaxNodeKind) : Bool

def parserDescrIsBodyLayoutConstraint : ParserDescr → Bool
  | .const parser => [`colGt, `colGe].contains parser
  | .unary _ parser => parserDescrIsBodyLayoutConstraint parser
  | .binary combinator left right =>
      combinator == `andthen
      && parserDescrIsBodyLayoutConstraint left
      && parserDescrIsBodyLayoutConstraint right
  | _ => false

partial def parserDescrIsOwnedTacticBody : ParserDescr → Bool
  | .const parser =>
      parser == `tacticSeq
      || parser == `tacticSeqIndentGt
      || parser == `Lean.Parser.Tactic.tacticSeq
      || parser == `Lean.Parser.Tactic.tacticSeqIndentGt
  | .unary _ parser => parserDescrIsOwnedTacticBody parser
  | .binary combinator constraint body =>
      combinator == `andthen
      && parserDescrIsBodyLayoutConstraint constraint
      && parserDescrIsOwnedTacticBody body
  | _ => false

partial def parserDescrIsOwnedBody : ParserDescr → Bool
  | .cat category _ => category == `term
  | .const parser =>
      parser == `tacticSeq
      || parser == `tacticSeqIndentGt
      || parser == `Lean.Parser.Tactic.tacticSeq
      || parser == `Lean.Parser.Tactic.tacticSeqIndentGt
  | .unary combinator parser =>
      combinator != `optional && parserDescrIsOwnedBody parser
  | _ => false

def parserDescrKeywordSuffixes : ParserDescr → List String
  | .symbol symbol
  | .nonReservedSymbol symbol _ =>
      let symbol := symbol.trimAscii.toString
      if symbol.toList.any (·.isAlphanum) then [symbol] else []
  | .unicodeSymbol ascii unicode _ =>
      [ascii, unicode].filterMap
        fun symbol =>
          let symbol := symbol.trimAscii.toString
          if symbol.toList.any (·.isAlphanum) then some symbol else none
  | _ => []

def parserDescrSuffixOwnedBodyClauseSuffixes (parser : ParserDescr) : List String :=
  match parserDescrSequence parser with
  | [suffix, body] =>
      if parserDescrIsOwnedBody body then parserDescrKeywordSuffixes suffix else []
  | _ => []

def parserDescrTrailingTacticBodySuffixes (parser : ParserDescr) : List String :=
  match parserDescrSequence parser |>.reverse with
  | body :: suffix :: _ =>
      if parserDescrIsOwnedTacticBody body then
        parserDescrKeywordSuffixes suffix
      else
        []
  | _ => []

def parserDescrTrailingBodySuffixes (parser : ParserDescr) : List String :=
  match parserDescrSequence parser with
  | [] | [_] => []
  | sequence =>
      match sequence.reverse with
      | body :: suffix :: preceding =>
          if !preceding.isEmpty && parserDescrIsOwnedBody body then
            parserDescrKeywordSuffixes suffix
          else
            match body with
            | .unary combinator clause =>
                if combinator == `optional && !sequence.dropLast.isEmpty then
                  parserDescrSuffixOwnedBodyClauseSuffixes clause
                else
                  []
            | _ => []
      | _ => []

def ParserOwnedBodyMap.insertSuffixes
    (owned : ParserOwnedBodyMap) (kind : SyntaxNodeKind) (suffixes : List String)
    (suffixOwnsBody : Bool)
    : ParserOwnedBodyMap :=
  let existing := (owned.find? kind).getD {}
  let suffixes :=
    suffixes.foldl
      (fun accumulated suffix =>
        if accumulated.contains suffix then accumulated else suffix :: accumulated)
      existing.suffixes
  if suffixes.isEmpty then
    owned
  else
    owned.insert kind
      { suffixes, suffixOwnsBody := existing.suffixOwnsBody || suffixOwnsBody }

partial def parserDescrOwnedTrailingBodySuffixes (parser : ParserDescr) : List String :=
  match parser with
  | .node _ _ parser
  | .nodeWithAntiquot _ _ parser =>
      parserDescrTrailingBodySuffixes parser
      ++ parserDescrOwnedTrailingBodySuffixes parser
  | .trailingNode _ _ _ parser =>
      parserDescrTrailingTacticBodySuffixes parser
  | .unary _ parser => parserDescrOwnedTrailingBodySuffixes parser
  | .binary _ left right =>
      parserDescrOwnedTrailingBodySuffixes left
      ++ parserDescrOwnedTrailingBodySuffixes right
  | _ => []

def parserKindOwnsCategory (env : Environment) (category kind : SyntaxNodeKind) : Bool :=
  (Parser.getParserCategory? env category).any
    fun parserCategory => parserCategory.kinds.contains kind

def parserKindOwnsCommandOrTacticLayout (env : Environment) (kind : SyntaxNodeKind)
    : Bool :=
  [`command, `tactic].any fun category => parserKindOwnsCategory env category kind

unsafe def parserOwnedTrailingBodiesUnsafe
    (env : Environment) (options : Options) (kind : SyntaxNodeKind)
    : ParserOwnedBodyMap :=
  if !parserKindOwnsCommandOrTacticLayout env kind then
    {}
  else
    match env.find? kind with
    | some info =>
        let isTrailing := info.type.isConstOf ``TrailingParserDescr
        let hasRegisteredFormatter :=
          !(KeyedDeclsAttribute.getValues
              PrettyPrinter.formatterAttribute env kind).isEmpty
        if (info.type.isConstOf ``ParserDescr || isTrailing)
            && !(isTrailing && hasRegisteredFormatter) then
          match env.evalConst ParserDescr options kind with
          | .ok parser =>
              ({} : ParserOwnedBodyMap).insertSuffixes kind
                (parserDescrOwnedTrailingBodySuffixes parser)
                (parserKindOwnsCategory env `tactic kind)
          | .error _ => {}
        else
          {}
    | none => {}

@[implemented_by parserOwnedTrailingBodiesUnsafe]
opaque parserOwnedTrailingBodies
    (env : Environment) (options : Options) (kind : SyntaxNodeKind)
    : ParserOwnedBodyMap

structure ParserLayoutFacts where
  checkedKinds : NameSet := {}
  infixPrecedences : InfixPrecedenceMap := {}
  spacedApplicationKinds : SpacedApplicationKindSet := {}
  parserOwnedBodies : ParserOwnedBodyMap := {}

def ParserLayoutFacts.record
    (facts : ParserLayoutFacts)
    (env : Environment) (options : Options) (kind : SyntaxNodeKind)
    : ParserLayoutFacts :=
  if facts.checkedKinds.contains kind then
    facts
  else
    let infixPrecedences :=
      match parserPrecedence env options kind with
      | some precedence => facts.infixPrecedences.insert kind precedence
      | none => facts.infixPrecedences
    let spacedApplicationKinds :=
      if parserDescribesSpacedApplication env options kind then
        facts.spacedApplicationKinds.insert kind
      else
        facts.spacedApplicationKinds
    let parserOwnedBodies :=
      (parserOwnedTrailingBodies env options kind).foldl
        (fun owned kind policy =>
          owned.insertSuffixes kind policy.suffixes policy.suffixOwnsBody)
        facts.parserOwnedBodies
    {
      checkedKinds := facts.checkedKinds.insert kind
      infixPrecedences
      spacedApplicationKinds
      parserOwnedBodies
    }

partial def collectParserLayoutFacts
    (env : Environment) (options : Options)
    (stx : Syntax) (facts : ParserLayoutFacts := {})
    : ParserLayoutFacts :=
  match stx with
  | .missing
  | .atom ..
  | .ident .. => facts
  | .node _ kind children =>
      children.foldl
        (fun facts child =>
          collectParserLayoutFacts env options child facts)
        (facts.record env options kind)

/-! ## Logical regrouping -/

private partial def directLeafAtomToken? : Tree → Option Token
  | .leaf token => if token.role == .atom then some token else none
  | .node (.raw `null) children =>
      match children.toList with
      | [child] => directLeafAtomToken? child
      | _ => none
  | _ => none

private partial def directLeafIdentToken? : Tree → Option Token
  | .leaf token => if token.role == .ident then some token else none
  | .node (.raw `null) children =>
      match children.toList with
      | [child] => directLeafIdentToken? child
      | _ => none
  | _ => none

def directLeafAtom? (tree : Tree) : Bool :=
  (directLeafAtomToken? tree).isSome

def isGeneratedTermKind (kind : Lean.SyntaxNodeKind) : Bool :=
  let name := toString kind
  name.startsWith "«term"
  || match name.splitOn ".«term" with
      | [_] => false
      | _ => true

def isGeneratedCommandKind (kind : Lean.SyntaxNodeKind) : Bool :=
  let name := toString kind
  name.startsWith "«command"
  || (name.splitOn ".").getLast?.any (fun segment => segment.startsWith "command")
  || match name.splitOn ".«command" with
      | [_] => false
      | _ => true

private def delimiterKindForLexemes? (opening closing : String) : Option DelimiterKind :=
  if opening.endsWith "(" && closing == ")" then
    some .paren
  else if opening.endsWith "[" && closing == "]" then
    some .bracket
  else if opening.endsWith "{" && closing == "}" then
    some .brace
  else if opening.endsWith "⟨" && closing == "⟩" then
    some .anonymousConstructor
  else if opening.endsWith "⟪" && closing == "⟫" then
    some .doubleAngle
  else if opening == "‖" && closing == "‖" then
    some .norm
  else
    none

def outerDelimiterKind? (children : Array Tree) : Option DelimiterKind := do
  let openingTree ←
    children.findSome?
      fun child =>
        if child.firstToken?.isSome then some child else none
  let closingTree ←
    children.findSomeRev?
      fun child =>
        if child.firstToken?.isSome then some child else none
  let opening ← openingTree.singleToken?
  let closing ← closingTree.singleToken?
  if opening.role != .atom || closing.role != .atom then
    none
  else
    delimiterKindForLexemes? opening.lexeme closing.lexeme

private def sourceTokensAreAdjacent (left right : Token) : Bool :=
  left.span.start < left.span.stop
  && right.span.start < right.span.stop
  && left.span.stop == right.span.start

private def generatedTightPiece?
    (firstToken lastToken : Option Token) (allowLeading : Bool) (left right : Tree)
    : Bool :=
  match directLeafAtomToken? left, right.firstToken?, right.lastToken? with
  | some left, some rightFirst, some rightLast =>
      let leading :=
        allowLeading
        && firstToken.any (·.span.start == left.span.start)
        && lexemeEndsWithOpeningDelimiter rightFirst.lexeme
      let trailing := lastToken.any (·.span.stop == rightLast.span.stop)
      sourceTokensAreAdjacent left rightFirst && (leading || trailing)
  | _, _, _ => false

private def generatedLeadingApplicationPiece?
    (firstToken : Option Token) (left right : Tree)
    : Bool :=
  match directLeafAtomToken? left, right with
  | some left, .node .application _ =>
      firstToken.any (·.span.start == left.span.start)
      && right.firstToken?.any fun rightFirst => sourceTokensAreAdjacent left rightFirst
  | _, _ => false

private def groupGeneratedTightPiece
    (firstToken : Option Token) (allowLeading : Bool) (left right : Tree)
    : Tree :=
  let leading :=
    allowLeading
    && (directLeafAtomToken? left).any
        fun token => firstToken.any (·.span.start == token.span.start)
  if leading then
    match right with
    | .node kind children => .node kind (#[left] ++ children)
    | _ => .node .suffixGroup #[left, right]
  else
    .node .suffixGroup #[left, right]

private def splitGeneratedLeadingApplication? (children : Array Tree)
    : Option (Array Tree) := do
  let #[.node .application applicationChildren] :=
    children.filter fun child => child.firstToken?.isSome | none
  let prefixTree ← applicationChildren[0]?
  let operandHead ← applicationChildren[1]?
  let prefixToken ← directLeafAtomToken? prefixTree
  let operandToken ← operandHead.firstToken?
  if !sourceTokensAreAdjacent prefixToken operandToken then
    none
  let operandChildren := applicationChildren.extract 1 applicationChildren.size
  let operand :=
    if operandChildren.size == 1 then
      operandHead
    else
      .node .application operandChildren
  some #[prefixTree, operand]

private def regroupGeneratedTightPieces (children : Array Tree) : Array Tree :=
  let children := (splitGeneratedLeadingApplication? children).getD children
  let tree := Tree.node (.raw `null) children
  let firstToken := tree.firstToken?
  let lastToken := tree.lastToken?
  let allowLeading := (children.filter fun child => child.firstToken?.isSome).size == 2
  let rec loop (remaining : List Tree) (result : Array Tree) : Array Tree :=
    match remaining with
    | left :: right :: rest =>
        if generatedLeadingApplicationPiece? firstToken left right then
          loop (right :: rest) <| result.push left
        else if generatedTightPiece? firstToken lastToken allowLeading left right then
          loop rest
          <| result.push
          <| groupGeneratedTightPiece firstToken allowLeading left right
        else
          loop (right :: rest) <| result.push left
    | [last] => result.push last
    | [] => result
  loop children.toList #[]

private def regroupGeneratedSuffixApplication?
    (kind : SyntaxNodeKind) (children : Array Tree)
    : Option Tree := do
  if !isGeneratedTermKind kind then
    none
  let head ← children[0]?
  let suffix ← children[1]?
  let arguments ← children[2]?
  if children.size != 3 then
    none
  let headToken ← directLeafIdentToken? head
  let suffixToken ← directLeafAtomToken? suffix
  if !sourceTokensAreAdjacent headToken suffixToken then
    none
  let .node .application argumentChildren := arguments | none
  if argumentChildren.size < 2 then
    none
  some <| .node .application (#[.node .suffixGroup #[head, suffix]] ++ argumentChildren)

private def regroupSpacedApplication?
    (spacedApplicationKinds : SpacedApplicationKindSet)
    (kind : SyntaxNodeKind) (children : Array Tree)
    : Option Tree := do
  let generated := isGeneratedTermKind kind
  if !generated && !spacedApplicationKinds.contains kind then
    none
  let contentIndexes :=
    (List.range children.size).filter
      fun index => children[index]?.bind Tree.firstToken? |>.isSome
  if contentIndexes.length < (if generated then 3 else 2)
      || contentIndexes.head? != some 0 then
    none
  let head ← children[0]?
  if !directLeafAtom? head then
    none
  let rec separatorsAreSpaces : List Nat → Bool
    | left :: right :: rest =>
        let separatorsHaveNoContent :=
          (List.range' (left + 1) (right - left - 1)).all
            fun index => children[index]?.bind Tree.firstToken? |>.isNone
        let generatedSeparator :=
          right == left + 2
          && (children[left + 1]?).any fun separator => rawKind? separator == some `group
        let sourceHasSpace :=
          match children[left]? >>= Tree.lastToken?,
                children[right]? >>= Tree.firstToken? with
          | some leftToken, some rightToken =>
              !sourceTokensAreAdjacent leftToken rightToken
          | _, _ => false
        separatorsHaveNoContent
        && (if generated then generatedSeparator else sourceHasSpace)
        && separatorsAreSpaces (right :: rest)
    | _ => true
  if !separatorsAreSpaces contentIndexes then
    none
  let arguments := contentIndexes.drop 1 |>.filterMap fun index => children[index]?
  if generated && arguments.any directLeafAtom? then
    none
  let arguments := arguments.toArray
  let commentPayloadBody? : Option Tree := do
    if generated || arguments.size < 2 then
      none
    let body ← arguments.back?
    let headerArguments := arguments.extract 0 (arguments.size - 1)
    if headerArguments.any
        fun argument =>
          argument.containsNodeKind (.raw `Lean.Parser.Command.docComment) then
      some
      <| .node .parserOwnedBody #[.node .suffixGroup (#[head] ++ headerArguments), body]
    else
      none
  commentPayloadBody?.getD <| .node .application (#[head] ++ arguments)

private def regroupPrefixedDeclaration? (children : Array Tree) : Option Tree := do
  if children.size != 2 then
    none
  let prefixTree ← children[0]?
  let declaration ← children[1]?
  let _ ← directLeafAtomToken? prefixTree
  if rawKind? declaration != some `Lean.Parser.Term.letDecl then
    none
  some <| .node .suffixGroup #[prefixTree, declaration]

private def regroupPrefixedApplication? (children : Array Tree)
    : Option (Array Tree) := do
  let #[prefixTree, .node (.raw `null) #[.node .application applicationChildren]] :=
    children | none
  let head ← applicationChildren[0]?
  let prefixedHead := .node .suffixGroup #[prefixTree, head]
  some
    #[
      .node .application
        (#[prefixedHead] ++ applicationChildren.extract 1 applicationChildren.size)
    ]

def isBinaryInfixRawNode (kind : SyntaxNodeKind) (children : Array Tree) : Bool :=
  let hasLeftOperand := children[0]?.any fun child => child.firstToken?.isSome
  let hasRightOperand := children[2]?.any fun child => child.firstToken?.isSome
  kind != `null
  && kind != `Lean.Parser.Term.app
  && children.size == 3
  && hasLeftOperand
  && hasRightOperand
  && match children[1]? with
      | some operator => directLeafAtom? operator
      | none => false

private def isIndexedInfixRawNode (kind : SyntaxNodeKind) (children : Array Tree)
    : Bool :=
  let hasLeftOperand := children[0]?.any fun child => child.firstToken?.isSome
  let hasIndex := children[2]?.any fun child => child.firstToken?.isSome
  let hasRightOperand := children[4]?.any fun child => child.firstToken?.isSome
  kind != `null
  && kind != `Lean.Parser.Term.app
  && children.size == 5
  && hasLeftOperand
  && hasIndex
  && hasRightOperand
  && match children[1]?, children[3]? with
      | some operator, some closing =>
          match directLeafAtomToken? operator, directLeafAtomToken? closing with
          | some operator, some closing =>
              operator.lexeme != "["
              && operator.lexeme.endsWith "["
              && closing.lexeme == "]"
          | _, _ => false
      | _, _ => false

def appendApplicationArgumentChildren (argumentContainer : Tree) : Array Tree :=
  match argumentContainer with
  | .node (.raw `null) children => children
  | child => #[child]

def infixKindsSharePrecedence
    (infixPrecedences : InfixPrecedenceMap)
    (left right : SyntaxNodeKind)
    : Bool :=
  left == right
  || match infixPrecedences.find? left, infixPrecedences.find? right with
      | some leftPrecedence, some rightPrecedence =>
          leftPrecedence == rightPrecedence
      | _, _ => false

def appendInfixParts
    (infixPrecedences : InfixPrecedenceMap)
    (kind : SyntaxNodeKind) (parts : Array Tree) (tree : Tree)
    : Array Tree :=
  match tree with
  | .node (.infixChain childKind) children =>
      if infixKindsSharePrecedence infixPrecedences kind childKind then
        parts ++ children
      else
        parts.push tree
  | _ => parts.push tree

private def isTransparentTacticSequenceWrapperKind : NodeKind -> Bool
  | .raw kind => kind == `null || Tree.isTacticSequenceKind kind
  | .tactic kind _ _ _ _ => Tree.isTacticSequenceKind kind
  | _ => false

private partial def attachPrefixToOperandHead (prefixTree : Tree) : Tree → Tree
  | .node kind children =>
      let contentIndexes :=
        (List.range children.size).filter
          fun index => children[index]?.bind Tree.firstToken? |>.isSome
      if isTransparentTacticSequenceWrapperKind kind then
        match contentIndexes.head? with
        | some childIndex =>
            match children[childIndex]? with
            | some child =>
                .node kind
                  (children.set! childIndex (attachPrefixToOperandHead prefixTree child))
            | none => .node kind children
        | none => .node kind children
      else
        match kind with
        | .application
        | .infixChain _
        | .indexedInfix _
        | .letExpression _ _
        | .raw `Lean.Parser.Term.let
        | .raw `Lean.Parser.Term.letrec
        | .tactic _ _ _ _ true =>
            match contentIndexes.head? with
            | some headIndex =>
                match children[headIndex]? with
                | some head =>
                    .node kind
                      (children.set! headIndex
                        (attachPrefixToOperandHead prefixTree head))
                | none => .node kind children
            | none => .node kind children
        | .suffixGroup => .node .suffixGroup (#[prefixTree] ++ children)
        | _ => .node .suffixGroup #[prefixTree, .node kind children]
  | operand => .node .suffixGroup #[prefixTree, operand]

def lowPriorityRhsCanFlow (rhs : Tree) : Bool :=
  rhs.firstToken?.any
    fun token =>
      [
        "by",
        "calc",
        "do",
        "from",
        "using",
        "using!",
        "where",
        "with",
        "deriving",
        "then",
        "else"
      ].contains
        token.lexeme

def lowPriorityRhsHasAttachedBody (rhs : Tree) : Bool :=
  rhs.firstToken?.any
    fun token => ["by", "calc", "do", "let", "have", "haveI"].contains token.lexeme

def regroupFromTermChildren (children : Array Tree) : Array Tree :=
  match children.findIdx? fun child => child.singleToken?.any (·.lexeme == "from") with
  | some fromIndex =>
      match children[fromIndex]?, children[fromIndex + 1]? with
      | some fromKeyword, some operand =>
          children
          |>.set! fromIndex .missing
          |>.set! (fromIndex + 1) (attachPrefixToOperandHead fromKeyword operand)
      | _, _ => children
  | none => children

def regroupLowPriorityInfixRhs (parts : Array Tree) : Array Tree :=
  match parts.toList with
  | [] => #[]
  | first :: rest =>
      let rec loop : List Tree → List Tree
        | rhs@(.node .lowPriorityInfixRhs _) :: rest => rhs :: loop rest
        | operator :: rhs :: rest =>
            let canFlow := lowPriorityRhsCanFlow rhs
            let hasAttachedBody := lowPriorityRhsHasAttachedBody rhs
            .node .lowPriorityInfixRhs
              #[.node (.lowPriorityOperand canFlow hasAttachedBody) #[operator], rhs]
            :: loop rest
        | _ => []
      (first :: loop rest).toArray

def regroupSignatureParameters : Tree → Tree
  | .node (.raw `null) children => .node .signatureParameters children
  | tree => tree

def flattenDeclarationIdentifierChild : Tree → Array Tree
  | .node (.raw `Lean.Parser.Command.optDeclSig) children
  | .node (.raw `Lean.Parser.Command.declSig) children =>
      children.flatMap
        fun child =>
          match child with
          | .node .signatureParameters parameters => parameters
          | child => #[child]
  | child => #[child]

def regroupDeclarationIdentifierChildren (children : Array Tree) : Array Tree :=
  let children :=
    match children[0]?, children[1]? with
    | some identifier, some universeSuffix =>
        if universeSuffix.firstToken?.isSome then
          #[Tree.node .suffixGroup #[identifier, universeSuffix]]
          ++ children.extract 2 children.size
        else
          children
    | _, _ => children
  children.flatMap flattenDeclarationIdentifierChild

def regroupSeparatedDeclarationSignatureChildren (children : Array Tree) : Array Tree :=
  match children.findIdx?
          fun child => rawKind? child == some `Lean.Parser.Command.declId with
  | some identifierIndex =>
      match children[identifierIndex]?, children[identifierIndex + 1]? with
      | some (.node (.raw `Lean.Parser.Command.declId) identifierChildren),
        some signature =>
          if rawKind? signature == some `Lean.Parser.Command.optDeclSig
              || rawKind? signature == some `Lean.Parser.Command.declSig then
            children
            |>.set! identifierIndex
                (.node (.raw `Lean.Parser.Command.declId)
                  (identifierChildren ++ flattenDeclarationIdentifierChild signature))
            |>.set! (identifierIndex + 1) .missing
          else
            children
      | _, _ => children
  | none => children

def regroupUnifHintChildren (children : Array Tree) : Array Tree :=
  let children :=
    match children[4]? with
    | some parameters => children.set! 4 (regroupSignatureParameters parameters)
    | none => children
  match children[6]? with
  | some (Tree.node (NodeKind.raw `null) constraints) =>
      children.set! 6 (.node .unifConstraints constraints)
  | _ => children

def regroupMatchPatterns : Tree → Tree
  | .node (.raw `null) children =>
      if children.size == 1 then
        match children[0]? with
        | some (Tree.node (.raw `null) nested) => .node .matchPatterns nested
        | _ => .node .matchPatterns children
      else
        .node .matchPatterns children
  | tree => tree

def regroupMatchDiscriminants : Tree → Tree
  | .node (.raw `null) children => .node .matchDiscriminants children
  | tree => .node .matchDiscriminants #[tree]

def previousContentIndex? (children : Array Tree) (index : Nat) : Option Nat :=
  (List.range index).foldl
    (fun found candidate =>
      match children[candidate]? >>= Tree.firstToken? with
      | some _ => some candidate
      | none => found)
    none

def regroupMatchDiscriminantsBeforeWith (children : Array Tree) : Array Tree :=
  match children.findIdx?
          fun child =>
            (Tree.firstToken? child).map (fun token => token.lexeme) == some "with" with
  | some withIndex =>
      match previousContentIndex? children withIndex with
      | some discriminantsIndex =>
          match children[discriminantsIndex]?, children[withIndex]? with
          | some discriminants, some withKeyword =>
              let discriminants := regroupMatchDiscriminants discriminants
              if discriminants.containsNodeKind (.raw `Lean.Parser.Term.match) then
                let header := .node .matchHeader #[discriminants, withKeyword]
                children.set! discriminantsIndex header |>.set! withIndex .missing
              else
                children.set! discriminantsIndex discriminants
          | _, _ => children
      | none => children
  | none => children

def unwrapSingleNullChild (children : Array Tree) : Array Tree :=
  if children.size == 1 then
    match children[0]? with
    | some (Tree.node (.raw `null) wrappedChildren) => wrappedChildren
    | _ => children
  else
    children

def childrenRange (children : Array Tree) (start stop : Nat) : Array Tree :=
  (List.range (stop - start)).foldl
    (fun acc offset =>
      match children[start + offset]? with
      | some child => acc.push child
      | none => acc)
    #[]

def appendApplicationArgumentContainers (children : Array Tree) (start : Nat)
    : Array Tree :=
  (childrenRange children start children.size).foldl
    (fun arguments container =>
      arguments ++ appendApplicationArgumentChildren container)
    #[]

partial def structInstFieldParts? : Tree → Option (Array Tree)
  | .node (.raw `Lean.Parser.Term.structInstFieldDef) children => some children
  | .node _ children =>
      let rec loop (index : Nat) : Option (Array Tree) := do
        let child ← children[index]?
        match structInstFieldParts? child with
        | some parts =>
            some
            <| childrenRange children 0 index
                ++ parts
                ++ childrenRange children (index + 1) children.size
        | none => loop (index + 1)
      loop 0
  | _ => none

def doForDeclChildren? : Tree → Option (Array Tree)
  | .node (.raw `Lean.Parser.Term.doForDecl) children => some children
  | .node (.raw `null) children =>
      match children.toList with
      | [.node (.raw `Lean.Parser.Term.doForDecl) children] => some children
      | _ => none
  | _ => none

def regroupDoForChildren (children : Array Tree) : Option (Array Tree) := do
  let keyword ← children[0]?
  let declaration ← children[1]?
  let declarationChildren ← doForDeclChildren? declaration
  some
  <| #[.node .doForHeader (#[keyword] ++ declarationChildren)]
      ++ childrenRange children 2 children.size

def regroupDeclarationHeader (children : Array Tree) : Option (Array Tree) := do
  let name ← children[0]?
  let parameters ← children[1]?
  let typeSpec ← children[2]?
  some
  <| #[
        .node .declarationHeader #[name, regroupSignatureParameters parameters, typeSpec]
      ]
      ++ childrenRange children 3 children.size

def singleContentChild? (children : Array Tree) : Option Tree :=
  let content := children.filter fun child => child.firstToken?.isSome
  if content.size == 1 then content[0]? else none

partial def attachedDoTree? : Tree → Option Tree
  | tree@(.node (.raw kind) children) =>
      if kind == `Lean.Parser.Term.doNested then
        some tree
      else if kind == `Lean.Parser.Term.doSeqIndent
              || kind == `Lean.Parser.Term.doSeqItem
              || kind == `null then
        singleContentChild? children >>= attachedDoTree?
      else
        none
  | _ => none

private def regroupRightmostOwnedChildren
    (children : Array Tree) (ownedRight? : Tree → Option Tree)
    (groupPair? : Tree → Tree → Option Tree)
    : Array Tree :=
  let contentIndexes :=
    (List.range children.size).filter
      fun index => children[index]?.bind Tree.firstToken? |>.isSome
  let rec loop : List Nat → Array Tree
    | rightIndex :: leftIndex :: rest =>
        match children[leftIndex]?, children[rightIndex]? with
        | some left, some right =>
            match ownedRight? right with
            | some right =>
                match groupPair? left right with
                | some group =>
                    children.set! leftIndex group |>.set! rightIndex .missing
                | none => loop (leftIndex :: rest)
            | none => children
        | _, _ => loop (leftIndex :: rest)
    | _ => children
  loop contentIndexes.reverse

private def regroupRightmostSuffixChildren
    (children : Array Tree) (ownedRight? : Tree → Option Tree)
    (ownsPair : Tree → Tree → Bool := fun left _ => directLeafAtom? left)
    : Array Tree :=
  regroupRightmostOwnedChildren children ownedRight?
    fun left right =>
      if ownsPair left right then some <| .node .suffixGroup #[left, right] else none

private def treeStartsAttachedBody (tree : Tree) : Bool :=
  tree.firstToken?.any fun token => token.lexeme == "do" || token.lexeme == "by"

private def regroupOptionalPrivateValue (children : Array Tree) : Array Tree :=
  regroupRightmostOwnedChildren children (fun tree => some tree)
    fun left right =>
      if directLeafAtomToken? left |>.any fun token => token.lexeme == "private" then
        some
        <| match right with
            | .node (.raw `Lean.Parser.Term.fun) children =>
                .node (.raw `Lean.Parser.Term.fun) (#[left] ++ children)
            | _ => .node .suffixGroup #[left, right]
      else
        none

private def startsWithOpeningDelimiter (tree : Tree) : Bool :=
  tree.firstToken?.any fun token => lexemeEndsWithOpeningDelimiter token.lexeme

private partial def splitLeadingToken? (accepts : Token → Bool)
    : Tree → Option (Tree × Tree)
  | tree@(.leaf token) =>
      if accepts token then
        some (tree, .missing)
      else
        none
  | .node kind children => do
      let index ←
        (List.range children.size).find?
          fun index => children[index]?.bind Tree.firstToken? |>.isSome
      let child ← children[index]?
      let (token, child) ← splitLeadingToken? accepts child
      some (token, .node kind (children.set! index child))
  | .missing => none

private def regroupTerminalLeadingTokenChildren
    (children : Array Tree) (ownsRight : Tree → Bool) (accepts : Token → Bool)
    (normalizeRemainder : Tree → Tree := id)
    : Array Tree :=
  match ((List.range children.size).filter
          fun index => children[index]?.bind Tree.firstToken? |>.isSome).reverse with
  | rightIndex :: leftIndex :: _ =>
      match children[leftIndex]?, children[rightIndex]? with
      | some left, some right =>
          if directLeafAtom? left && ownsRight right && right.firstToken?.any accepts then
            match splitLeadingToken? accepts right with
            | some (token, right) =>
                children.set! leftIndex (.node .suffixGroup #[left, token])
                |>.set! rightIndex (normalizeRemainder right)
            | none => children
          else
            children
      | _, _ => children
  | _ => children

private partial def unwrapAttachedBodyRemainder : Tree → Tree
  | tree@(.node (.raw kind) children) =>
      if kind == `Lean.Parser.Term.do
          || kind == `Lean.Parser.Term.doNested
          || kind == `Lean.Parser.Term.byTactic
          || kind == `Lean.Parser.Term.byTactic'
          || kind == `Lean.Parser.Command.macroRhs then
        match singleContentChild? children with
        | some child => unwrapAttachedBodyRemainder child
        | none => tree
      else
        tree
  | tree => tree

private def regroupAttachedBodyIntroducerChildren
    (children : Array Tree)
    (accepts : Token → Bool := fun token => token.lexeme == "do" || token.lexeme == "by")
    : Array Tree :=
  let contentIndexes :=
    (List.range children.size).filter
      fun index => children[index]?.bind Tree.firstToken? |>.isSome
  let rec loop : List Nat → Array Tree
    | rightIndex :: leftIndex :: rest =>
        match children[leftIndex]?, children[rightIndex]? with
        | some left, some right =>
            if right.firstToken?.any accepts then
              match splitLeadingToken? accepts right with
              | some (introducer, body) =>
                  children.set! leftIndex (.node .suffixGroup #[left, introducer])
                  |>.set! rightIndex (unwrapAttachedBodyRemainder body)
              | none => children
            else
              loop (leftIndex :: rest)
        | _, _ => loop (leftIndex :: rest)
    | _ => children
  loop contentIndexes.reverse

private def regroupNestedAttachedBodyChildren? (children : Array Tree)
    : Option (Array Tree) := do
  let nestedIndex ←
    ((List.range children.size).filter
      fun index => children[index]?.bind Tree.firstToken? |>.isSome).getLast?
  let .node nestedKind nestedChildren ← children[nestedIndex]? | none
  let bodyIndex ←
    ((List.range nestedChildren.size).filter
      fun index => nestedChildren[index]?.bind Tree.firstToken? |>.isSome).getLast?
  let body@(.node (.proofBody _) _) ← nestedChildren[bodyIndex]? | none
  let nestedHeader := .node nestedKind (nestedChildren.set! bodyIndex .missing)
  let header := .node .suffixGroup (children.set! nestedIndex nestedHeader)
  some #[header, body]

private partial def splitParserOwnedBody? (suffixes : List String)
    : Tree → Option (Tree × Tree × Tree)
  | .node kind children => do
      let contentIndexes :=
        (List.range children.size).filter
          fun index => children[index]?.bind Tree.firstToken? |>.isSome
      let bodyIndex ← contentIndexes.getLast?
      let suffixIndex ← previousContentIndex? children bodyIndex
      let suffix ← children[suffixIndex]?
      let body ← children[bodyIndex]?
      match directLeafAtomToken? suffix with
      | some token =>
          if suffixes.contains token.lexeme then
            let headerPrefix :=
              .node kind <| children.set! suffixIndex .missing |>.set! bodyIndex .missing
            some (headerPrefix, suffix, body)
          else
            let (nestedPrefix, suffix, body) ← splitParserOwnedBody? suffixes body
            some (.node kind (children.set! bodyIndex nestedPrefix), suffix, body)
      | none =>
          let (nestedPrefix, suffix, body) ← splitParserOwnedBody? suffixes body
          some (.node kind (children.set! bodyIndex nestedPrefix), suffix, body)
  | _ => none

private def attachParserOwnedHeaderHead (children : Array Tree) : Array Tree :=
  let contentIndexes :=
    (List.range children.size).filter
      fun index => children[index]?.any fun child => !child.tokens.isEmpty
  match contentIndexes with
  | firstIndex :: modifierIndex :: argumentIndex :: _ =>
      match children[firstIndex]?, children[modifierIndex]?, children[argumentIndex]? with
      | some first, some modifier, some argument =>
          if modifier.singleToken?.isSome && startsWithOpeningDelimiter argument then
            children.set! firstIndex .missing
            |>.set! modifierIndex .missing
            |>.set! argumentIndex (.node .suffixGroup #[first, modifier, argument])
          else
            let attached :=
              match modifier with
              | .node .suffixGroup modifierChildren =>
                  .node .suffixGroup <| #[first] ++ modifierChildren
              | _ => .node .suffixGroup #[first, modifier]
            children.set! firstIndex .missing |>.set! modifierIndex attached
      | _, _, _ => children
  | firstIndex :: argumentIndex :: _ =>
      match children[firstIndex]?, children[argumentIndex]? with
      | some first, some argument =>
          let attached :=
            match argument with
            | .node .suffixGroup argumentChildren =>
                .node .suffixGroup <| #[first] ++ argumentChildren
            | _ => .node .suffixGroup #[first, argument]
          children.set! firstIndex .missing |>.set! argumentIndex attached
      | _, _ => children
  | _ => children

private partial def isParserOwnedTacticBody : Tree → Bool
  | tree@(.node (.raw `null) children) =>
      tree.isTacticSequenceTree
      || (singleContentChild? children).any isParserOwnedTacticBody
  | tree => tree.isTacticSequenceTree

private def regroupParserOwnedBody?
    (kind : SyntaxNodeKind) (policy : ParserOwnedBodyPolicy) (children : Array Tree)
    : Option Tree := do
  let (headerPrefix, suffix, body) ←
    splitParserOwnedBody? policy.suffixes (.node (.raw kind) children)
  let suffixOwnsBody := policy.suffixOwnsBody
  let header :=
    match headerPrefix with
    | .node _ children =>
        let contentIndexes :=
          (List.range children.size).filter
            fun index => children[index]?.bind Tree.firstToken? |>.isSome
        match contentIndexes.getLast? with
        | some index =>
            let flattenLastChildren (lastChildren : Array Tree) :=
              let lastChildren :=
                if suffixOwnsBody then
                  lastChildren
                else
                  let lastContentIndex? :=
                    ((List.range lastChildren.size).filter
                      fun index => lastChildren[index]?.bind Tree.firstToken? |>.isSome)
                    |>.getLast?
                  match lastContentIndex? with
                  | some lastContentIndex =>
                      match lastChildren[lastContentIndex]? with
                      | some lastContent =>
                          lastChildren.set! lastContentIndex
                            (.node .suffixGroup #[lastContent, suffix])
                      | none => lastChildren
                  | none => lastChildren.push suffix
              childrenRange children 0 index
              ++ lastChildren
              ++ childrenRange children (index + 1) children.size
            match children[index]? with
            | some (.node (.raw _) lastChildren) =>
                .node .parserOwnedHeader
                  (attachParserOwnedHeaderHead <| flattenLastChildren lastChildren)
            | some (.node (.tactic _ _ false false _) lastChildren) =>
                .node .parserOwnedHeader
                  (attachParserOwnedHeaderHead <| flattenLastChildren lastChildren)
            | some last =>
                let children :=
                  if suffixOwnsBody then
                    children
                  else
                    children.set! index (.node .suffixGroup #[last, suffix])
                .node .parserOwnedHeader (attachParserOwnedHeaderHead children)
            | none => if suffixOwnsBody then headerPrefix else suffix
        | none => if suffixOwnsBody then headerPrefix else suffix
    | tree =>
        if suffixOwnsBody then
          .node .parserOwnedHeader #[tree]
        else
          .node .parserOwnedHeader #[.node .suffixGroup #[tree, suffix]]
  let body :=
    if suffixOwnsBody then
      if isParserOwnedTacticBody body then
        .node .parserOwnedSuffixBody
          #[
            .node .suffixGroup
              #[suffix, .node (.proofBody body.containsTacticLayoutOwner) #[body]]
          ]
      else
        .node .suffixGroup #[suffix, body]
    else
      body
  some <| .node .parserOwnedBody #[header, body]

private def regroupDoIfElseBodySuffix : Tree → Tree
  | .node (.raw `null) children =>
      .node (.raw `null) <| regroupRightmostSuffixChildren children attachedDoTree?
  | tree => tree

private def regroupTacticTerminalDelimiter : Tree → Tree
  | .node kind@(.tactic rawKind containsSequence isOwner _ isSpacedApplication)
      children =>
      let terminalIndex? :=
        ((List.range children.size).filter
          fun index => children[index]?.bind Tree.firstToken? |>.isSome).getLast?
      let terminalToken? :=
        terminalIndex?.bind fun index => children[index]? >>= Tree.firstToken?
      let delimiterWasDetached :=
        terminalToken?.any fun token => token.leading.text.contains '\n'
      let grouped :=
        regroupRightmostSuffixChildren children
          fun tree => if startsWithOpeningDelimiter tree then some tree else none
      if grouped == children then
        .node kind children
      else if !isOwner && delimiterWasDetached then
        match terminalIndex? with
        | some index =>
            match children[index]? with
            | some body =>
                if body.isTacticSequenceTree then
                  let header :=
                    .node (.tactic rawKind false false false isSpacedApplication)
                      (children.set! index .missing)
                  .node .parserOwnedBody
                    #[header, .node (.proofBody body.containsTacticLayoutOwner) #[body]]
                else
                  .node (.tactic rawKind containsSequence true true isSpacedApplication)
                    grouped
            | none => .node kind grouped
        | none => .node kind grouped
      else
        .node kind grouped
  | tree => tree

private partial def containsPrefixedTacticLayoutOwner : Tree -> Bool
  | tree@(.node (.raw kind) children)
  | tree@(.node (.tactic kind _ _ _ _) children) =>
      Tree.tacticKindOwnsStructuralLayout kind
      || Tree.isCalcTree tree
      || children.any containsPrefixedTacticLayoutOwner
  | .node _ children => children.any containsPrefixedTacticLayoutOwner
  | _ => false

private partial def regroupSpacedTacticFirstOperands : Tree → Tree
  | .node kind children =>
      let children := children.map regroupSpacedTacticFirstOperands
      match kind with
      | kind@(.tactic _ _ _ _ true) =>
          let contentIndexes :=
            (List.range children.size).filter
              fun index => children[index]?.bind Tree.firstToken? |>.isSome
          match contentIndexes with
          | prefixIndex :: operandIndex :: _ =>
              match children[prefixIndex]?, children[operandIndex]? with
              | some prefixTree, some operand =>
                  let attached := attachPrefixToOperandHead prefixTree operand
                  .node kind
                    (children.set! prefixIndex attached |>.set! operandIndex .missing)
              | _, _ => .node kind children
          | _ => .node kind children
      | _ => .node kind children
  | tree => tree

private def regroupTacticSequenceWrapperPrefix : Tree → Tree
  | .node kind@(.tactic _ _ _ _ _) children =>
      .node kind
      <| regroupRightmostOwnedChildren children
          (fun tree => if Tree.isTacticSequenceTree tree then some tree else none)
          fun left right =>
            if left.singleToken?.any (·.role == .atom)
                && Tree.sharesSourceLineWith left right then
              if left.singleToken?.any (·.lexeme != "·")
                  && containsPrefixedTacticLayoutOwner right then
                some <| attachPrefixToOperandHead left right
              else
                some <| .node .suffixGroup #[left, right]
            else
              none
  | tree => tree

private def tacticEndsWithDetachedBodySuffix (parserOwnedBodies : ParserOwnedBodyMap)
    : Tree → Bool
  | tree@(.node (.raw kind) _)
  | tree@(.node (.tactic kind _ _ _ _) _) =>
      tree.lastToken?.any
        fun token =>
          ((parserOwnedBodies.find? kind).any
            fun policy => policy.suffixes.contains token.lexeme)
          || (isCoreTacticKindName (toString kind) && token.lexeme == "=>")
  | _ => false

private partial def splitTrailingOwnedSuffix? (suffixes : List String)
    : Tree → Option (Tree × Tree)
  | tree@(.leaf token) =>
      if suffixes.contains token.lexeme then some (.missing, tree) else none
  | .node kind children => do
      let index ←
        ((List.range children.size).filter
          fun index => children[index]?.bind Tree.lastToken? |>.isSome).getLast?
      let child ← children[index]?
      let (child, suffix) ← splitTrailingOwnedSuffix? suffixes child
      some (.node kind (children.set! index child), suffix)
  | .missing => none

private def splitDetachedParserOwnedSuffix?
    (parserOwnedBodies : ParserOwnedBodyMap) (tree : Tree)
    : Option (Tree × Tree) := do
  let suffixes ←
    match tree with
    | .node (.raw kind) _
    | .node (.tactic kind _ _ _ _) _ =>
        (parserOwnedBodies.find? kind).map (·.suffixes)
    | .node .parserOwnedHeader _ =>
        tree.lastToken?.map fun token => [token.lexeme]
    | _ => none
  splitTrailingOwnedSuffix? suffixes tree

private def attachDetachedParserOwnedBody (header suffix body : Tree) : Tree :=
  let body :=
    .node .parserOwnedSuffixBody
      #[
        .node .suffixGroup
          #[suffix, .node (.proofBody body.containsTacticLayoutOwner) #[body]]
      ]
  .node .parserOwnedBody #[header, body]

private def regroupDirectParserOwnedTacticBody?
    (parserOwnedBodies : ParserOwnedBodyMap) (kind : NodeKind) (children : Array Tree)
    : Option Tree := do
  let .tactic _ _ _ _ _ := kind | none
  let bodyIndex ←
    ((List.range children.size).filter
      fun index => children[index]?.bind Tree.firstToken? |>.isSome).getLast?
  let body ← children[bodyIndex]?
  if !body.isTacticSequenceTree then
    none
  let header := .node kind (children.set! bodyIndex .missing)
  if let some (header, suffix) :=
      splitDetachedParserOwnedSuffix? parserOwnedBodies header then
    return attachDetachedParserOwnedBody header suffix body
  if !tacticEndsWithDetachedBodySuffix parserOwnedBodies header then
    none
  let body := .node (.proofBody body.containsTacticLayoutOwner) #[body]
  some <| .node .parserOwnedBody #[header, body]

private partial def regroupDetachedParserOwnedTacticBodiesCore
    (parserOwnedBodies : ParserOwnedBodyMap)
    : Tree → Tree × Bool
  | .node kind children =>
      let regroupedChildren :=
        children.map (regroupDetachedParserOwnedTacticBodiesCore parserOwnedBodies)
      let children := regroupedChildren.map fun (child, _) => child
      let containsDetached := regroupedChildren.any fun (_, contains) => contains
      let rec loop (grouped : Array Tree) (containsDetached : Bool)
          : List Tree → Array Tree × Bool
        | header :: body :: rest =>
            if body.isTacticSequenceTree then
              match splitDetachedParserOwnedSuffix? parserOwnedBodies header with
              | some (header, suffix) =>
                  loop
                    (grouped.push <| attachDetachedParserOwnedBody header suffix body)
                    true rest
              | none =>
                  if tacticEndsWithDetachedBodySuffix parserOwnedBodies header then
                    let body := .node (.proofBody body.containsTacticLayoutOwner) #[body]
                    loop (grouped.push <| .node .parserOwnedBody #[header, body]) true
                      rest
                  else
                    loop (grouped.push header) containsDetached (body :: rest)
            else
              loop (grouped.push header) containsDetached (body :: rest)
        | [child] => (grouped.push child, containsDetached)
        | [] => (grouped, containsDetached)
      let (children, containsDetached) := loop #[] containsDetached children.toList
      let (children, containsDetached) :=
        match kind, children.toList with
        | .parserOwnedBody, [_, .node .parserOwnedSuffixBody _] =>
            (children, true)
        | .parserOwnedBody, [header, body] =>
            if body.isTacticSequenceTree && !Tree.sharesSourceLineWith header body then
              (#[header, .node (.proofBody body.containsTacticLayoutOwner) #[body]], true)
            else
              (children, containsDetached)
        | _, _ => (children, containsDetached)
      let containsDetached :=
        containsDetached
        || match kind, children.toList with
            | .parserOwnedBody, [_, .node (.proofBody _) _] => true
            | _, _ => false
      let kind : NodeKind :=
        match kind with
        | .tactic rawKind containsSequence isOwner containsOwner isSpacedApplication =>
            if containsDetached then
              .tactic rawKind containsSequence isOwner true isSpacedApplication
            else
              .tactic rawKind containsSequence isOwner containsOwner isSpacedApplication
        | .proofBody containsOwner =>
            if containsDetached then
              .proofBody true
            else
              .proofBody containsOwner
        | _ => kind
      match kind, singleContentChild? children with
      | .parserOwnedBody, some child@(.node .parserOwnedBody _) => (child, true)
      | _, _ =>
          match regroupDirectParserOwnedTacticBody? parserOwnedBodies kind children with
          | some tree => (tree, true)
          | none => (.node kind children, containsDetached)
  | tree => (tree, false)

private def regroupDetachedParserOwnedTacticBodies
    (parserOwnedBodies : ParserOwnedBodyMap) (tree : Tree)
    : Tree :=
  (regroupDetachedParserOwnedTacticBodiesCore parserOwnedBodies tree).1

private def regroupMatchAltBodySuffix (children : Array Tree) : Array Tree :=
  regroupTerminalLeadingTokenChildren children (fun _ => true)
    (fun token => token.lexeme == "do" || token.lexeme == "by")
    fun tree =>
      match tree with
      | .node (.raw kind) children =>
          if kind == `Lean.Parser.Term.do
              || kind == `Lean.Parser.Term.doNested
              || kind == `Lean.Parser.Term.byTactic then
            (singleContentChild? children).getD tree
          else
            tree
      | _ => tree

private partial def attachedIntroducerBody? : Tree → Option Tree
  | .node (.raw kind) children =>
      if kind == `Lean.Parser.Term.do
          || kind == `Lean.Parser.Term.doNested
          || kind == `Lean.Parser.Term.byTactic
          || kind == `Lean.Parser.Term.byTactic' then
        singleContentChild? children
      else
        singleContentChild? children >>= attachedIntroducerBody?
  | _ => none

private def regroupAttachedBodyOwner? (kind : SyntaxNodeKind) (children : Array Tree)
    : Option Tree := do
  let grouped := regroupMatchAltBodySuffix children
  if grouped == children then
    none
  let bodyIndex ←
    ((List.range grouped.size).filter
      fun index => grouped[index]?.bind Tree.firstToken? |>.isSome).getLast?
  let wrappedBody ← grouped[bodyIndex]?
  let body := (attachedIntroducerBody? wrappedBody).getD wrappedBody
  let header := .node (.raw kind) (grouped.set! bodyIndex .missing)
  some <| .node .parserOwnedBody #[header, body]

def regroupInitialize? (children : Array Tree) : Option Tree := do
  let modifiers ← children[0]?
  let keyword ← children[1]?
  let .node (.raw `null) headerAndAssignment ← children[2]? | none
  let body ← children[3]?
  let body := (attachedDoTree? body).getD body
  let assignmentIndex ←
    headerAndAssignment.findIdx?
      fun child => child.firstToken?.any fun token => token.lexeme == "←"
  if assignmentIndex == 0 then
    none
  let assignment ← headerAndAssignment[assignmentIndex]?
  let header :=
    .node .declarationHeader (childrenRange headerAndAssignment 0 assignmentIndex)
  let definition := .node .definition #[keyword, header, assignment, body]
  some
  <| .node (.raw `Lean.Parser.Command.initialize)
      (#[modifiers, definition] ++ childrenRange children 4 children.size)

partial def isDocCommentContainer : Tree → Bool
  | .node (.raw `Lean.Parser.Command.docComment) _ => true
  | .node kind children =>
      if kind == .raw `null || kind == .raw `Lean.Parser.Command.declModifiers then
        let presentChildren := children.filter fun child => child.firstToken?.isSome
        !presentChildren.isEmpty && presentChildren.all isDocCommentContainer
      else
        false
  | _ => false

def regroupLetRecDeclAnnotations (children : Array Tree) : Option (Array Tree) := do
  let annotationsIndex ←
    (children.findIdx?
      fun child => child.firstToken?.map (fun token => token.lexeme) == some "@[")
    |>.orElse fun _ => children.findIdx? isDocCommentContainer
  let declarationIndex ←
    children.findIdx?
      fun child =>
        rawKind? child == some `Lean.Parser.Term.letDecl
  if declarationIndex <= annotationsIndex then
    none
  else
    let annotationsContainer ← children[annotationsIndex]?
    let annotations :=
      match annotationsContainer with
      | .node (.raw `null) wrappedChildren =>
          if wrappedChildren.size == 1 then
            match wrappedChildren[0]? with
            | some annotations => annotations
            | none => annotationsContainer
          else
            annotationsContainer
      | _ => annotationsContainer
    let declaration ← children[declarationIndex]?
    some
    <| (children.set! annotationsIndex
          (.node .annotatedDeclaration #[annotations, declaration])).set!
        declarationIndex .missing

partial def lakeConfigChildren? : Tree → Option (Array Tree)
  | .node (.raw `Lake.DSL.declValWhere) children => some children
  | .node _ children =>
      children.foldl
        (fun found child =>
          match found with
          | some children => some children
          | none => lakeConfigChildren? child)
        none
  | _ => none

def regroupLakeCommandChildren (children : Array Tree) : Array Tree :=
  children.foldl
    (fun regrouped child =>
      if rawKind? child == some `Lake.DSL.optConfig then
        match lakeConfigChildren? child with
        | some configChildren => regrouped ++ configChildren
        | none => regrouped.push child
      else
        regrouped.push child)
    #[]

partial def flattenLakeRequireTree : Tree → Array Tree
  | .missing => #[]
  | tree@(.node (.raw kind) children) =>
      if kind == `null
          || kind == `Lake.DSL.depSpec
          || kind == `Lake.DSL.depName
          || kind == `Lake.DSL.identOrStr
          || kind == `Lake.DSL.fromClause
          || kind == `Lake.DSL.fromSource
          || kind == `Lake.DSL.fromGit then
        children.foldl
          (fun flattened child => flattened ++ flattenLakeRequireTree child) #[]
      else
        #[tree]
  | tree => #[tree]

def regroupLakeRequireChildren (children : Array Tree) : Array Tree :=
  children.foldl (fun flattened child => flattened ++ flattenLakeRequireTree child) #[]

def unwrapSingleNullTree : Tree → Tree
  | tree@(.node (.raw `null) children) =>
      if children.size == 1 then children[0]?.getD tree else tree
  | tree => tree

def splitWhereStructInstTrailingWhereDecls? : Tree → Option (Tree × Tree)
  | .node (.raw `Lean.Parser.Command.whereStructInst) children => do
      let trailingIndex ←
        children.findIdx?
          fun child =>
            rawKind? (unwrapSingleNullTree child) == some `Lean.Parser.Term.whereDecls
      let trailing ← children[trailingIndex]?
      some
        (
          .node (.raw `Lean.Parser.Command.whereStructInst)
            (children.set! trailingIndex .missing),
          unwrapSingleNullTree trailing
        )
  | _ => none

def regroupDefinitionTrailingWhereDecls? (children : Array Tree) : Option (Array Tree) :=
  match children.findIdx?
          fun child =>
            (splitWhereStructInstTrailingWhereDecls? child).isSome with
  | some valueIndex =>
      match children[valueIndex]? >>= splitWhereStructInstTrailingWhereDecls? with
      | some (value, trailing) =>
          some
          <| childrenRange children 0 valueIndex
              ++ #[value, trailing]
              ++ childrenRange children (valueIndex + 1) children.size
      | none => none
  | none => none

def flattenSimpleDeclarationValueChildren? (children : Array Tree)
    : Option (Array Tree) := do
  let valueIndex ←
    children.findIdx?
      fun child =>
        rawKind? (unwrapSingleNullTree child) == some `Lean.Parser.Command.declValSimple
  let value ← children[valueIndex]? |>.map unwrapSingleNullTree
  match value with
  | .node _ valueChildren =>
      some
      <| childrenRange children 0 valueIndex
          ++ valueChildren
          ++ childrenRange children (valueIndex + 1) children.size
  | _ => none

def regroupFlattenedDefinitionChildren (children : Array Tree) : Array Tree :=
  (regroupDefinitionTrailingWhereDecls? children).getD children

def regroupDefinitionChildren (children : Array Tree) : Option (Array Tree) :=
  match flattenSimpleDeclarationValueChildren? children with
  | some flattened =>
      some <| regroupFlattenedDefinitionChildren flattened
  | none =>
      match regroupDefinitionTrailingWhereDecls? children with
      | some children => some children
      | none =>
          if children.any
              fun child =>
                rawKind? child == some `Lean.Parser.Command.whereStructInst then
            some children
          else
            none

def splitEquationTrailingClauses? : Tree → Option (Tree × Array Tree)
  | .node (.raw `Lean.Parser.Command.declValEqns) valueChildren => do
      let alternativesIndex ←
        valueChildren.findIdx?
          fun child =>
            rawKind? child == some `Lean.Parser.Term.matchAltsWhereDecls
      let alternatives ← valueChildren[alternativesIndex]?
      match alternatives with
      | .node (.raw `Lean.Parser.Term.matchAltsWhereDecls) children => do
          let clauseIndexes :=
            (List.range children.size).filter
              fun index =>
                match children[index]? with
                | some child =>
                    (rawKind? child == some `Lean.Parser.Termination.suffix
                      && child.firstToken?.isSome)
                    || child.firstToken?.any fun token => token.lexeme == "where"
                | none => false
          let firstClauseIndex ← clauseIndexes.head?
          if !(childrenRange children 0 firstClauseIndex).any
                fun child => child.firstToken?.any fun token => token.lexeme == "|" then
            none
          let clauses :=
            clauseIndexes.foldl
              (fun clauses index =>
                match children[index]? with
                | some child =>
                    clauses.push
                    <|  if child.firstToken?.any fun token => token.lexeme == "where" then
                          unwrapSingleNullTree child
                        else
                          child
                | none => clauses)
              #[]
          let alternatives :=
            .node (.raw `Lean.Parser.Term.matchAltsWhereDecls)
              (children.mapIdx
                fun index child =>
                  if clauseIndexes.contains index then .missing else child)
          let value :=
            .node (.raw `Lean.Parser.Command.declValEqns)
              (valueChildren.set! alternativesIndex alternatives)
          some (value, clauses)
      | _ => none
  | _ => none

def regroupEquationTrailingClauseChildren (children : Array Tree) : Array Tree :=
  match children[3]? >>= splitEquationTrailingClauses? with
  | some (value, clauses) =>
      childrenRange children 0 3
      ++ #[value]
      ++ clauses
      ++ childrenRange children 4 children.size
  | none => children

def declarationValueCommandKind (kind : SyntaxNodeKind) : Bool :=
  kind == `Lean.Parser.Command.theorem || kind == `lemma || kind == `group

def splitLeadingAnnotations? : Tree → Option (Tree × Tree)
  | .node (.raw `Lean.Parser.Command.declModifiers) children => do
      let reverseIndex ←
        children.reverse.findIdx?
          fun child =>
            child.firstToken?.map (fun token => token.lexeme) == some "@["
            || isDocCommentContainer child
      let annotationIndex := children.size - reverseIndex - 1
      let annotation ← children[annotationIndex]?
      let annotationChildren :=
        children.mapIdx
          fun index child =>
            if index < annotationIndex then
              child
            else if index == annotationIndex then
              annotation
            else
              .missing
      let remainingChildren :=
        children.mapIdx
          fun index child =>
            if annotationIndex < index then child else .missing
      some
        (
          .node (.raw `Lean.Parser.Command.declModifiers) annotationChildren,
          .node (.raw `Lean.Parser.Command.declModifiers) remainingChildren
        )
  | _ => none

def splitDeclarationAnnotations? : Tree → Option (Tree × Tree)
  | .node kind children => do
      match children.findIdx?
              fun child =>
                rawKind? child == some `Lean.Parser.Command.declModifiers with
      | some modifierIndex => do
          let modifiers ← children[modifierIndex]?
          let (annotations, remainingModifiers) ← splitLeadingAnnotations? modifiers
          some (annotations, .node kind (children.set! modifierIndex remainingModifiers))
      | none => do
          if kind == .raw `null then
            none
          let annotationIndex ←
            children.findIdx?
              fun child =>
                child.firstToken?.map (fun token => token.lexeme) == some "@["
                && child.lastToken?.map (fun token => token.lexeme) == some "]"
          if (previousContentIndex? children annotationIndex).isSome then
            none
          else
            let annotations ← children[annotationIndex]?
            some (annotations, .node kind (children.set! annotationIndex .missing))
  | _ => none

def splitLeadingDeclarationModifiers? : Tree → Option (Tree × Tree)
  | .node kind children => do
      let modifierIndex ←
        children.findIdx?
          fun child =>
            rawKind? child == some `Lean.Parser.Command.declModifiers
      if (previousContentIndex? children modifierIndex).isSome then
        none
      else
        let modifiers ← children[modifierIndex]?
        if modifiers.firstToken?.isSome then
          some
            (
              modifiers,
              .node kind
                (childrenRange children 0 modifierIndex
                  ++ childrenRange children (modifierIndex + 1) children.size)
            )
        else
          none
  | _ => none

def splitDirectCommandDocComment? : Tree → Option (Tree × Tree)
  | .node kind children => do
      let annotationIndex ←
        children.findIdx?
          fun child =>
            child.firstToken?.isSome
      let annotation ← children[annotationIndex]?
      let firstToken ← annotation.firstToken?
      if isDocCommentContainer annotation
          && (firstToken.lexeme.startsWith "/-" || firstToken.lexeme.startsWith "--") then
        some (annotation, .node kind (children.set! annotationIndex .missing))
      else
        none
  | _ => none

def annotatedDeclarationTree (annotations modifiers declaration : Tree) : Tree :=
  let children :=
    if modifiers.firstToken?.isSome then
      #[annotations, modifiers, declaration]
    else
      #[annotations, declaration]
  .node .annotatedDeclaration children

def annotatedDeclarationTreeForCommand (annotations command : Tree) : Tree :=
  match splitLeadingDeclarationModifiers? command with
  | some (modifiers, command) =>
      annotatedDeclarationTree annotations modifiers command
  | none => annotatedDeclarationTree annotations .missing command

def regroupStructCtor (children : Array Tree) : Tree :=
  let command := .node (.raw `Lean.Parser.Command.structCtor) (children.set! 0 .missing)
  match children[0]? with
  | some modifiers =>
      match splitLeadingAnnotations? modifiers with
      | some (annotations, remainingModifiers) =>
          annotatedDeclarationTree annotations remainingModifiers command
      | none =>
          if modifiers.firstToken?.isSome then
            .node .annotatedDeclaration #[modifiers, command]
          else
            command
  | none => command

def regroupCtor (children : Array Tree) : Tree :=
  match children[2]? with
  | some modifiers =>
      match splitLeadingAnnotations? modifiers with
      | some (annotations, remainingModifiers) =>
          let command :=
            .node (.raw `Lean.Parser.Command.ctor)
            <| ((children.set! 0 .missing).set! 1 .missing).set! 2 .missing
          .node (.raw `Lean.Parser.Command.ctor)
          <| childrenRange children 0 2
              ++ #[annotatedDeclarationTree annotations remainingModifiers command]
      | none =>
          .node (.raw `Lean.Parser.Command.ctor) children
  | none =>
      .node (.raw `Lean.Parser.Command.ctor) children

def regroupStructure (children : Array Tree) : Tree :=
  let trailingDeriving :=
    match children[5]? with
    | some clause =>
        if clause.firstToken?.isSome then
          #[.node .structureDeriving #[clause]]
        else
          #[]
    | none => #[]
  match children[4]? with
  | some (Tree.node (.raw `null) whereChildren) =>
      match whereChildren[0]? with
      | some whereKeyword =>
          let header :=
            .node .structureHeader (childrenRange children 0 4 ++ #[whereKeyword])
          let constructor :=
            match whereChildren[1]? with
            | some (Tree.node (.raw `null) declarations) =>
                if declarations.any fun child => child.firstToken?.isSome then
                  #[.node .structureConstructor declarations]
                else
                  #[]
            | some declaration =>
                if declaration.firstToken?.isSome then
                  #[.node .structureConstructor #[declaration]]
                else
                  #[]
            | none => #[]
          let fields :=
            match whereChildren[2]? with
            | some fields =>
                if fields.firstToken?.isSome then #[fields] else #[]
            | none => #[]
          .node (.raw `Lean.Parser.Command.structure)
          <| #[header]
              ++ constructor
              ++ fields
              ++ childrenRange whereChildren 3 whereChildren.size
              ++ trailingDeriving
              ++ childrenRange children 6 children.size
      | none =>
          .node (.raw `Lean.Parser.Command.structure)
          <| #[.node .structureHeader (childrenRange children 0 4)]
              ++ trailingDeriving
              ++ childrenRange children 6 children.size
  | _ => .node (.raw `Lean.Parser.Command.structure) children

def regroupDeclarationValueCommand (kind : SyntaxNodeKind) (children : Array Tree)
    : Tree :=
  let children := regroupEquationTrailingClauseChildren children
  let command :=
    match regroupDefinitionChildren children with
    | some declarationChildren =>
        if kind == `group then
          .node .definition declarationChildren
        else
          .node (.raw kind) declarationChildren
    | none => .node (.raw kind) children
  match splitDeclarationAnnotations? command with
  | some (annotations, command) =>
      annotatedDeclarationTreeForCommand annotations command
  | none => command

def regroupDeclarationChildren (children : Array Tree) : Option (Array Tree) := do
  let modifiers ← children[0]?
  let declaration ← children[1]?
  let annotatedDeclaration? : Option Tree :=
    match splitLeadingAnnotations? modifiers with
    | some (annotations, remainingModifiers) =>
        some <| annotatedDeclarationTree annotations remainingModifiers declaration
    | none =>
        match splitDeclarationAnnotations? declaration with
        | some (annotations, declaration) =>
            some <| annotatedDeclarationTree annotations modifiers declaration
        | none =>
            if (Tree.firstToken? modifiers).isSome then
              some <| Tree.node .annotatedDeclaration #[modifiers, declaration]
            else
              none
  annotatedDeclaration?.map
    fun annotatedDeclaration =>
      #[annotatedDeclaration] ++ childrenRange children 2 children.size

partial def structureUpdateSourceChildren : Tree → Array Tree
  | .node (.raw `null) children =>
      children.foldl
        (fun flattened child => flattened ++ structureUpdateSourceChildren child) #[]
  | tree => #[tree]

def regroupStructureUpdateSource (tree : Tree) : Tree :=
  .node .structureUpdate (structureUpdateSourceChildren tree)

def regroupStructInstChildren (children : Array Tree) : Array Tree :=
  match children[1]? with
  | some source =>
      if source.lastToken?.map (·.lexeme) == some "with" then
        children.set! 1 (regroupStructureUpdateSource source)
      else
        children
  | none => children

def regroupRegisterLinterSetChildren (children : Array Tree) : Array Tree :=
  match (children[4]? : Option Tree) with
  | some (.node (.raw `null) items) =>
      childrenRange children 0 4 ++ items ++ childrenRange children 5 children.size
  | _ => children

def regroupDoFallbackChildren? (children : Array Tree) : Option (Array Tree) := do
  let pipeIndex ←
    children.findIdx?
      fun child => child.firstToken?.map (fun token => token.lexeme) == some "|"
  let fallbackIndex ←
    (List.range' (pipeIndex + 1) (children.size - pipeIndex - 1)).find?
      fun index => children[index]?.any fun child => child.firstToken?.isSome
  let pipe ← children[pipeIndex]?
  let fallback ← children[fallbackIndex]?
  let clause := .node .doFallbackClause #[pipe, fallback]
  let continuationChildren := childrenRange children (fallbackIndex + 1) children.size
  let continuation :=
    if continuationChildren.isEmpty then
      #[]
    else
      #[.node .doFallbackContinuation continuationChildren]
  some <| childrenRange children 0 pipeIndex ++ #[clause] ++ continuation

def regroupDoDeclarationFallbackChildren (children : Array Tree) : Array Tree :=
  children.foldl
    (fun regrouped child =>
      match child with
      | .node (.raw `null) fallbackChildren =>
          match regroupDoFallbackChildren? fallbackChildren with
          | some grouped => regrouped ++ grouped
          | none => regrouped.push child
      | _ => regrouped.push child)
    #[]

def isIfThenElseKind (kind : SyntaxNodeKind) : Bool :=
  kind == `termIfThenElse || kind == `termDepIfThenElse || kind == `boolIfThenElse

def ifThenElseClause (children : Array Tree) : Tree :=
  if children.size < 2 then
    .node .ifThenElseClause children
  else
    let conditionIndex := children.size - 2
    let condition := children[conditionIndex]!
    let thenKeyword := children[conditionIndex + 1]!
    .node .ifThenElseClause
    <| (childrenRange children 0 conditionIndex).push
    <| .node .suffixGroup #[condition, thenKeyword]

def attachIfThenElseClauseBody (accepts : Tree → Bool) (clause body : Tree)
    : Tree × Tree :=
  if !accepts body then
    (clause, body)
  else
    match clause with
    | .node .ifThenElseClause children =>
        let suffixIndex := children.size - 1
        match children[suffixIndex]? with
        | some (.node .suffixGroup suffixChildren) =>
            (
              .node .ifThenElseClause
                (children.set! suffixIndex
                  <| .node .suffixGroup (suffixChildren.push body)),
              .missing
            )
        | _ => (clause, body)
    | _ => (clause, body)

def termIfAttachedBody (body : Tree) : Bool :=
  treeStartsAttachedBody body

def doIfAttachedBody (body : Tree) : Bool :=
  body.firstToken?.any (·.lexeme == "do")

def ifThenElseChainParts? : Tree → Option (Array Tree)
  | .node (.raw kind) children => do
      if !isIfThenElseKind kind || children.size != 6 then
        none
      let thenBranch ← children[3]?
      let elseKeyword ← children[4]?
      let elseBranch ← children[5]?
      let (clause, thenBranch) :=
        attachIfThenElseClauseBody termIfAttachedBody
          (ifThenElseClause (childrenRange children 0 3)) thenBranch
      some
        #[
          clause,
          thenBranch,
          elseKeyword,
          elseBranch
        ]
  | .node (.ifThenElseChain _) children => some children
  | _ => none

def prependElseToIfThenElseClause (elseKeyword : Tree) (parts : Array Tree)
    : Option (Array Tree) := do
  let first ← parts[0]?
  match first with
  | .node .ifThenElseClause children =>
      some <| parts.set! 0 (.node .ifThenElseClause (#[elseKeyword] ++ children))
  | _ => none

def attachFinalElseBodySuffixWhere (accepts : Tree → Bool) (parts : Array Tree)
    : Array Tree :=
  if parts.size < 2 then
    parts
  else
    match parts[parts.size - 2]?, parts.back? with
    | some delimiter, some body =>
        if (directLeafAtomToken? delimiter).any (·.lexeme == "else") && accepts body then
          parts.extract 0 (parts.size - 2) |>.push (.node .suffixGroup #[delimiter, body])
        else
          parts
    | _, _ => parts

def regroupIfThenElseChain (kind : SyntaxNodeKind) (children : Array Tree) : Tree :=
  if children.size != 6 then
    .node (.raw kind) children
  else
    let thenBranch := children[3]!
    let elseKeyword := children[4]!
    let elseBranch := children[5]!
    let continuation? := do
      let continuation ← ifThenElseChainParts? elseBranch
      prependElseToIfThenElseClause elseKeyword continuation
    match continuation? with
    | some continuation =>
        let (clause, thenBranch) :=
          attachIfThenElseClauseBody termIfAttachedBody
            (ifThenElseClause (childrenRange children 0 3)) thenBranch
        let parts := #[clause, thenBranch] ++ continuation
        .node (.ifThenElseChain kind)
          (attachFinalElseBodySuffixWhere termIfAttachedBody parts)
    | none => .node (.raw kind) children

private partial def doIfContinuationParts? : Tree → Option (Array Tree)
  | .node (.raw `null) children =>
      let children := children.filter fun child => child.firstToken?.isSome
      let rec loop : List Tree → Option (Array Tree)
        | [] => some #[]
        | [elseKeyword, body] =>
            if (directLeafAtomToken? elseKeyword).any (·.lexeme == "else") then
              some #[elseKeyword, (attachedDoTree? body).getD body]
            else
              none
        | child :: rest => do
            let childParts ← doIfContinuationParts? child
            let restParts ← loop rest
            some <| childParts ++ restParts
      loop children.toList
  | .node (.raw `group) children =>
      match children.toList with
      | [elseKeyword, ifKeyword] =>
          if elseKeyword.firstToken?.any (·.lexeme == "else")
              && ifKeyword.firstToken?.any (·.lexeme == "if") then
            some #[elseKeyword, ifKeyword]
          else
            none
      | _ => do
          let prefixParts ← children[0]? >>= doIfContinuationParts?
          let children := prefixParts ++ childrenRange children 1 children.size
          if children.size != 5
              || !children[0]!.firstToken?.any (·.lexeme == "else")
              || !children[1]!.firstToken?.any (·.lexeme == "if")
              || !children[3]!.firstToken?.any (·.lexeme == "then") then
            none
          else
            let body := (attachedDoTree? children[4]!).getD children[4]!
            let (clause, body) :=
              attachIfThenElseClauseBody doIfAttachedBody
                (ifThenElseClause (childrenRange children 0 4)) body
            some #[clause, body]
  | _ => none

def regroupDoIfThenElseChain? (children : Array Tree) : Option Tree := do
  if children.size < 4 then
    none
  let thenBranch ← children[3]?
  let thenBranch := (attachedDoTree? thenBranch).getD thenBranch
  let (clause, thenBranch) :=
    attachIfThenElseClauseBody doIfAttachedBody
      (ifThenElseClause (childrenRange children 0 3)) thenBranch
  let initial := #[clause, thenBranch]
  let rec loop (parts : Array Tree) (index : Nat) : Option (Array Tree) := do
    if children.size <= index then
      some parts
    else
      let child ← children[index]?
      if child.firstToken?.isNone then
        loop parts (index + 1)
      else
        let continuation ← doIfContinuationParts? child
        loop (parts ++ continuation) (index + 1)
  let parts ← loop initial 4
  let hasContinuationClause :=
    match parts[2]? with
    | some (.node .ifThenElseClause _) => true
    | _ => false
  if !hasContinuationClause then
    none
  else
    some
    <| .node (.ifThenElseChain `Lean.Parser.Term.doIf)
    <| attachFinalElseBodySuffixWhere doIfAttachedBody parts

def proofBodyTree (children : Array Tree) : Tree :=
  .node (.proofBody <| children.any Tree.containsTacticLayoutOwner) children

partial def startsWithParserOwnedBody : Tree → Bool
  | .node .parserOwnedBody _ => true
  | .node _ children =>
      match children.find? fun child => child.firstToken?.isSome with
      | some child => startsWithParserOwnedBody child
      | none => false
  | _ => false

def regroupByTacticChildren (children : Array Tree) : Array Tree :=
  match children[0]? with
  | some byKeyword =>
      let bodyChildren := childrenRange children 1 children.size
      let body := proofBodyTree bodyChildren
      let parserOwnedBodyIsDetached :=
        startsWithParserOwnedBody (.node (.raw `null) bodyChildren)
        && match byKeyword.lastToken?, body.firstToken? with
            | some introducer, some firstBodyToken =>
                introducer.trailing.text.contains '\n'
                || firstBodyToken.leading.text.contains '\n'
            | _, _ => false
      let body :=
        match body with
        | .node (.proofBody containsOwner) children =>
            .node (.proofBody <| containsOwner || parserOwnedBodyIsDetached) children
        | tree => tree
      #[byKeyword, body]
  | none => children

def regroupDecreasingByChildren (children : Array Tree) : Array Tree :=
  match children[0]? with
  | some decreasingByKeyword =>
      #[decreasingByKeyword, proofBodyTree <| childrenRange children 1 children.size]
  | none => children

def regroupTerminationByParameters (parameters arrow : Tree) : Tree :=
  match parameters with
  | .node (.raw `null) parameterChildren =>
      match parameterChildren.back? with
      | some finalParameter =>
          .node .signatureParameters
          <| childrenRange parameterChildren 0 (parameterChildren.size - 1)
              ++ #[.node (.raw `null) #[finalParameter, arrow]]
      | none => .node .signatureParameters #[arrow]
  | _ =>
      .node .signatureParameters #[.node (.raw `null) #[parameters, arrow]]

def regroupTerminationByChildren (children : Array Tree) : Array Tree :=
  match
      children.findIdx?
        fun child =>
          match child with
          | .node (.raw `null) parts =>
              parts.size == 2
              && parts[1]?.any
                  fun arrow => arrow.firstToken?.any fun token => token.lexeme == "=>"
          | _ => false
  with
  | some parameterArrowIndex =>
      match children[parameterArrowIndex]? with
      | some (.node (.raw `null) parameterArrowParts) =>
          match parameterArrowParts[0]?, parameterArrowParts[1]? with
          | some parameters, some arrow =>
              childrenRange children 0 parameterArrowIndex
              ++ #[regroupTerminationByParameters parameters arrow]
              ++ childrenRange children (parameterArrowIndex + 1) children.size
          | _, _ => children
      | _ => children
  | none => children

def regroupTerminationSuffixChildren (children : Array Tree) : Array Tree :=
  children.foldl
    (fun clauses child =>
      let clause := unwrapSingleNullTree child
      if clause.firstToken?.isSome then clauses.push clause else clauses)
    #[]

def regroupWhereFinallyChildren (children : Array Tree) : Array Tree :=
  match children[1]? with
  | some tacticBody =>
      children.set! 1 <| proofBodyTree #[tacticBody]
  | none => children

def regroupWhereDeclsChildren (children : Array Tree) : Array Tree :=
  match children[0]?, children[1]?, children[2]? with
  | some whereKeyword,
    some (Tree.node (.raw `null) declarations),
    some (Tree.node (.raw `null) finallyWrapper) =>
      let finallyChildren :=
        match finallyWrapper[0]? with
        | some (Tree.node (.raw `Lean.Parser.Term.whereFinally) children) =>
            if finallyWrapper.size == 1 then children else finallyWrapper
        | _ => finallyWrapper
      #[whereKeyword] ++ declarations ++ finallyChildren
  | _, _, _ => children

def regroupCommandInWrapperChildren (children : Array Tree) : Array Tree :=
  match children[1]? with
  | some (Tree.node (.raw `null) wrapped) =>
      match wrapped[0]? with
      | some first =>
          if first.firstToken?.any (·.lexeme == "in") then
            childrenRange children 0 1
            ++ wrapped
            ++ childrenRange children 2 children.size
          else
            children
      | none => children
  | _ => children

def regroupBinderTacticChildren (children : Array Tree) : Array Tree :=
  match children[0]?, children[1]? with
  | some assignment, some byKeyword =>
      #[assignment, byKeyword, proofBodyTree <| childrenRange children 2 children.size]
  | _, _ => children

def regroupAttachedDoRhs (children : Array Tree) : Array Tree :=
  match children[3]? >>= attachedDoTree? with
  | some body => children.set! 3 body
  | none => children

def regroupDerivingClause? (children : Array Tree) : Option Tree := do
  let keyword ← children[0]?
  if keyword.firstToken?.map (·.lexeme) != some "deriving" then
    none
  let classes ← children[1]?
  match classes with
  | .node (.raw `null) classChildren =>
      some <| .node .derivingClause (#[keyword] ++ classChildren)
  | _ => none

def regroupDerivingCommandChildren (children : Array Tree) : Array Tree :=
  match (children[3]? : Option Tree) with
  | some (.node (.raw `null) classChildren) =>
      children.set! 3 (.node .derivingClause classChildren)
  | _ => children

def isDelimitedCollectionKind (kind : SyntaxNodeKind) : Bool :=
  kind == `Lean.Parser.Term.tuple
  || kind == `Lean.Parser.Term.anonymousCtor
  || kind == `«term{_}»
  || kind == `«term[_]»
  || kind == `«term#[_,]»
  || kind == `Matrix.vecNotation
  || kind == `Matrix.matrixNotation

partial def flattenDelimitedCollectionChildren (children : Array Tree) : Array Tree :=
  match children.findIdx? fun child => rawKind? child == some `null with
  | some index =>
      match children[index]? with
      | some (.node (.raw `null) items) =>
          let hasSeparator :=
            items.any
              fun item =>
                item.firstToken?.any
                  fun token =>
                    token.lexeme == "," || token.lexeme == ";"
          if hasSeparator then
            flattenDelimitedCollectionChildren
            <| childrenRange children 0 index
                ++ items
                ++ childrenRange children (index + 1) children.size
          else
            children
      | _ => children
  | none => children

private def isDelimitedSequenceKind : NodeKind → Bool
  | .raw kind | .tactic kind _ _ _ _ =>
      kind == `Lean.Parser.Tactic.tacticSeqBracketed
      || kind == `Lean.Parser.Term.doSeqBracketed
  | _ => false

private partial def splitLeadingDelimitedSequenceOpener? : Tree → Option (Tree × Tree)
  | .node kind children =>
      let contentIndexes :=
        (List.range children.size).filter
          fun index => children[index]?.bind Tree.firstToken? |>.isSome
      if isDelimitedSequenceKind kind then do
        let openerIndex ← contentIndexes.head?
        let opener ← children[openerIndex]?
        if opener.singleToken?.isSome then
          some (opener, .node kind (children.set! openerIndex .missing))
        else
          none
      else
        match contentIndexes with
        | [childIndex] => do
            let child ← children[childIndex]?
            let (opener, child) ← splitLeadingDelimitedSequenceOpener? child
            some (opener, .node kind (children.set! childIndex child))
        | _ => none
  | _ => none

private def splitCalcAttachedProof? : Tree → Option (Tree × Tree)
  | .node (.raw kind) #[keyword, body] =>
      if kind == `Lean.Parser.Term.byTactic
          || kind == `Lean.Parser.Term.do
          || kind == `Lean.calc then
        match splitLeadingDelimitedSequenceOpener? body with
        | some (opener, body) => some (.node .suffixGroup #[keyword, opener], body)
        | none => some (keyword, body)
      else
        none
  | _ => none

private def regroupCalcStep? (children : Array Tree) : Option Tree := do
  let relation ← children[0]?
  let assignmentChildren :=
    match children[1]? with
    | some (Tree.node (NodeKind.raw `null) assignmentChildren) =>
        assignmentChildren ++ childrenRange children 2 children.size
    | _ => childrenRange children 1 children.size
  let assignmentIndex ←
    assignmentChildren.findIdx?
      fun child => child.firstToken?.any fun token => token.lexeme == ":="
  let assignment := childrenRange assignmentChildren 0 (assignmentIndex + 1)
  let proof :=
    childrenRange assignmentChildren (assignmentIndex + 1) assignmentChildren.size
  if !(proof.any fun child => child.firstToken?.isSome) then
    none
  else
    match proof with
    | #[proof] =>
        match splitCalcAttachedProof? proof with
        | some (suffix, body) =>
            some
            <| .node .calcStep
            <| #[.node .suffixGroup (#[relation] ++ assignment ++ #[suffix]), body]
        | none =>
            some
            <| .node .calcStep
            <| #[.node .suffixGroup (#[relation] ++ assignment), proof]
    | _ =>
        some
        <| .node .calcStep
        <| #[.node .suffixGroup (#[relation] ++ assignment), .node (.raw `null) proof]

private def regroupCalcBodyChildren (children : Array Tree) : Array Tree :=
  children.foldl
    (fun steps child =>
      match child with
      | Tree.node (NodeKind.raw `null) nested => steps ++ nested
      | _ => steps.push child)
    #[]

private def regroupCalcChildren (children : Array Tree) : Array Tree :=
  match children with
  | #[keyword, Tree.node .calcBody steps] =>
      match steps[0]? with
      | some (Tree.node (NodeKind.raw `Lean.calcFirstStep) initialChildren) =>
          let initial := Tree.node (NodeKind.raw `Lean.calcFirstStep) initialChildren
          #[
            .node .suffixGroup #[keyword, initial],
            .node .calcBody (childrenRange steps 1 steps.size)
          ]
      | _ => children
  | _ => children

private def regroupCalcOwnerTree : Tree → Tree
  | .node kind children => .node kind (regroupCalcChildren children)
  | tree => tree

def regroupOtherRawNode (kind : SyntaxNodeKind) (children : Array Tree) : Tree :=
  if kind == `Lean.Parser.Command.deriving then
    .node (.raw kind) (regroupDerivingCommandChildren children)
  else if kind == `Lean.Parser.Command.declaration then
    match regroupDeclarationChildren children with
    | some declarationChildren => .node (.raw kind) declarationChildren
    | none => .node (.raw kind) children
  else if kind == `Lean.Parser.Term.doCatch || kind == `Lean.Parser.Term.doCatchMatch then
    (regroupAttachedBodyOwner? kind children).getD <| .node (.raw kind) children
  else if kind == `Lean.Parser.Term.doIdDecl || kind == `Lean.Parser.Term.doPatDecl then
    .node (.raw kind)
    <| regroupDoDeclarationFallbackChildren
    <| regroupRightmostSuffixChildren children
        fun tree => if treeStartsAttachedBody tree then some tree else none
  else if kind == `Lean.Parser.Term.doLetElse || kind == `Lean.Parser.Term.doLetExpr then
    match regroupDoFallbackChildren? children with
    | some grouped => .node (.raw kind) grouped
    | none => .node (.raw kind) children
  else if kind == `Lean.Parser.Term.structInst then
    .node (.raw kind) (regroupStructInstChildren children)
  else if kind == `Lean.Parser.Command.optDeclSig
          || kind == `Lean.Parser.Command.declSig then
    match children[0]?, children[1]? with
    | some parameters, some typeSpec =>
        .node (.raw kind) #[regroupSignatureParameters parameters, typeSpec]
    | _, _ =>
        .node (.raw kind) children
  else if kind == `Lean.Parser.Command.declId then
    .node (.raw kind) (regroupDeclarationIdentifierChildren children)
  else if kind == `Lean.Parser.Command.structCtor then
    regroupStructCtor children
  else if kind == `Lean.Parser.Command.ctor then
    regroupCtor children
  else if kind == `Lean.Parser.Command.structure then
    regroupStructure children
  else if kind == `Lean.calcSteps then
    .node .calcBody (regroupCalcBodyChildren children)
  else if kind == `Lean.calcFirstStep then
    (regroupCalcStep? children).getD <| .node (.raw kind) children
  else if kind == `Lean.calc then
    .node (.raw kind) (regroupCalcChildren children)
  else if kind == `Lean.Parser.Term.fun
          && children.any
              fun child => rawKind? child == some `Lean.Parser.Term.matchAlts then
    .node .patternLambda children
  else if kind == `Lean.Parser.Term.basicFun then
    match children[0]? with
    | some parameters =>
        .node (.raw kind)
        <| regroupAttachedBodyIntroducerChildren
        <| children.set! 0 (regroupSignatureParameters parameters)
    | none =>
        .node (.raw kind) (regroupAttachedBodyIntroducerChildren children)
  else if kind == `Lean.«command__Unif_hint____Where_|_-⊢__» then
    .node (.raw kind) (regroupUnifHintChildren children)
  else if kind == `Lean.Parser.Term.letEqnsDecl then
    match regroupDeclarationHeader children with
    | some children => .node (.raw kind) children
    | none => .node (.raw kind) children
  else if kind == `Lean.Parser.Term.letIdDecl then
    match regroupDeclarationHeader children with
    | some children => .node (.raw kind) children
    | none => .node (.raw kind) children
  else if kind == `Lean.Parser.Term.letRecDecl then
    match regroupLetRecDeclAnnotations children with
    | some children => .node (.raw kind) children
    | none => .node (.raw kind) children
  else if kind == `Lean.Parser.Term.matchAlt then
    let children := regroupMatchAltBodySuffix (regroupAttachedDoRhs children)
    match children[1]? with
    | some patterns =>
        .node (.raw kind) <| children.set! 1 (regroupMatchPatterns patterns)
    | none => .node (.raw kind) children
  else if kind == `Lean.Parser.Term.matchExprAlt
          || kind == `Lean.Parser.Term.matchExprElseAlt then
    .node (.raw kind) (regroupAttachedDoRhs children)
  else if kind == `Lean.Parser.Term.doIf then
    let children := regroupAttachedDoRhs children
    (regroupDoIfThenElseChain? children).getD
    <| .node (.raw kind) (children.map regroupDoIfElseBodySuffix)
  else if kind == `Lean.Parser.Term.structInstField then
    match children[0]?, children[1]? >>= structInstFieldParts? with
    | some lvalue, some fieldParts =>
        let fieldParts :=
          match fieldParts[0]? with
          | some parameters =>
              fieldParts.set! 0 (regroupSignatureParameters parameters)
          | none => fieldParts
        let fieldParts := regroupOptionalPrivateValue fieldParts
        .node (.raw kind)
        <| regroupRightmostSuffixChildren (#[lvalue] ++ fieldParts)
            fun tree => if treeStartsAttachedBody tree then some tree else none
    | _, _ => .node (.raw kind) children
  else if kind == `Lean.Parser.Term.match
          || kind == `Lean.Parser.Term.doMatch
          || kind == `Lean.Parser.Tactic.match then
    .node (.raw kind) (regroupMatchDiscriminantsBeforeWith children)
  else if kind == `Lean.Parser.Term.matchAlts then
    .node (.raw kind) (unwrapSingleNullChild children)
  else if kind == `Lean.Parser.Term.doFor then
    match regroupDoForChildren children with
    | some children => .node (.raw kind) children
    | none => .node (.raw kind) children
  else if kind == `Lean.Parser.Term.byTactic || kind == `Lean.Parser.Term.byTactic' then
    .node (.raw kind) (regroupByTacticChildren children)
  else if kind == `Lean.Parser.Termination.decreasingBy then
    .node (.raw kind) (regroupDecreasingByChildren children)
  else if kind == `Lean.Parser.Termination.terminationBy then
    .node (.raw kind) (regroupTerminationByChildren children)
  else if kind == `Lean.Parser.Termination.suffix then
    .node (.raw kind) (regroupTerminationSuffixChildren children)
  else if kind == `Lean.Parser.Term.whereFinally then
    .node (.raw kind) (regroupWhereFinallyChildren children)
  else if kind == `Lean.Parser.Term.whereDecls then
    .node (.raw kind) (regroupWhereDeclsChildren children)
  else if kind == `Lean.Parser.Command.declModifiers then
    .node (.raw kind) children
  else if isGeneratedTermKind kind then
    .node (.raw kind) (regroupGeneratedTightPieces children)
  else
    let tree := .node (.raw kind) children
    let documentedCommand? :=
      if isGeneratedCommandKind kind then splitDirectCommandDocComment? tree else none
    match documentedCommand? with
    | some (annotations, command) =>
        annotatedDeclarationTreeForCommand annotations command
    | none =>
        match splitDeclarationAnnotations? tree with
        | some (annotations, command) =>
            annotatedDeclarationTreeForCommand annotations command
        | none =>
            match splitLeadingDeclarationModifiers? tree with
            | some (modifiers, command) =>
                .node .annotatedDeclaration #[modifiers, command]
            | none => tree

private def nodeKindHasRawKind (expected : SyntaxNodeKind) : NodeKind → Bool
  | .raw kind | .tactic kind _ _ _ _ => kind == expected
  | _ => false

private partial def treeIsCasesAlternativeGroup : Tree → Bool
  | .node kind children =>
      if nodeKindHasRawKind `Lean.Parser.Tactic.inductionAlt kind then
        true
      else
        match kind with
        | .raw `null =>
            let content := children.filter fun child => child.firstToken?.isSome
            !content.isEmpty && content.all treeIsCasesAlternativeGroup
        | _ => false
  | _ => false

private partial def casesTargetGroupContainsNamedDiscriminant : Tree → Bool
  | .node .namedDiscriminant _ => true
  | .node (.raw `null) children =>
      children.any casesTargetGroupContainsNamedDiscriminant
  | _ => false

def splitDefaultTacticAlternative? (alternatives : Tree) : Option (Tree × Tree) := do
  let .node kind children := unwrapSingleNullTree alternatives | none
  if !nodeKindHasRawKind `Lean.Parser.Tactic.inductionAlts kind then
    none
  else
    let contentIndexes :=
      (List.range children.size).filter
        fun index => children[index]?.any fun child => child.firstToken?.isSome
    let defaultIndex ← contentIndexes.head?
    let defaultAlternative ← children[defaultIndex]?
    if treeIsCasesAlternativeGroup defaultAlternative then
      none
    else
      let explicitAlternatives := .node kind (children.set! defaultIndex .missing)
      let defaultBody :=
        .node (.proofBody defaultAlternative.containsTacticLayoutOwner)
          #[defaultAlternative]
      some (defaultBody, explicitAlternatives)

def regroupCasesChildren (children : Array Tree) : Option (Array Tree) := do
  let alternativesIndex ←
    children.findIdx?
      fun child =>
        child.firstToken?.any fun token => token.lexeme == "with"
  let suffixIndex ← previousContentIndex? children alternativesIndex
  let headerContent := childrenRange children 0 alternativesIndex
  let headerContentIndexes :=
    (List.range headerContent.size).filter
      fun index => headerContent[index]?.any fun child => child.firstToken?.isSome
  let targetIndex ← headerContentIndexes[1]?
  let target ← headerContent[targetIndex]?
  let targetIsNamed := casesTargetGroupContainsNamedDiscriminant target
  let targetGroup :=
    match target with
    | .node (.raw `null) targetChildren =>
        .node (.tacticEliminationTargets targetIsNamed) targetChildren
    | _ => .node (.tacticEliminationTargets targetIsNamed) #[target]
  let children := children.set! targetIndex targetGroup
  let suffix ← children[suffixIndex]?
  let alternatives ← children[alternativesIndex]?
  let (withKeyword, alternatives) ← Tree.extractLeadingLexeme? "with" alternatives
  let suffix := .node .suffixGroup #[suffix, withKeyword]
  let children := children.set! suffixIndex suffix
  let headerChildren := childrenRange children 0 alternativesIndex
  let trailingChildren := childrenRange children (alternativesIndex + 1) children.size
  match splitDefaultTacticAlternative? alternatives with
  | some (defaultAlternative, explicitAlternatives) =>
      let header :=
        .node (.tacticEliminationHeader targetIsNamed)
          (headerChildren.push defaultAlternative)
      some <| #[header, explicitAlternatives] ++ trailingChildren
  | none =>
      let header := .node (.tacticEliminationHeader targetIsNamed) headerChildren
      some <| #[header, alternatives] ++ trailingChildren

def regroupTacticIdentifierClause? (tree : Tree) : Option Tree := do
  let .node (.raw `null) children := tree | none
  let keyword ← children[0]?
  let identifierContainer ← children[1]?
  let .node (.raw `null) identifiers := identifierContainer | none
  let identifiers := identifiers.filter fun identifier => identifier.firstToken?.isSome
  let first ← identifiers[0]?
  let first := .node .suffixGroup #[keyword, first]
  let children := identifiers.set! 0 first
  some <| .node .tacticIdentifierClause <| children

def regroupInductionChildren (children : Array Tree) : Option (Array Tree) := do
  let alternativesIndex ←
    children.findIdx?
      fun child =>
        match unwrapSingleNullTree child with
        | .node (.raw `Lean.Parser.Tactic.inductionAlts) _ => true
        | .node (.tactic `Lean.Parser.Tactic.inductionAlts _ _ _ _) _ => true
        | _ => false
  let alternatives ← children[alternativesIndex]?
  let (withKeyword, alternatives) ← Tree.extractLeadingLexeme? "with" alternatives
  let headerChildren :=
    childrenRange children 0 alternativesIndex
    |>.map
        fun child =>
          if child.firstToken?.any fun token => token.lexeme == "generalizing" then
            (regroupTacticIdentifierClause? child).getD child
          else
            child
  let suffixIndex ← previousContentIndex? headerChildren headerChildren.size
  let suffix ← headerChildren[suffixIndex]?
  let suffix :=
    match suffix with
    | .node .tacticIdentifierClause identifiers =>
        match previousContentIndex? identifiers identifiers.size with
        | some identifierIndex =>
            match identifiers[identifierIndex]? with
            | some identifier =>
                .node .tacticIdentifierClause
                  (identifiers.set! identifierIndex
                    <| .node .suffixGroup #[identifier, withKeyword])
            | none => .node .suffixGroup #[suffix, withKeyword]
        | none => .node .suffixGroup #[suffix, withKeyword]
    | _ => .node .suffixGroup #[suffix, withKeyword]
  let headerChildren := headerChildren.set! suffixIndex suffix
  let header := .node (.tacticEliminationHeader false) headerChildren
  let trailingChildren := childrenRange children (alternativesIndex + 1) children.size
  let bodyChildren :=
    match splitDefaultTacticAlternative? alternatives with
    | some (defaultAlternative, explicitAlternatives) =>
        #[defaultAlternative, explicitAlternatives]
    | none => #[alternatives]
  some <| #[header] ++ bodyChildren ++ trailingChildren

def regroupNamedDiscriminant? (children : Array Tree) : Option Tree :=
  if children.size == 2 then do
    let nameAndColon ← children[0]?
    let discriminant ← children[1]?
    let (name, colon) ← Tree.extractTrailingLexeme? ":" nameAndColon
    if name.firstToken?.isNone || discriminant.firstToken?.isNone then
      none
    else
      some <| .node .namedDiscriminant #[name, colon, discriminant]
  else
    none

def regroupDependentIfNamedDiscriminant? (children : Array Tree)
    : Option (Array Tree) := do
  if children.size != 8 then
    none
  let name ← children[1]?
  let colon ← children[2]?
  let discriminant ← children[3]?
  if colon.singleToken?.any (·.lexeme == ":")
      && name.firstToken?.isSome
      && discriminant.firstToken?.isSome then
    some
    <| #[children[0]!, .node .namedDiscriminant #[name, colon, discriminant]]
        ++ childrenRange children 4 children.size
  else
    none

def regroupTacticAlternativeChildren (children : Array Tree) : Array Tree :=
  let regrouped? : Option (Array Tree) := do
    let lhs ← children[0]?
    let .node (.raw `null) rhsChildren ← children[1]? | none
    let rhsChildren := regroupAttachedBodyIntroducerChildren rhsChildren
    let bodyIndex ← rhsChildren.findIdx? Tree.isTacticSequenceTree
    let body ← rhsChildren[bodyIndex]?
    let header := .node .suffixGroup <| #[lhs] ++ childrenRange rhsChildren 0 bodyIndex
    some
    <| #[header, body]
        ++ childrenRange rhsChildren (bodyIndex + 1) rhsChildren.size
        ++ childrenRange children 2 children.size
  regrouped?.getD children

def regroupMacroChildren (children : Array Tree) : Array Tree :=
  let children :=
    match children.findIdx?
            fun child => rawKind? child == some `Lean.Parser.Command.macroTail with
    | some index =>
        match children[index]? with
        | some (.node (.raw `Lean.Parser.Command.macroTail) tailChildren) =>
            childrenRange children 0 index
            ++ tailChildren
            ++ childrenRange children (index + 1) children.size
        | _ => children
    | none => children
  (children.filter fun child => child.firstToken?.isSome).map
    fun child =>
      match child with
      | .node (.raw `null) patternChildren =>
          let patternChildren :=
            patternChildren.filter fun patternChild => patternChild.firstToken?.isSome
          if !patternChildren.isEmpty
              && patternChildren.all
                  fun patternChild =>
                    rawKind? patternChild == some `Lean.Parser.Command.macroArg then
            .node .macroPattern patternChildren
          else
            child
      | _ => child

def regroupRawNode
    (infixPrecedences : InfixPrecedenceMap)
    (spacedApplicationKinds : SpacedApplicationKindSet)
    (parserOwnedBodies : ParserOwnedBodyMap)
    (regroupSpacedApplications : Bool)
    (kind : SyntaxNodeKind) (children : Array Tree)
    : Tree :=
  if kind == `null then
    (regroupDerivingClause? children).getD <| .node (.raw kind) children
  else if kind == `Lean.Parser.Command.initialize then
    (regroupInitialize? children).getD <| .node (.raw kind) children
  else if kind == `Lean.Parser.Tactic.elimTarget then
    (regroupNamedDiscriminant? children).getD <| .node (.raw kind) children
  else if kind == `Lean.Parser.Tactic.cases then
    .node (.raw kind) ((regroupCasesChildren children).getD children)
  else if kind == `Lean.Parser.Tactic.induction then
    .node (.raw kind) ((regroupInductionChildren children).getD children)
  else if kind == `Lean.Parser.Tactic.inductionAlt then
    .node (.raw kind) (regroupTacticAlternativeChildren children)
  else if kind == `Lean.Parser.Command.macro then
    .node (.raw kind) (regroupMacroChildren children)
  else if kind == `termDepIfThenElse then
    let children := (regroupDependentIfNamedDiscriminant? children).getD children
    regroupIfThenElseChain kind children
  else if isIfThenElseKind kind then
    regroupIfThenElseChain kind children
  else if kind == `Lean.Parser.Command.macroTail
          || kind == `Lean.Parser.Term.namedArgument
          || kind == `Lean.Parser.Term.sufficesDecl
          || kind == `Lean.Parser.Term.fromTerm then
    let children :=
      if kind == `Lean.Parser.Term.fromTerm then
        regroupFromTermChildren
        <| regroupAttachedBodyIntroducerChildren children
            fun token => token.lexeme == "by"
      else
        regroupAttachedBodyIntroducerChildren children
    .node (.raw kind) ((regroupNestedAttachedBodyChildren? children).getD children)
  else if kind == `Lean.Parser.Term.app && children.size == 2 then
    match children[0]?, children[1]? with
    | some head, some argumentContainer =>
        let headAndArgs :=
          match head with
          | .node .application headChildren => headChildren
          | _ => #[head]
        .node .application
          (headAndArgs ++ appendApplicationArgumentChildren argumentContainer)
    | _, _ =>
        .node (.raw kind) children
  else if kind == `Lean.Parser.Term.doReturn || kind == `Lean.Parser.Term.termReturn then
    .node (.raw kind) ((regroupPrefixedApplication? children).getD children)
  else if kind == `Lean.Parser.Term.pipeProj && 2 < children.size then
    match children[0]?, children[1]?, children[2]? with
    | some receiver, some operator, some head =>
        let right :=
          if children.size == 3 then
            head
          else
            .node .application (#[head] ++ appendApplicationArgumentContainers children 3)
        let parts := appendInfixParts infixPrecedences kind #[] receiver
        .node (.infixChain kind) <| parts.push operator |>.push right
    | _, _, _ => .node (.raw kind) children
  else if kind == `Lake.DSL.packageCommand
          || kind == `Lake.DSL.leanLibCommand
          || kind == `Lake.DSL.leanExeCommand
          || kind == `Lake.DSL.externLibCommand then
    .node (.raw kind) (regroupLakeCommandChildren children)
  else if kind == `Lake.DSL.requireDecl then
    .node (.raw kind) (regroupLakeRequireChildren children)
  else if kind == `Lake.DSL.declField then
    .node .definition children
  else if kind == `Lean.Linter.«command_Register_linter_set_:=_» then
    .node (.raw kind) (regroupRegisterLinterSetChildren children)
  else if kind == `commandUnsuppress_compilationIn_ then
    .node (.raw kind) (regroupCommandInWrapperChildren children)
  else if kind == `Lean.Parser.Term.structInstFieldDef then
    .node (.raw kind) children
  else if kind == `Lean.Parser.Term.binderTactic then
    .node (.infixChain kind) (regroupBinderTacticChildren children)
  else if kind == `Lean.calcStep then
    (regroupCalcStep? children).getD <| .node (.raw kind) children
  else
    if let some policy := parserOwnedBodies.find? kind then
      (regroupParserOwnedBody? kind policy children).getD <| .node (.raw kind) children
    else
      if let some declaration := regroupPrefixedDeclaration? children then
        declaration
      else
        let spacedApplication? :=
          if regroupSpacedApplications then
            regroupSpacedApplication? spacedApplicationKinds kind children
          else
            none
        if let some application := spacedApplication? then
          application
        else
          if let some application := regroupGeneratedSuffixApplication? kind children then
            application
          else
            if isIndexedInfixRawNode kind children then
              .node (.indexedInfix kind) children
            else if isBinaryInfixRawNode kind children then
              match children[0]?, children[1]?, children[2]? with
              | some left, some operator, some right =>
                  let parts := appendInfixParts infixPrecedences kind #[] left
                  let parts := parts.push operator
                  let parts := appendInfixParts infixPrecedences kind parts right
                  let parts :=
                    if kind == `«term_<|_» then
                      regroupLowPriorityInfixRhs parts
                    else
                      parts
                  .node (.infixChain kind) parts
              | _, _, _ =>
                  .node (.raw kind) children
            else if kind == `Lean.Parser.Command.classAbbrev then
              .node .definition children
            else if kind == `Lean.Parser.Command.definition
                    || kind == `Lean.Parser.Command.abbrev
                    || kind == `Lean.Parser.Command.opaque then
              let children :=
                if kind == `Lean.Parser.Command.opaque then
                  regroupSeparatedDeclarationSignatureChildren children
                else
                  children
              let children := regroupEquationTrailingClauseChildren children
              match regroupDefinitionChildren children with
              | some definitionChildren => .node .definition definitionChildren
              | none => .node (.raw kind) children
            else if declarationValueCommandKind kind then
              regroupDeclarationValueCommand kind children
            else
              match regroupDefinitionChildren children with
              | some definitionChildren => .node .definition definitionChildren
              | none => regroupOtherRawNode kind children

private partial def regroupTreeWithPrecedencesInContext
    (infixPrecedences : InfixPrecedenceMap)
    (spacedApplicationKinds : SpacedApplicationKindSet)
    (parserOwnedBodies : ParserOwnedBodyMap)
    (isTacticSequenceEntry : Bool)
    : Tree → Tree
  | .missing => .missing
  | .leaf token => .leaf token
  | .node (.raw kind) children =>
      let childIsTacticSequenceEntry :=
        Tree.isTacticSequenceKind kind || (isTacticSequenceEntry && kind == `null)
      let tacticOperandsAtEvenIndexes :=
        isTacticSequenceEntry && isBinaryInfixRawNode kind children
      let regroupChildren (children : Array Tree) :=
        children.mapIdx
          fun index child =>
            regroupTreeWithPrecedencesInContext
              infixPrecedences spacedApplicationKinds parserOwnedBodies
              (if tacticOperandsAtEvenIndexes then
                  index % 2 == 0
                else
                  childIsTacticSequenceEntry)
              child
      let isDelimitedCollection := isDelimitedCollectionKind kind
      let outerDelimiter? :=
        if isDelimitedCollection || isGeneratedTermKind kind then
          none
        else
          outerDelimiterKind? children
      let tree :=
        if isDelimitedCollection || outerDelimiter? == some .bracket then
          let children := regroupChildren (flattenDelimitedCollectionChildren children)
          let children := flattenDelimitedCollectionChildren children
          if kind == `null && outerDelimiter? == some .bracket then
            .node (.delimitedCollection .bracket) children
          else
            .node (.raw kind) children
        else
          regroupRawNode infixPrecedences spacedApplicationKinds
            parserOwnedBodies (!isTacticSequenceEntry) kind (regroupChildren children)
      regroupCalcOwnerTree
      <| regroupTacticSequenceWrapperPrefix
      <| regroupTacticTerminalDelimiter
      <| Tree.annotateTacticTree tree spacedApplicationKinds
  | .node kind children =>
      .node kind
        (children.map
          (regroupTreeWithPrecedencesInContext
            infixPrecedences spacedApplicationKinds parserOwnedBodies false))

def regroupTreeWithPrecedences
    (infixPrecedences : InfixPrecedenceMap)
    (spacedApplicationKinds : SpacedApplicationKindSet := {})
    (parserOwnedBodies : ParserOwnedBodyMap := {})
    : Tree → Tree :=
  fun tree =>
    regroupSpacedTacticFirstOperands
    <| regroupDetachedParserOwnedTacticBodies parserOwnedBodies
    <| regroupTreeWithPrecedencesInContext
        infixPrecedences spacedApplicationKinds parserOwnedBodies false tree

def regroupTree (tree : Tree) : Tree :=
  regroupTreeWithPrecedences {} {} {} tree

def regroupTopLevelCommandAnnotations (tree : Tree) : Tree :=
  match tree with
  | .node .annotatedDeclaration _ => tree
  | _ =>
      match splitDeclarationAnnotations? tree with
      | some (annotations, command) =>
          annotatedDeclarationTreeForCommand annotations command
      | none =>
          match splitDirectCommandDocComment? tree with
          | some (annotations, command) =>
              annotatedDeclarationTreeForCommand annotations command
          | none => tree

private partial def annotateCommandContext : Tree → Tree
  | .node (.raw kind) children =>
      let nestedCommandIndex? : Option Nat := do
        let inIndex ←
          (List.range children.size).foldl
            (fun found index =>
              let firstLexeme := (children[index]?.bind Tree.firstToken?).map (·.lexeme)
              let lastLexeme := (children[index]?.bind Tree.lastToken?).map (·.lexeme)
              if firstLexeme == some "in" && lastLexeme == some "in" then
                some index
              else
                found)
            none
        let nestedIndex ←
          (List.range' (inIndex + 1) (children.size - (inIndex + 1))).find?
            fun index => children[index]?.bind Tree.firstToken? |>.isSome
        let lastIndex ← previousContentIndex? children children.size
        if nestedIndex == lastIndex then
          some nestedIndex
        else
          none
      let children :=
        match nestedCommandIndex? with
        | some index =>
            match children[index]? with
            | some nested => children.set! index (annotateCommandContext nested)
            | none => children
        | none => children
      .node (.command kind) children
  | tree => tree

private def annotateTopLevelCommand : Tree → Tree
  | .node .annotatedDeclaration children =>
      match children.back? with
      | some command@(.node (.raw _) _) =>
          .node .annotatedDeclaration
            (children.set! (children.size - 1) (annotateCommandContext command))
      | _ => .node .annotatedDeclaration children
  | command@(.node (.raw _) _) => annotateCommandContext command
  | tree => tree

def regroupTopLevelAnnotations : Tree → Tree
  | .node (.raw `Lean.Parser.Module.module) children =>
      match children[1]? with
      | some (Tree.node (.raw `null) commands) =>
          Tree.node (.raw `Lean.Parser.Module.module)
          <| children.set! 1
          <| Tree.node (.raw `null)
          <| commands.map
              fun command =>
                annotateTopLevelCommand <| regroupTopLevelCommandAnnotations command
      | _ => Tree.node (.raw `Lean.Parser.Module.module) children
  | tree => tree

structure LetBodyParserFact where
  letStart : String.Pos.Raw
  bodyCanStartApplicationArgument : Bool
deriving BEq, Repr

private abbrev LetBodyParserFactIndex := Std.HashMap String.Pos.Raw Bool

private def indexLetBodyParserFacts (facts : Array LetBodyParserFact)
    : LetBodyParserFactIndex :=
  facts.foldl
    (fun index fact =>
      index.insertIfNew fact.letStart fact.bodyCanStartApplicationArgument)
    {}

private partial def annotateLetExpressionsWithIndex (facts : LetBodyParserFactIndex)
    : Tree → Tree
  | .missing => .missing
  | .leaf token => .leaf token
  | .node kind children =>
      let children := children.map (annotateLetExpressionsWithIndex facts)
      match kind with
      | .raw rawKind =>
          if rawKind == `Lean.Parser.Term.let
              || rawKind == `Lean.Parser.Term.letI
              || rawKind == `Lean.Parser.Term.letrec then
            let bodyCanStartApplicationArgument :=
              match Tree.firstToken? (.node kind children) with
              | some token => facts[token.span.start]?.getD true
              | none => true
            .node (.letExpression rawKind bodyCanStartApplicationArgument) children
          else
            .node kind children
      | _ => .node kind children

def annotateLetExpressions (facts : Array LetBodyParserFact) (tree : Tree) : Tree :=
  annotateLetExpressionsWithIndex (indexLetBodyParserFacts facts) tree

private partial def regroupSimpleApplicationProofArgumentsWithSummary : Tree → Tree × Bool
  | .missing => (.missing, false)
  | .leaf token => (.leaf token, false)
  | .node kind children =>
      let summaries := children.map regroupSimpleApplicationProofArgumentsWithSummary
      let children := summaries.map (fun summary => summary.1)
      let tree := .node kind children
      let proofArgumentCount :=
        summaries.foldl (fun count summary => if summary.2 then count + 1 else count) 0
      let tree :=
        if kind == .application && proofArgumentCount == 1 then
          (Tree.groupSimpleTrailingProofArgument? tree).getD tree
        else
          tree
      let containsProofBody :=
        kind == .proofBody false || kind == .proofBody true || 0 < proofArgumentCount
      (tree, containsProofBody)

private def regroupSimpleApplicationProofArguments (tree : Tree) : Tree :=
  (regroupSimpleApplicationProofArgumentsWithSummary tree).1

def extractTree
    (source : String) (stx : Syntax)
    (letBodyParserFacts : Array LetBodyParserFact := #[])
    (infixPrecedences : InfixPrecedenceMap := {})
    (spacedApplicationKinds : SpacedApplicationKindSet := {})
    (parserOwnedBodies : ParserOwnedBodyMap := {})
    : Tree :=
  regroupTopLevelAnnotations
  <| annotateLetExpressions letBodyParserFacts
  <| regroupSimpleApplicationProofArguments
  <| regroupTreeWithPrecedences infixPrecedences spacedApplicationKinds parserOwnedBodies
  <| removeOverlappingSourceTokens source
  <| extractRawTree source stx

/-! ## Lean module parsing -/

def importEnvironment
    (imports : Array Import) (leakEnv := false)
    (level : OLeanLevel := .private)
    : IO Environment :=
  LeanEnvironment.importEnvironment { imports, level } (leakEnv := leakEnv)

def importLeanEnvironment : IO Environment := do
  importEnvironment #[{ module := `Lean }]

def parserStateCommandKind : SyntaxNodeKind → Bool
  | `Lean.Parser.Command.open
  | `Lean.Parser.Command.namespace
  | `Lean.Parser.Command.syntax
  | `Lean.Parser.Command.macro
  | `Lean.Parser.Command.notation
  | `Lean.Parser.Command.mixfix
  | `Lean.Parser.Command.infix
  | `Lean.Parser.Command.infixl
  | `Lean.Parser.Command.infixr
  | `Lean.Parser.Command.prefix
  | `Lean.Parser.Command.postfix
  | `Mathlib.Notation3.notation3
  | `Mathlib.Tactic.scopedNS => true
  | _ => false

partial def syntaxContainsParserStateCommandKind : Syntax → Bool
  | Syntax.node _ kind children =>
      parserStateCommandKind kind || children.any syntaxContainsParserStateCommandKind
  | _ => false

def commandUpdatesParserState (command : Syntax) : Bool :=
  syntaxContainsParserStateCommandKind command

def parserStateCommandContext (inputContext : Parser.InputContext)
    : Elab.Command.Context :=
  {
    fileName := inputContext.fileName
    fileMap := inputContext.fileMap
    snap? := none
    cancelTk? := none
  }

def parserModuleContext (commandState : Elab.Command.State)
    : Parser.ParserModuleContext :=
  let scope := commandState.scopes.head!
  {
    env := commandState.env
    options := scope.opts
    currNamespace := scope.currNamespace
    openDecls := scope.openDecls
  }

def syntaxSourceText? (source : String) (stx : Syntax) : Option String := do
  let start ← stx.getPos? (canonicalOnly := true)
  let stop ← stx.getTailPos? (canonicalOnly := true)
  if start < stop then
    some <| sourceText source start stop
  else
    none

def bodyCanStartApplicationArgument
    (parserContext : Parser.ParserModuleContext)
    (bodySource : String)
    : Bool :=
  let inputContext := Parser.mkInputContext bodySource "<let-body-argument-probe>"
  let state :=
    (Parser.termParser Parser.argPrec).fn.run inputContext parserContext
      (Parser.getTokenTable parserContext.env)
      (Parser.mkParserState bodySource)
  !state.hasError && 0 < state.pos

def letBodyIndex? (kind : SyntaxNodeKind) : Option Nat :=
  if kind == `Lean.Parser.Term.let || kind == `Lean.Parser.Term.letI then
    some 4
  else if kind == `Lean.Parser.Term.letrec then
    some 3
  else
    none

partial def collectLetBodyParserFacts
    (source : String) (parserContext : Parser.ParserModuleContext)
    (stx : Syntax) (facts : Array LetBodyParserFact := #[])
    : Array LetBodyParserFact :=
  let facts :=
    match stx with
    | .node _ kind children =>
        match letBodyIndex? kind with
        | some bodyIndex =>
            match stx.getPos? (canonicalOnly := true), children[bodyIndex]? with
            | some letStart, some body =>
                match syntaxSourceText? source body with
                | some bodySource =>
                    facts.push
                      {
                        letStart
                        bodyCanStartApplicationArgument :=
                          bodyCanStartApplicationArgument parserContext bodySource
                      }
                | none => facts
            | _, _ => facts
        | none => facts
    | _ => facts
  stx.getArgs.foldl
    (fun facts child =>
      collectLetBodyParserFacts source parserContext child facts)
    facts

def elaborateParserStateCommand
    (inputContext : Parser.InputContext)
    (commandState : Elab.Command.State)
    (command : Syntax)
    : IO Elab.Command.State := do
  let context := parserStateCommandContext inputContext
  let (_, (_, commandState)) ←
    IO.FS.withIsolatedStreams
      (isolateStderr := true) do
        EIO.toIO (fun _ => IO.userError "failed to update parser command state")
          ((Elab.Command.elabCommand command).run context |>.run commandState)
  pure commandState

partial def parseModuleCommandsQuiet
    (inputContext : Parser.InputContext)
    (state : Parser.ModuleParserState) (messages : MessageLog)
    (commandState : Elab.Command.State)
    (updateParserState : Bool)
    (commands : Array Syntax)
    (letBodyParserFacts : Array LetBodyParserFact)
    : IO (Array Syntax × Array LetBodyParserFact × Elab.Command.State) := do
  let parserContext := parserModuleContext commandState
  let (command, state, messages) :=
    Parser.parseCommand inputContext parserContext state messages
  if Parser.isTerminalCommand command then
    if messages.hasUnreported then
      let messageTexts ← messages.toList.mapM fun message => message.toString
      let details := "\n".intercalate messageTexts
      throw
      <| IO.userError
      <|  if details.isEmpty then
            "failed to parse file"
          else
            s!"failed to parse file:\n{details}"
    else
      pure (commands, letBodyParserFacts, commandState)
  else do
    let letBodyParserFacts :=
      collectLetBodyParserFacts inputContext.inputString parserContext command
        letBodyParserFacts
    let commandState ←
      if updateParserState && commandUpdatesParserState command then
        elaborateParserStateCommand inputContext commandState command
      else
        pure commandState
    parseModuleCommandsQuiet inputContext state messages commandState
      updateParserState (commands.push command) letBodyParserFacts

structure ParsedModuleSyntax where
  rawSyntax : Syntax
  letBodyParserFacts : Array LetBodyParserFact
  infixPrecedences : InfixPrecedenceMap
  spacedApplicationKinds : SpacedApplicationKindSet
  parserOwnedBodies : ParserOwnedBodyMap

instance : Repr ParsedModuleSyntax where
  reprPrec parsed precedence :=
    let spacedApplicationKinds :=
      parsed.spacedApplicationKinds.foldl (fun kinds kind => kinds.push kind) #[]
    reprPrec
      (
        parsed.rawSyntax,
        parsed.letBodyParserFacts,
        parsed.infixPrecedences,
        spacedApplicationKinds,
        parsed.parserOwnedBodies
      )
      precedence

def parseModuleSyntaxWithEnvCoreDetailed
    (env : Environment) (source fileName : String) (updateParserState : Bool)
    : IO ParsedModuleSyntax := do
  let inputContext := Parser.mkInputContext source fileName
  let (header, state, messages) ← Parser.parseHeader inputContext
  let commandState := Elab.Command.mkState env
  let (commands, letBodyParserFacts, commandState) ←
    try
      parseModuleCommandsQuiet inputContext state messages commandState
        updateParserState #[] #[]
    catch parseError =>
      if updateParserState then
        let frontendState ← Elab.IO.processCommands inputContext state commandState
        let commands :=
          frontendState.commands.filter
            fun command =>
              !Parser.isTerminalCommand command
        pure (commands, #[], frontendState.commandState)
      else
        throw parseError
  let rawSyntax :=
    (mkNode `Lean.Parser.Module.module #[header, mkListNode commands]).raw.updateLeading
  let parserContext := parserModuleContext commandState
  let parserLayoutFacts :=
    collectParserLayoutFacts parserContext.env parserContext.options rawSyntax
  pure
    {
      rawSyntax := rawSyntax
      letBodyParserFacts := letBodyParserFacts
      infixPrecedences := parserLayoutFacts.infixPrecedences
      spacedApplicationKinds := parserLayoutFacts.spacedApplicationKinds
      parserOwnedBodies := parserLayoutFacts.parserOwnedBodies
    }

def parseModuleSyntaxWithEnvCore
    (env : Environment) (source fileName : String) (updateParserState : Bool)
    : IO Syntax := do
  pure
    (← parseModuleSyntaxWithEnvCoreDetailed env source fileName
        updateParserState).rawSyntax

def parseModuleSyntaxWithEnv (env : Environment) (source fileName : String) : IO Syntax :=
  parseModuleSyntaxWithEnvCore env source fileName (updateParserState := true)

def parseModuleSyntaxWithoutParserStateUpdates
    (env : Environment) (source fileName : String)
    : IO Syntax :=
  parseModuleSyntaxWithEnvCore env source fileName (updateParserState := false)

def parseModuleSyntax (source fileName : String) : IO Syntax := do
  parseModuleSyntaxWithEnv (← importLeanEnvironment) source fileName

def parseModuleStringWithEnv (env : Environment) (source fileName : String := "<input>")
    : IO Module := do
  let parsed ←
    parseModuleSyntaxWithEnvCoreDetailed env source fileName (updateParserState := true)
  let tree :=
    extractTree source parsed.rawSyntax parsed.letBodyParserFacts parsed.infixPrecedences
      parsed.spacedApplicationKinds parsed.parserOwnedBodies
  pure { source, rawSyntax := parsed.rawSyntax, tree, tokens := tree.tokens }

def parseModuleString (source fileName : String := "<input>") : IO Module := do
  parseModuleStringWithEnv (← importLeanEnvironment) source fileName

end SyntaxTree
end LeanFmt
