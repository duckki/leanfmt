import LeanFmt.Formatter.LineBreakRules
import LeanFmt.Formatter.LayoutPlan
import LeanFmt.Formatter.LayoutTree
import LeanFmt.Formatter.OriginalTree
import LeanFmt.Formatter.Rebase
import LeanFmt.Formatter.SourceBoundary
import LeanFmt.Formatter.SpaceRules
import LeanFmt.Formatter.Trace

namespace LeanFmt
namespace Formatter

/-! ## Output and indentation state -/

def maxLineWidth : Nat :=
  90

structure Options where
  lineWidth : Nat := maxLineWidth
deriving BEq, Repr

def indentationSpaces : Nat :=
  OriginalTree.indentationSpaces

def lineWidth (text : String) : Nat :=
  text.length

def firstLineAppendWidth (text : String) : Nat × Bool :=
  let first := text.takeWhile fun char => char != '\n' && char != '\r'
  (first.toString.length, first.utf8ByteSize < text.utf8ByteSize)

def lineFits (text : String) (limit : Nat := maxLineWidth) : Bool :=
  lineWidth text <= limit

def linesFit (text : String) (limit : Nat := maxLineWidth) : Bool :=
  (SpaceRules.normalizeLineEndings text).splitOn "\n"
  |>.all fun line => lineFits line limit

def lineFitsWithTrailingWidth
    (line : String) (trailingWidth : Nat) (limit : Nat := maxLineWidth)
    : Bool :=
  lineWidth line + trailingWidth <= limit

def linesFitWithTrailingWidth
    (text : String) (trailingWidth : Nat) (limit : Nat := maxLineWidth)
    : Bool :=
  let rec loop : List String → Bool
    | [] => trailingWidth <= limit
    | [line] => lineFitsWithTrailingWidth line trailingWidth limit
    | line :: rest => lineFits line limit && loop rest
  loop <| (SpaceRules.normalizeLineEndings text).splitOn "\n"

def spaces (count : Nat) : String :=
  String.ofList <| List.replicate count ' '

def indentationLevelForColumn (column : Nat) : Nat :=
  column / indentationSpaces

def indentationPastColumn (column : Nat) : Nat :=
  indentationLevelForColumn (column + indentationSpaces - 1) * indentationSpaces

def leadingWhitespace (line : String) : String :=
  (line.takeWhile SpaceRules.isHorizontalWhitespace).toString

def hasLineBreakChar (text : String) : Bool :=
  (text.toByteArray.findIdx?
    fun byte => byte == '\n'.toUInt8 || byte == '\r'.toUInt8).isSome

structure AppendedLines where
  lineBreakCount : Nat
  completedLineOverflowCount : Nat
  currentLine : String

inductive AppendedTextKind where
  | code
  | trivia
deriving BEq

def appendedLines
    (currentLine text : String) (limit : Nat := maxLineWidth)
    (kind : AppendedTextKind := .code)
    : AppendedLines :=
  let rec loop (lineWidth breakCount overflowCount : Nat) (countOverflow : Bool)
      (current : List Char)
      : List Char → AppendedLines
    | [] =>
        {
          lineBreakCount := breakCount
          completedLineOverflowCount := overflowCount
          currentLine := String.ofList current.reverse
        }
    | '\r' :: '\n' :: rest =>
        loop 0 (breakCount + 1)
          (overflowCount + if countOverflow && lineWidth > limit then 1 else 0)
          (kind == .code) [] rest
    | '\n' :: rest =>
        loop 0 (breakCount + 1)
          (overflowCount + if countOverflow && lineWidth > limit then 1 else 0)
          (kind == .code) [] rest
    | '\r' :: rest =>
        loop 0 (breakCount + 1)
          (overflowCount + if countOverflow && lineWidth > limit then 1 else 0)
          (kind == .code) [] rest
    | char :: rest =>
        loop (lineWidth + 1) breakCount overflowCount countOverflow (char :: current) rest
  let countInitialOverflow := kind == .code || !currentLine.trimAscii.isEmpty
  loop currentLine.length 0 0 countInitialOverflow [] text.toList

def charsAfterLastNewline (text : String) : String :=
  ((SpaceRules.normalizeLineEndings text).takeEndWhile (· != '\n')).toString

def hasBlankLineStructure (text : String) : Bool :=
  hasLineBreakChar text
  && SpaceRules.containsSubstring (SpaceRules.normalizeLineEndings text) "\n\n"

def treeFirstSourceLineWidth? (source : String) (tree : SyntaxTree.Tree)
    : Option Nat := do
  let first ← tree.firstToken?
  let last ← tree.lastToken?
  some
  <| (firstLineAppendWidth
        (SyntaxTree.sourceText source first.span.start last.span.stop)).1

/-- Cached source-layout facts. This mirrors the immutable syntax tree so speculative
rendering can reuse classification results without moving syntax policy into the renderer. -/
structure TreeLayoutSummary where
  retryOwner? : Option LayoutTree.RetryOwner := none
  originalPlan? : Option OriginalTree.IslandPlan := none
  startsWithOriginalEmission : Bool := false
  startsWithRetainedOriginalBoundary : Bool := false
  startsWithUnbreakableOriginalFirstLine : Bool := false
  containsMultilineOriginalEmission : Bool := false
  containsCommentForcedBreak : Bool := false
  containsLineCommentForcedBreak : Bool := false
  firstToken? : Option SyntaxTree.Token := none
  lastToken? : Option SyntaxTree.Token := none
  firstSourceToken? : Option SyntaxTree.Token := none
  lastSourceToken? : Option SyntaxTree.Token := none
deriving Repr

inductive TreeLayoutFacts where
  | node (summary : TreeLayoutSummary) (children : Array TreeLayoutFacts)

instance : Inhabited TreeLayoutFacts :=
  ⟨.node {} #[]⟩

instance : Repr TreeLayoutFacts where
  reprPrec _ precedence := reprPrec ("<tree-layout-facts>" : String) precedence

namespace TreeLayoutFacts

def summary : TreeLayoutFacts → TreeLayoutSummary
  | .node summary _ => summary

def child? : TreeLayoutFacts → Nat → Option TreeLayoutFacts
  | .node _ children, index => children[index]?

private structure BoundaryFold where
  firstSourceToken? : Option SyntaxTree.Token := none
  lastSourceToken? : Option SyntaxTree.Token := none
  containsCommentForcedBreak : Bool := false
  containsLineCommentForcedBreak : Bool := false

private def BoundaryFold.push
    (source : String) (boundaries : SourceBoundary.Cache)
    (fold : BoundaryFold) (child : TreeLayoutFacts)
    : BoundaryFold :=
  let childSummary := child.summary
  let containsCommentForcedBreak :=
    fold.containsCommentForcedBreak || childSummary.containsCommentForcedBreak
  let containsLineCommentForcedBreak :=
    fold.containsLineCommentForcedBreak || childSummary.containsLineCommentForcedBreak
  let boundary? := do
    if containsCommentForcedBreak && containsLineCommentForcedBreak then none
    let left ← fold.lastSourceToken?
    let right ← childSummary.firstSourceToken?
    some <| SourceBoundary.factsBetween source left right boundaries
  {
    firstSourceToken? :=
      fold.firstSourceToken?.orElse fun _ => childSummary.firstSourceToken?
    lastSourceToken? :=
      childSummary.lastSourceToken?.orElse fun _ => fold.lastSourceToken?
    containsCommentForcedBreak :=
      containsCommentForcedBreak
      || boundary?.any fun boundary => boundary.commentForcesBreak
    containsLineCommentForcedBreak :=
      containsLineCommentForcedBreak || boundary?.any (·.lineCommentForcesBreak)
  }

private def sourceHasLineStructure
    (source : String) (firstToken? lastToken? : Option SyntaxTree.Token)
    : Bool :=
  match firstToken?, lastToken? with
  | some firstToken, some lastToken =>
      SpaceRules.hasLineStructure
        (SyntaxTree.sourceText source firstToken.span.start lastToken.span.stop)
  | _, _ => false

private def childrenContainMultilineOriginalEmission
    (source : String) (children : Array TreeLayoutFacts)
    (start := 0) (stop := children.size)
    : Bool :=
  Id.run do
    let mut previous? := none
    for index in [start:min stop children.size] do
      let summary := children[index]!.summary
      if summary.containsMultilineOriginalEmission then
        return true
      if summary.startsWithRetainedOriginalBoundary then
        if let (some left, some right) := (previous?, summary.firstToken?) then
          if SpaceRules.hasLineStructure
              (SyntaxTree.sourceText source left.span.stop right.span.start) then
            return true
      if let some last := summary.lastToken? then
        previous? := some last
    return false

private def resolveSummary
    (source : String) (summary : TreeLayoutSummary)
    (originalPlan? : Option OriginalTree.IslandPlan) (children : Array TreeLayoutFacts)
    : TreeLayoutSummary :=
  let firstChild? := children.find? fun child => child.summary.firstToken?.isSome
  {
    summary with
      originalPlan?
      startsWithOriginalEmission :=
        originalPlan?.isSome || firstChild?.any (·.summary.startsWithOriginalEmission)
      startsWithRetainedOriginalBoundary :=
        match originalPlan? with
        | some plan => plan.policy.leadingBoundary == .preserveWithIsland
        | none => firstChild?.any (·.summary.startsWithRetainedOriginalBoundary)
      startsWithUnbreakableOriginalFirstLine :=
        match originalPlan? with
        | some plan => plan.policy.firstLine == .unbreakable
        | none => firstChild?.any (·.summary.startsWithUnbreakableOriginalFirstLine)
      containsMultilineOriginalEmission :=
        match originalPlan? with
        | some _ =>
            sourceHasLineStructure source summary.firstToken? summary.lastToken?
        | none => childrenContainMultilineOriginalEmission source children
  }

/-- Resolve an alternative once, including the summaries used by fit and suffix probes. -/
partial def withAlternative
    (source : String) (facts : TreeLayoutFacts)
    (alternative : OriginalTree.OverflowAlternative)
    : TreeLayoutFacts :=
  match alternative, facts with
  | .unchanged, _ => facts
  | .preserve plan, .node summary children =>
      .node (resolveSummary source summary (some plan) children) children
  | .structural alternatives, .node summary children =>
      let children :=
        children.mapIdx
          fun index child =>
            child.withAlternative source (alternatives[index]?.getD .unchanged)
      .node (resolveSummary source summary none children) children

/-- Canonical source facts only: no retry descriptors or emission-policy overrides.
Entries are scoped to one source and checked against the complete tree on lookup. -/
abbrev Cache := Std.HashMap (Nat × Nat) (Array (SyntaxTree.Tree × TreeLayoutFacts))

private def cached? (cache : Cache) (tree : SyntaxTree.Tree)
    : Option TreeLayoutFacts := do
  if cache.isEmpty then none
  let first ← tree.firstToken?
  let last ← tree.lastToken?
  let entries ← cache[(first.span.start.byteIdx, last.span.stop.byteIdx)]?
  let (_, facts) ← entries.find? fun (original, _) => original == tree
  some facts

partial def ofTree (source : String) (tree : SyntaxTree.Tree)
    (boundaries : SourceBoundary.Cache := {})
    (cache : Cache := {})
    : TreeLayoutFacts :=
  if let some facts := cached? cache tree then
    facts
  else
    match tree with
    | .missing => .node {} #[]
    | .leaf token =>
        let token? := if token.lexeme.isEmpty then none else some token
        let sourceToken? :=
          if SyntaxTree.tokenComesFromSource source token then some token else none
        .node
          {
            firstToken? := token?,
            lastToken? := token?
            firstSourceToken? := sourceToken?,
            lastSourceToken? := sourceToken?
          }
          #[]
    | .node _ children =>
        let childFacts := children.map fun child => ofTree source child boundaries cache
        let firstToken? := childFacts.findSome? fun child => child.summary.firstToken?
        let lastToken? := childFacts.findSomeRev? fun child => child.summary.lastToken?
        let boundaries := childFacts.foldl (BoundaryFold.push source boundaries) {}
        let originalPlan? := OriginalTree.plan? tree
        .node
          (resolveSummary source
            {
              containsCommentForcedBreak := boundaries.containsCommentForcedBreak
              containsLineCommentForcedBreak := boundaries.containsLineCommentForcedBreak
              firstToken?
              lastToken?
              firstSourceToken? := boundaries.firstSourceToken?
              lastSourceToken? := boundaries.lastSourceToken?
            }
            originalPlan? childFacts)
          childFacts

/-- Capture a bounded cache before applying any rendering alternatives. New retry
groupings are never added, so cache size cannot grow with the number of retries. -/
partial def cacheOfTree (source : String) (tree : SyntaxTree.Tree)
    (boundaries : SourceBoundary.Cache := {})
    : Cache :=
  collect tree (ofTree source tree boundaries) {}
where
  collect (tree : SyntaxTree.Tree) (facts : TreeLayoutFacts) (cache : Cache) : Cache :=
    let cache :=
      match facts.summary.firstToken?, facts.summary.lastToken? with
      | some first, some last =>
          let key := (first.span.start.byteIdx, last.span.stop.byteIdx)
          cache.insert key ((cache[key]?.getD #[]).push (tree, facts))
      | _, _ => cache
    match tree, facts with
    | .node _ children, .node _ childFacts =>
        (children.zip childFacts).foldl
          (fun cache (child, facts) => collect child facts cache) cache
    | _, _ => cache

private def withRetryOwner (facts : TreeLayoutFacts) (path : List Nat)
    (owner : LayoutTree.RetryOwner)
    : TreeLayoutFacts :=
  match facts, path with
  | .node summary children, [] =>
      .node { summary with retryOwner? := some owner } children
  | .node summary children, index :: rest =>
      match children[index]? with
      | none => facts
      | some child =>
          .node summary (children.set! index (child.withRetryOwner rest owner))

def ofPrepared (source : String) (view : LayoutTree.Prepared) (cache : Cache := {})
    : TreeLayoutFacts :=
  view.retryOwners.foldl
    (fun facts (path, owner) => facts.withRetryOwner path owner)
    (ofTree source view.tree view.boundaries cache)

end TreeLayoutFacts

structure SourceBreak where
  index : Nat
  indent : Nat
deriving BEq, Repr

structure TailIndentationAnchor where
  stop : Nat
  indentation : Nat
deriving Repr

inductive CommandBoundarySpacing where
  | lineBreak
  | blankLine
deriving BEq, Repr

structure RenderState where
  options : Options := {}
  source : String
  sourceMap : SyntaxTree.SourcePositionMap
  layoutFacts? : Option TreeLayoutFacts := none
  retryFacts : TreeLayoutFacts.Cache := {}
  guardedJoins : Std.HashSet Nat := {}
  brokenJoins : Std.HashSet Nat := {}
  output : String := ""
  outputLineBreakCount : Nat := 0
  completedLineOverflowCount : Nat := 0
  introducedAtomicOverflowCount : Nat := 0
  currentLine : String := ""
  lastToken? : Option SyntaxTree.Token := none
  pendingIndent? : Option Nat := none
  pendingCommandBoundary? : Option CommandBoundarySpacing := none
  preserveNextStandaloneCommentIndent : Bool := false
  movePendingCommentAfterToken : Bool := false
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
deriving Repr

structure WhitespaceState where
  options : Options
  source : String
  sourceMap : SyntaxTree.SourcePositionMap
  currentLine : String
  lastToken? : Option SyntaxTree.Token
  pendingIndent? : Option Nat
  pendingCommandBoundary? : Option CommandBoundarySpacing
  preserveNextStandaloneCommentIndent : Bool
  movePendingCommentAfterToken : Bool
  layoutAnchor : Rebase.Anchor

def RenderState.whitespaceState (state : RenderState) : WhitespaceState :=
  {
    options := state.options
    source := state.source
    sourceMap := state.sourceMap
    currentLine := state.currentLine
    lastToken? := state.lastToken?
    pendingIndent? := state.pendingIndent?
    pendingCommandBoundary? := state.pendingCommandBoundary?
    preserveNextStandaloneCommentIndent := state.preserveNextStandaloneCommentIndent
    movePendingCommentAfterToken := state.movePendingCommentAfterToken
    layoutAnchor := state.layoutAnchor
  }

structure SegmentBase where
  column : Nat
  indentation : Nat
deriving Repr

structure ChildRenderScope where
  context : LineBreakRules.RuleContext
  layoutFacts? : Option TreeLayoutFacts
  segmentBaseColumn : Nat
  segmentIndentation : Nat
  layoutAnchor : Rebase.Anchor
  tailIndentation? : Option Nat
  tailIndentationStop? : Option Nat
  tailIndentationAnchors : List TailIndentationAnchor
  breakIndentationShift : Nat
  lineFitSuffixWidth : Nat
  trace : Trace.State

def ChildRenderScope.capture (state : RenderState) : ChildRenderScope :=
  {
    context := state.context
    layoutFacts? := state.layoutFacts?
    segmentBaseColumn := state.segmentBaseColumn
    segmentIndentation := state.segmentIndentation
    layoutAnchor := state.layoutAnchor
    tailIndentation? := state.tailIndentation?
    tailIndentationStop? := state.tailIndentationStop?
    tailIndentationAnchors := state.tailIndentationAnchors
    breakIndentationShift := state.breakIndentationShift
    lineFitSuffixWidth := state.lineFitSuffixWidth
    trace := state.trace
  }

def ChildRenderScope.restore (scope : ChildRenderScope) (rendered : RenderState)
    : RenderState :=
  {
    rendered with
      context := scope.context
      layoutFacts? := scope.layoutFacts?
      segmentBaseColumn := scope.segmentBaseColumn
      segmentIndentation := scope.segmentIndentation
      layoutAnchor := scope.layoutAnchor
      tailIndentation? := scope.tailIndentation?
      tailIndentationStop? := scope.tailIndentationStop?
      tailIndentationAnchors := scope.tailIndentationAnchors
      breakIndentationShift := scope.breakIndentationShift
      lineFitSuffixWidth := scope.lineFitSuffixWidth
      trace := rendered.trace.restorePathFrom scope.trace
  }

def currentLineAfterAppend (currentLine text : String) : String :=
  if hasLineBreakChar text then
    charsAfterLastNewline text
  else
    currentLine ++ text

def introducesCompletedLineOverflow
    (currentLine text : String) (limit : Nat := maxLineWidth)
    : Bool :=
  let rec loop (lineWidth : Nat) (lineTouched : Bool) : List Char → Bool
    | [] => false
    | '\r' :: '\n' :: rest =>
        (lineTouched && lineWidth > limit) || loop 0 false rest
    | '\n' :: rest => (lineTouched && lineWidth > limit) || loop 0 false rest
    | '\r' :: rest => (lineTouched && lineWidth > limit) || loop 0 false rest
    | _ :: rest => loop (lineWidth + 1) true rest
  loop currentLine.length false text.toList

def RenderState.appendOutputAs
    (state : RenderState) (kind : AppendedTextKind) (text : String)
    : RenderState :=
  if hasLineBreakChar text then
    let appended := appendedLines state.currentLine text state.options.lineWidth kind
    {
      state with
        output := state.output ++ text
        outputLineBreakCount := state.outputLineBreakCount + appended.lineBreakCount
        completedLineOverflowCount :=
          state.completedLineOverflowCount + appended.completedLineOverflowCount
        currentLine := appended.currentLine
    }
  else
    {
      state with
        output := state.output ++ text
        currentLine := state.currentLine ++ text
    }

def RenderState.appendOutput (state : RenderState) (text : String) : RenderState :=
  state.appendOutputAs .code text

def RenderState.appendTriviaOutput (state : RenderState) (text : String) : RenderState :=
  state.appendOutputAs .trivia text

def segmentFirstToken? (segment : LineBreakRules.Segment) : Option SyntaxTree.Token :=
  match segment.parent with
  | .leaf token => if token.lexeme.isEmpty then none else some token
  | .missing => none
  | .node _ _ =>
      segment.indexes.foldl
        (fun found index =>
          match found with
          | some token => some token
          | none =>
              match segment.child? index with
              | some child => SyntaxTree.Tree.firstToken? child
              | none => none)
        none

def RenderState.currentColumn (state : RenderState) : Nat :=
  match state.pendingIndent? with
  | some indent => indent
  | none => lineWidth state.currentLine

def WhitespaceState.currentIndent (state : WhitespaceState) : Nat :=
  match state.pendingIndent? with
  | some indent => indent
  | none => (leadingWhitespace state.currentLine).length

def RenderState.currentIndent (state : RenderState) : Nat :=
  state.whitespaceState.currentIndent

def RenderState.segmentBaseIndent (state : RenderState) : Nat :=
  state.segmentIndentation * indentationSpaces

def ensureBlankLineBeforeIndentation (text indentation : String) : String :=
  let lineSuffix := "\n" ++ indentation
  let blankSuffix := "\n\n" ++ indentation
  if text.endsWith blankSuffix then
    text
  else if text.endsWith lineSuffix then
    (text.dropEnd lineSuffix.length).toString ++ blankSuffix
  else
    text ++ blankSuffix

def ensureBlankLineBeforeLeadingComment (text : String) : String :=
  if text.startsWith "\n\n" || text.startsWith "\r\n\r\n" then
    text
  else if text.startsWith "\n" || text.startsWith "\r\n" then
    "\n" ++ text
  else
    "\n\n" ++ text

def commentTriviaForBoundary
    (boundary : SourceBoundary.Boundary)
    (commentIndentation followingIndentation : String)
    (spacing : CommandBoundarySpacing)
    (belongsToFollowingToken : Bool := true)
    : String :=
  let adjusted :=
    boundary.forBreakWithFollowingIndent commentIndentation followingIndentation
  if spacing == .blankLine then
    if boundary.hasSeparatedCommentGroups then
      adjusted
    else if boundary.startsOnNewLine then
      if belongsToFollowingToken then
        ensureBlankLineBeforeLeadingComment adjusted
      else
        ensureBlankLineBeforeIndentation adjusted followingIndentation
    else
      ensureBlankLineBeforeIndentation adjusted followingIndentation
  else
    adjusted

def whitespaceForPendingBoundary
    (boundary : SourceBoundary.Boundary) (indentation : String)
    (commandBoundary? : Option CommandBoundarySpacing)
    : String :=
  if boundary.hasComment then
    let result :=
      match commandBoundary? with
      | some spacing =>
          commentTriviaForBoundary boundary indentation indentation spacing
      | none =>
          boundary.forBreakWithFollowingIndent indentation indentation
    result
  else
    match commandBoundary? with
    | none =>
        if hasBlankLineStructure boundary.text then
          "\n\n" ++ indentation
        else
          "\n" ++ indentation
    | some .lineBreak => "\n" ++ indentation
    | some .blankLine => "\n\n" ++ indentation

def WhitespaceState.indentForMultilineToken
    (state : WhitespaceState) (token : SyntaxTree.Token) (desiredIndent : Nat)
    : Nat :=
  if hasLineBreakChar token.lexeme then
    match (SpaceRules.normalizeLineEndings token.lexeme).splitOn "\n" with
    | [] => desiredIndent
    | firstLine :: _ =>
        let sourceColumn := state.sourceMap.columnAt token.span.start
        if desiredIndent + firstLine.length > state.options.lineWidth
            && sourceColumn + firstLine.length <= state.options.lineWidth then
          sourceColumn
        else
          desiredIndent
  else
    desiredIndent

def WhitespaceState.movePendingCommentAfterTokenIfFits
    (state : WhitespaceState) (whitespace : String)
    : String :=
  if !state.movePendingCommentAfterToken then
    whitespace
  else
    match (SourceBoundary.ofText whitespace).moveLeadingCommentAfterToken? with
    | some moved =>
        let firstLineWidth := (firstLineAppendWidth moved.text).1
        if lineWidth state.currentLine + firstLineWidth <= state.options.lineWidth then
          moved.text
        else
          whitespace
    | none => whitespace

def WhitespaceState.defaultWhitespace (state : WhitespaceState) (token : SyntaxTree.Token)
    (preserveLines : Bool := false)
    : String :=
  let whitespace :=
    match state.lastToken?, state.pendingIndent? with
    | some left, some indent =>
        let trivia := SyntaxTree.sourceText state.source left.span.stop token.span.start
        let boundary := SourceBoundary.ofText trivia
        let indent := state.indentForMultilineToken token indent
        let indentation := spaces indent
        if state.preserveNextStandaloneCommentIndent
            && boundary.hasComment
            && !boundary.startsAfterBlankLine then
          match boundary.standaloneCommentIndent? with
          | some sourceIndent =>
              let sourceFollowingIndent := state.sourceMap.columnAt token.span.start
              if sourceIndent <= sourceFollowingIndent then
                let belongsToFollowingToken := !boundary.endsBeforeBlankLine
                match state.pendingCommandBoundary? with
                | some spacing =>
                    commentTriviaForBoundary boundary indentation indentation spacing
                      belongsToFollowingToken
                | none =>
                    boundary.forBreakWithFollowingIndent indentation indentation
              else
                let leftStayedAtSourceColumn :=
                  state.currentLine.endsWith left.lexeme
                  && lineWidth state.currentLine - left.lexeme.length
                      == state.sourceMap.columnAt left.span.start
                if leftStayedAtSourceColumn then
                  let commentIndentation := spaces sourceIndent
                  match state.pendingCommandBoundary? with
                  | some spacing =>
                      commentTriviaForBoundary boundary commentIndentation indentation
                        spacing false
                  | none =>
                      boundary.forBreakWithFollowingIndent commentIndentation indentation
                else
                  let commentIndentation :=
                    spaces
                    <| ({ sourceColumn := sourceFollowingIndent, outputColumn := indent }
                        : Rebase.Anchor).shiftColumn
                        sourceIndent
                  match state.pendingCommandBoundary? with
                  | some spacing =>
                      commentTriviaForBoundary boundary commentIndentation indentation
                        spacing false
                  | none =>
                      boundary.forBreakWithFollowingIndent commentIndentation indentation
          | none =>
              whitespaceForPendingBoundary boundary indentation
                state.pendingCommandBoundary?
        else if state.movePendingCommentAfterToken then
          let movedText := state.movePendingCommentAfterTokenIfFits boundary.cleaned.text
          let movedBoundary := SourceBoundary.ofText movedText
          let sourceFollowingIndent := state.sourceMap.columnAt token.span.start
          let useFollowingTreeAnchor :=
            !movedBoundary.startsOnNewLine
            && (!movedBoundary.beginsMultilineBlockComment || boundary.startsOnNewLine)
          if !useFollowingTreeAnchor then
            let sourceCommentColumn :=
              boundary.firstCommentColumn? <| state.sourceMap.columnAt left.span.stop
            let targetCommentColumn :=
              movedBoundary.firstCommentColumn? <| lineWidth state.currentLine
            movedBoundary.forTreeBoundary
              (sourceCommentColumn.getD 0) (targetCommentColumn.getD 0)
              sourceFollowingIndent indentation
          else
            movedBoundary.forTreeBoundary
              sourceFollowingIndent indentation.length sourceFollowingIndent indentation
        else if boundary.hasComment
                && boundary.hasLineStructure
                && !boundary.startsOnNewLine then
          let cleanedBoundary := boundary.cleaned
          let sourceCommentColumn :=
            boundary.firstCommentColumn? (state.sourceMap.columnAt left.span.stop)
          let targetCommentColumn :=
            cleanedBoundary.firstCommentColumn? (lineWidth state.currentLine)
          let adjusted :=
            cleanedBoundary.forTreeBoundary
              (sourceCommentColumn.getD 0) (targetCommentColumn.getD 0)
              (state.sourceMap.columnAt token.span.start) indentation
          if state.pendingCommandBoundary? == some .blankLine then
            ensureBlankLineBeforeIndentation adjusted indentation
          else
            adjusted
        else if boundary.startsOnNewLine
                && (boundary.hasSeparatedCommentGroups
                    || boundary.endsBeforeBlankLine
                    || (state.pendingCommandBoundary? == some .blankLine
                        && state.sourceMap.columnAt token.span.start
                            == state.layoutAnchor.sourceColumn)) then
          match boundary.standaloneLineCommentIndent? with
          | some sourceCommentIndent =>
              let sourceTokenIndent := state.sourceMap.columnAt token.span.start
              if sourceCommentIndent <= sourceTokenIndent then
                whitespaceForPendingBoundary boundary indentation
                  state.pendingCommandBoundary?
              else
                let belongsToFollowingToken := boundary.startsAfterBlankLine
                let hasExplicitTrailingOwnership :=
                  boundary.hasSeparatedCommentGroups || boundary.endsBeforeBlankLine
                let commentIndent :=
                  if belongsToFollowingToken then
                    indent
                  else if hasExplicitTrailingOwnership then
                    ({ sourceColumn := sourceTokenIndent, outputColumn := indent }
                      : Rebase.Anchor).shiftColumn
                      sourceCommentIndent
                  else
                    state.layoutAnchor.shiftColumn sourceCommentIndent
                let commentIndentation := spaces commentIndent
                match state.pendingCommandBoundary? with
                | some spacing =>
                    commentTriviaForBoundary boundary commentIndentation indentation
                      spacing belongsToFollowingToken
                | none =>
                    boundary.forBreakWithFollowingIndent commentIndentation indentation
          | none =>
              whitespaceForPendingBoundary boundary indentation
                state.pendingCommandBoundary?
        else
          whitespaceForPendingBoundary boundary indentation state.pendingCommandBoundary?
    | none, some indent =>
        let indent := state.indentForMultilineToken token indent
        let indentation := spaces indent
        whitespaceForPendingBoundary (SourceBoundary.beforeToken token) indentation
          state.pendingCommandBoundary?
    | none, none =>
        if (SourceBoundary.beforeToken token).hasComment then
          SpaceRules.reindentCommentTrivia token.leading.text ""
        else
          ""
    | some left, none =>
        SpaceRules.interTokenWhitespace state.source left token preserveLines
  whitespace

def RenderState.defaultWhitespace (state : RenderState) (token : SyntaxTree.Token)
    (preserveLines : Bool := false)
    : String :=
  match state.lastToken?, state.pendingIndent? with
  | some left, none =>
      let normalizeAdjacent :=
        fun _ =>
          state.context.ancestors.any
            fun frame =>
              SyntaxTree.Tree.normalizesStructuralBoundary frame.segment.parent
                frame.childIndex token
      SpaceRules.interTokenWhitespace state.source left token preserveLines
        normalizeAdjacent
  | _, _ => state.whitespaceState.defaultWhitespace token preserveLines

def RenderState.allowsStartAlignment (state : RenderState) : Bool :=
  match state.lastToken?, state.pendingIndent? with
  | some token, none => SpaceRules.allowsHorizontalAlignmentAfterToken token.lexeme
  | _, _ => true

def RenderState.ensureBlankCommandBoundaryBeforeRenderedTree
    (before rendered : RenderState) (tree : SyntaxTree.Tree)
    : RenderState :=
  match SyntaxTree.Tree.firstToken? tree with
  | none => rendered
  | some token =>
      let originalWhitespace := before.defaultWhitespace token
      let blankWhitespace :=
        ({ before with pendingCommandBoundary? := some .blankLine }).defaultWhitespace
          token
      if originalWhitespace == blankWhitespace then
        rendered
      else
        let renderedSuffix := (rendered.output.drop before.output.length).toString
        if !renderedSuffix.startsWith originalWhitespace then
          rendered
        else
          let body := (renderedSuffix.drop originalWhitespace.length).toString
          let addedLineBreaks :=
            Trace.newlineCount blankWhitespace - Trace.newlineCount originalWhitespace
          {
            rendered with
              output := before.output ++ blankWhitespace ++ body
              outputLineBreakCount := rendered.outputLineBreakCount + addedLineBreaks
              trace :=
                rendered.trace.shiftEntriesAfter before.trace.entries.length
                  addedLineBreaks
          }

def RenderState.segmentStartColumn (state : RenderState)
    (segment : LineBreakRules.Segment)
    : Nat :=
  match segmentFirstToken? segment with
  | some token =>
      let whitespace := state.defaultWhitespace token
      lineWidth <| currentLineAfterAppend state.currentLine whitespace
  | none => state.currentColumn

def RenderState.traceSegment
    (state : RenderState) (segment : LineBreakRules.Segment) (ruleName : String)
    : RenderState :=
  if state.trace.enabled then
    {
      state with
        trace :=
          state.trace.recordSegment state.output
            (fun token => state.defaultWhitespace token) segment ruleName
            (state.segmentStartColumn segment) state.currentIndent
            state.segmentIndentation state.pendingIndent? state.tailIndentation?
    }
  else
    state

def RenderState.nextTokenColumn (state : RenderState) (token : SyntaxTree.Token)
    (preserveLines : Bool := false)
    : Nat :=
  let whitespace := state.defaultWhitespace token preserveLines
  lineWidth <| currentLineAfterAppend state.currentLine whitespace

def RenderState.emitToken (state : RenderState) (token : SyntaxTree.Token)
    (preserveLines : Bool := false)
    : RenderState :=
  if token.lexeme.isEmpty then
    state
  else
    let whitespace := state.defaultWhitespace token preserveLines
    let state :=
      if !state.guardedJoins.isEmpty
          && hasLineBreakChar whitespace
          && state.guardedJoins.contains token.span.start.byteIdx then
        { state with brokenJoins := state.brokenJoins.insert token.span.start.byteIdx }
      else
        state
    let state := state.appendTriviaOutput whitespace
    let lexeme :=
      if SpaceRules.isCommentLexeme token.lexeme && hasLineBreakChar token.lexeme then
        SpaceRules.reindentCommentLexeme token.lexeme
          (state.sourceMap.columnAt token.span.start) (lineWidth state.currentLine)
      else
        token.lexeme
    let introducedAtomicOverflow :=
      match state.pendingIndent? with
      | none => false
      | some _ =>
          let tokenWidth := (firstLineAppendWidth token.lexeme).1
          let outputColumn := lineWidth state.currentLine
          if state.options.lineWidth < outputColumn + tokenWidth then
            let sourceLeading :=
              match state.lastToken? with
              | some leftToken =>
                  SyntaxTree.sourceText state.source leftToken.span.stop token.span.start
              | none => token.leading.text
            let sourceColumn :=
              if SpaceRules.hasLineStructure sourceLeading then
                lineWidth <| charsAfterLastNewline sourceLeading
              else
                state.sourceMap.columnAt token.span.start
            sourceColumn + tokenWidth <= state.options.lineWidth
          else
            false
    {
      state.appendOutput lexeme with
        introducedAtomicOverflowCount :=
          state.introducedAtomicOverflowCount + if introducedAtomicOverflow then 1 else 0
        lastToken? := some token
        pendingIndent? := none
        pendingCommandBoundary? := none
        preserveNextStandaloneCommentIndent := false
        movePendingCommentAfterToken := false
    }

def RenderState.withPendingIndent (state : RenderState) (indent : Nat) : RenderState :=
  {
    state with
      pendingIndent? := some indent
      pendingCommandBoundary? := none
      movePendingCommentAfterToken := false
      tailIndentation? := none
      segmentBaseColumn := indent
      segmentIndentation := indentationLevelForColumn indent
  }

def RenderState.withCommentBoundaryIndent
    (state : RenderState) (indent : Nat) (moveCommentAfterToken : Bool)
    : RenderState :=
  {
    state with
      pendingIndent? := some indent
      pendingCommandBoundary? := none
      movePendingCommentAfterToken := moveCommentAfterToken
      tailIndentation? := none
  }

def breakIndent (baseColumn baseIndentation : Nat)
    (breakPoint : LineBreakRules.BreakPoint)
    : Nat :=
  if breakPoint.indentLevels == 0 then
    max (indentationPastColumn baseColumn) (baseIndentation * indentationSpaces)
  else
    (baseIndentation + breakPoint.indentLevels) * indentationSpaces

def RenderState.withRuleBreakIndent
    (state : RenderState) (baseColumn baseIndentation : Nat)
    (breakPoint : LineBreakRules.BreakPoint)
    : RenderState :=
  state.withPendingIndent (breakIndent baseColumn baseIndentation breakPoint)

def outputIntroducedLineBreak (before after : RenderState) : Bool :=
  before.outputLineBreakCount < after.outputLineBreakCount

def renderedCandidateFits (before after : RenderState) : Bool :=
  before.completedLineOverflowCount == after.completedLineOverflowCount
  && lineFitsWithTrailingWidth after.currentLine after.lineFitSuffixWidth
      after.options.lineWidth

def renderedOverflowCount (before after : RenderState) : Nat :=
  let completed := after.completedLineOverflowCount - before.completedLineOverflowCount
  let current :=
    if lineFitsWithTrailingWidth after.currentLine after.lineFitSuffixWidth
        after.options.lineWidth then
      0
    else
      1
  completed + current

def renderedOutputOverflowCount (before after : RenderState) : Nat :=
  renderedOverflowCount before { after with lineFitSuffixWidth := 0 }

def preferCandidateWithFewerOverflows (before current candidate : RenderState)
    : RenderState :=
  if renderedOverflowCount before candidate < renderedOverflowCount before current then
    candidate
  else
    current

def atomicTreeIntroducedOverflow (before after : RenderState) (tree : SyntaxTree.Tree)
    : Bool :=
  after.introducedAtomicOverflowCount == before.introducedAtomicOverflowCount
  && 0 < renderedOverflowCount before after
  && match tree.firstToken?, treeFirstSourceLineWidth? before.source tree with
      | some firstToken, some firstLineWidth =>
          before.sourceMap.columnAt firstToken.span.start + firstLineWidth
          <= before.options.lineWidth
      | _, _ => false

def RenderState.segmentStartBaseFor
    (state : RenderState) (segment : LineBreakRules.Segment)
    : SegmentBase :=
  let column :=
    match segmentFirstToken? segment with
    | some token => state.nextTokenColumn token
    | none => state.currentColumn
  { column, indentation := indentationLevelForColumn column }

def RenderState.sourceLayoutStart? (state : RenderState) (tree : SyntaxTree.Tree)
    : Option (Nat × Nat) := do
  let first ← tree.firstToken?
  let leading :=
    match state.lastToken? with
    | some left => SyntaxTree.sourceText state.source left.span.stop first.span.start
    | none => first.leading.text
  if state.lastToken?.isNone || SpaceRules.hasLineStructure leading then
    let column := lineWidth <| charsAfterLastNewline leading
    some (column, state.layoutAnchor.shiftColumn column)
  else
    none

def RenderState.withChildPlacement (state : RenderState)
    (segment : LineBreakRules.Segment) (plan : LayoutPlan.Plan)
    : RenderState :=
  let base :=
    if plan.inheritsBase then
      let indentation :=
        if plan.roundsUpBase then
          max state.segmentIndentation
            (state.pendingIndent?.map indentationLevelForColumn
              |>.getD state.segmentIndentation)
        else
          state.segmentIndentation
      {
        column :=
          if indentation == state.segmentIndentation then
            state.segmentBaseColumn
          else
            indentation * indentationSpaces
        indentation
      }
    else
      state.segmentStartBaseFor segment
  let layoutAnchor :=
    match state.sourceLayoutStart? segment.parent with
    | some (sourceColumn, _) =>
        let startsOnNewOutputLine :=
          segmentFirstToken? segment
          |>.any fun token => SpaceRules.hasLineStructure (state.defaultWhitespace token)
        if plan.inheritsBase && !startsOnNewOutputLine then
          state.layoutAnchor
        else
          { sourceColumn, outputColumn := state.segmentStartColumn segment }
    | none => state.layoutAnchor
  {
    state with
      segmentBaseColumn := base.column
      segmentIndentation := base.indentation
      layoutAnchor
  }

def renderedTreeIsMultiline (before after : RenderState) (tree : SyntaxTree.Tree)
    : Bool :=
  let leadingBreakCount :=
    match SyntaxTree.Tree.firstToken? tree with
    | some token =>
        let whitespace := before.defaultWhitespace token
        if hasLineBreakChar whitespace then
          (appendedLines "" whitespace before.options.lineWidth).lineBreakCount
        else
          0
    | none => 0
  before.outputLineBreakCount + leadingBreakCount < after.outputLineBreakCount

def renderedSegmentIsMultiline
    (before after : RenderState) (segment : LineBreakRules.Segment)
    : Bool :=
  let leadingBreakCount :=
    match segmentFirstToken? segment with
    | some token =>
        let whitespace := before.defaultWhitespace token
        if hasLineBreakChar whitespace then
          (appendedLines "" whitespace before.options.lineWidth).lineBreakCount
        else
          0
    | none => 0
  before.outputLineBreakCount + leadingBreakCount < after.outputLineBreakCount

def RenderState.forFitProbe (state : RenderState) : RenderState :=
  {
    state with
      output := ""
      outputLineBreakCount := 0
      completedLineOverflowCount := 0
      introducedAtomicOverflowCount := 0
  }

def RenderState.hasBlankBoundaryBefore (state : RenderState) (tree : SyntaxTree.Tree)
    : Bool :=
  match state.lastToken?, SyntaxTree.Tree.firstToken? tree with
  | some left, some right =>
      let trivia := SyntaxTree.sourceText state.source left.span.stop right.span.start
      hasBlankLineStructure trivia
  | _, _ => false

def RenderState.emitOriginalTree
    (state : RenderState) (tree : SyntaxTree.Tree)
    (formatLeadingBoundary : Bool := false)
    (respectPendingIndent : Bool := false)
    (rebaseSourceTextTargetColumn? : Option Nat := none)
    (islandPlan? : Option OriginalTree.IslandPlan := none)
    : RenderState :=
  let formattedLeadingWhitespace? :=
    if formatLeadingBoundary
        || islandPlan?.any
            fun plan => plan.policy.leadingBoundary == .formatStructurally then
      SyntaxTree.Tree.firstToken? tree
      |>.map fun firstToken => state.defaultWhitespace firstToken
    else
      none
  let formattedLeadingTargetColumn? :=
    formattedLeadingWhitespace?.map
      fun whitespace => lineWidth <| currentLineAfterAppend state.currentLine whitespace
  let request : OriginalTree.EmissionRequest :=
    {
      source := state.source
      sourceMap := state.sourceMap
      currentLine := state.currentLine
      currentIndent := state.currentIndent
      lastToken? := state.lastToken?
      formattedLeadingWhitespace?
      pendingLeadingWhitespace? :=
        state.pendingIndent?.map
          fun _ =>
            match SyntaxTree.Tree.firstToken? tree with
            | some firstToken => state.defaultWhitespace firstToken true
            | none => ""
      segmentIndentation := state.segmentIndentation
      layoutAnchor := state.layoutAnchor
      lineWidth := state.options.lineWidth
      lineFitSuffixWidth := state.lineFitSuffixWidth
      respectPendingIndent
      rebaseSourceTextTargetColumn? :=
        rebaseSourceTextTargetColumn?.orElse fun _ => formattedLeadingTargetColumn?
    }
  match OriginalTree.emit? request tree islandPlan? with
  | some emission =>
      {
        state.appendOutput emission.text with
          lastToken? := some emission.lastToken
          pendingIndent? := none
          pendingCommandBoundary? := none
          movePendingCommentAfterToken := false
          preserveNextStandaloneCommentIndent :=
            emission.preserveNextStandaloneCommentIndent
      }
  | none => state

def treeSourceHasLineStructure (source : String) (tree : SyntaxTree.Tree) : Bool :=
  match SyntaxTree.Tree.firstToken? tree, SyntaxTree.Tree.lastToken? tree with
  | some firstToken, some lastToken =>
      SpaceRules.hasLineStructure
        (SyntaxTree.sourceText source firstToken.span.start lastToken.span.stop)
  | _, _ => false

private def treeLayoutSummary
    (source : String) (tree : SyntaxTree.Tree)
    (facts? : Option TreeLayoutFacts := none)
    : TreeLayoutSummary :=
  match facts? with
  | some facts => facts.summary
  | none => (TreeLayoutFacts.ofTree source tree).summary

private def originalPlanForTree
    (source : String) (tree : SyntaxTree.Tree)
    (facts? : Option TreeLayoutFacts := none)
    : Option OriginalTree.IslandPlan :=
  (treeLayoutSummary source tree facts?).originalPlan?

private def segmentContainsMultilineOriginalEmission
    (source : String) (segment : LineBreakRules.Segment)
    (facts? : Option TreeLayoutFacts := none)
    : Bool :=
  let facts :=
    match facts? with
    | some facts => facts
    | none => TreeLayoutFacts.ofTree source segment.parent
  let .node _ children := facts
  TreeLayoutFacts.childrenContainMultilineOriginalEmission source children
    segment.start segment.stop

def childHasPriorContent (segment : LineBreakRules.Segment) (index : Nat) : Bool :=
  segment.indexes.any
    fun childIndex =>
      childIndex < index && (segment.child? childIndex).any LineBreakRules.treeHasContent

partial def ancestorFormatsLeadingBoundary (context : LineBreakRules.RuleContext)
    : Bool :=
  match context.ancestors with
  | [] => false
  | frame :: ancestors =>
      let parentContext : LineBreakRules.RuleContext := { ancestors }
      let parentPlan := LayoutPlan.resolve parentContext frame.segment
      if parentPlan.formatsOriginalLeadingBoundary frame.childIndex then
        true
      else if childHasPriorContent frame.segment frame.childIndex then
        false
      else
        ancestorFormatsLeadingBoundary parentContext

def formatOriginalChildLeadingBoundary
    (context : LineBreakRules.RuleContext) (segment : LineBreakRules.Segment)
    (index : Nat)
    : Bool :=
  let plan := LayoutPlan.resolve context segment
  plan.formatsOriginalLeadingBoundary index
  || (!childHasPriorContent segment index && ancestorFormatsLeadingBoundary context)

def hasRuleBreakAt
    (context : LineBreakRules.RuleContext) (segment : LineBreakRules.Segment)
    (index : Nat)
    : Bool :=
  (LayoutPlan.resolve context segment).hasBreakAt index

def naturalRuleBreakBase
    (plan : LayoutPlan.Plan)
    (baseColumn baseIndentation : Nat)
    (breakPoint : LineBreakRules.BreakPoint)
    : SegmentBase :=
  let naturalIndentation :=
    if plan.roundsUpBase && 0 < breakPoint.indentLevels then
      max baseIndentation (indentationLevelForColumn (indentationPastColumn baseColumn))
    else
      baseIndentation
  { column := baseColumn, indentation := naturalIndentation }

def naturalBreakIndentation
    (plan : LayoutPlan.Plan)
    (baseColumn baseIndentation : Nat)
    (breakPoint : LineBreakRules.BreakPoint)
    : Nat :=
  let base := naturalRuleBreakBase plan baseColumn baseIndentation breakPoint
  indentationLevelForColumn <| breakIndent base.column base.indentation breakPoint

def leastNaturalBreakIndentation?
    (plan : LayoutPlan.Plan)
    (baseColumn baseIndentation : Nat)
    : List LineBreakRules.BreakPoint → Option Nat
  | [] => none
  | breakPoint :: rest =>
      let indentation :=
        naturalBreakIndentation plan baseColumn baseIndentation breakPoint
      match leastNaturalBreakIndentation? plan baseColumn baseIndentation rest with
      | some minimum => some (min indentation minimum)
      | none => some indentation

def requiredTailIndentation (plan : LayoutPlan.Plan) (baseColumn tailIndentation : Nat)
    : Nat :=
  if plan.liftsTail || plan.isFlow then
    let headIndentation := indentationLevelForColumn (indentationPastColumn baseColumn)
    max headIndentation (tailIndentation + 1)
  else
    tailIndentation

def computeRuleBreakShift
    (state : RenderState) (plan : LayoutPlan.Plan)
    (baseColumn baseIndentation : Nat)
    (points : List LineBreakRules.BreakPoint)
    : Nat :=
  match state.tailIndentation? with
  | some tailIndentation =>
      let required := requiredTailIndentation plan baseColumn tailIndentation
      let minimum? := leastNaturalBreakIndentation? plan baseColumn baseIndentation points
      required - minimum?.getD required
  | none => 0

def ruleBreakBase
    (state : RenderState) (_segment : LineBreakRules.Segment)
    (plan : LayoutPlan.Plan)
    (baseColumn baseIndentation : Nat)
    (breakPoint : LineBreakRules.BreakPoint)
    : SegmentBase :=
  let base := naturalRuleBreakBase plan baseColumn baseIndentation breakPoint
  let shiftedIndentation :=
    if breakPoint.indentLevels == 0 then
      indentationLevelForColumn (breakIndent base.column base.indentation breakPoint)
      + state.breakIndentationShift
    else
      base.indentation + state.breakIndentationShift
  { base with indentation := shiftedIndentation }

def breakPointIndent
    (state : RenderState) (segment : LineBreakRules.Segment)
    (plan : LayoutPlan.Plan)
    (breakPoint : LineBreakRules.BreakPoint)
    : Nat :=
  let baseIndentation := state.segmentIndentation
  let baseColumn :=
    if baseIndentation == state.segmentIndentation then
      state.segmentBaseColumn
    else
      baseIndentation * indentationSpaces
  let base := ruleBreakBase state segment plan baseColumn baseIndentation breakPoint
  breakIndent base.column base.indentation breakPoint

/-! ## Flat rendering and fit measurement -/

def childRetainsRuleSourceBreak (source : String) (segment : LineBreakRules.Segment)
    (index : Nat) (facts? : Option TreeLayoutFacts)
    : Bool :=
  match segment.child? index with
  | none => false
  | some child =>
      (treeLayoutSummary source child facts?).startsWithRetainedOriginalBoundary
      && (match LineBreakRules.previousContentIndex? segment index
                >>= segment.child?
                >>= SyntaxTree.Tree.lastToken?, child.firstToken? with
          | some left, some right =>
              SpaceRules.hasLineStructure
                (SyntaxTree.sourceText source left.span.stop right.span.start)
          | _, _ => false)

def RenderState.retainedChildBoundary? (state entryState : RenderState)
    (segment : LineBreakRules.Segment) (index : Nat)
    (facts? : Option TreeLayoutFacts)
    : Option RenderState :=
  if childRetainsRuleSourceBreak state.source segment index facts? then
    let plan := LayoutPlan.resolve entryState.context segment
    match plan.breakPoints.find?
            (fun point =>
              point.index == index && !plan.formatsOriginalLeadingBoundary index) with
    | some point =>
        let placement :=
          if segment.start == 0 then
            entryState.withChildPlacement segment plan
          else
            entryState
        some <| state.withPendingIndent (breakPointIndent placement segment plan point)
    | none => none
  else
    none

partial def renderWithoutRuleBreaks
    (state : RenderState) (segment : LineBreakRules.Segment)
    : RenderState :=
  match segment.parent with
  | .missing => state
  | .leaf token => state.emitToken token false
  | .node _ _ =>
      let entryState := state
      segment.indexes.foldl
        (fun state index =>
          match segment.child? index with
          | some child =>
              let scope := ChildRenderScope.capture state
              let parentContext := state.context
              let parentFacts? := state.layoutFacts?
              let childFacts? := parentFacts? >>= (·.child? index)
              let state :=
                (state.retainedChildBoundary? entryState segment index childFacts?).getD
                  state
              let rendered :=
                match originalPlanForTree state.source child childFacts? with
                | some islandPlan =>
                    state.emitOriginalTree child
                      (formatLeadingBoundary :=
                        formatOriginalChildLeadingBoundary parentContext segment index)
                      (islandPlan? := some islandPlan)
                | none =>
                    renderWithoutRuleBreaks
                      {
                        state with
                          context := parentContext.push segment index
                          layoutFacts? := childFacts?
                      }
                      (LineBreakRules.Segment.ofTree child)
              scope.restore rendered
          | none => state)
        state

def layoutProbeHasNotOverflowed (state : RenderState) : Bool :=
  state.completedLineOverflowCount == 0
  && lineFits state.currentLine state.options.lineWidth

private partial def probeLayoutWithoutRuleBreaksCore?
    (state : RenderState) (segment : LineBreakRules.Segment)
    (checkWidth : Bool)
    : Option (RenderState × Bool) :=
  match segment.parent with
  | .missing => some (state, false)
  | .leaf token =>
      let rendered := state.emitToken token false
      if !checkWidth || layoutProbeHasNotOverflowed rendered then
        some (rendered, false)
      else
        none
  | .node _ _ =>
      let entryState := state
      let rec loop (state : RenderState) (retainedBreak : Bool)
          : List Nat → Option (RenderState × Bool)
        | [] => some (state, retainedBreak)
        | index :: rest =>
            match segment.child? index with
            | none => loop state retainedBreak rest
            | some child =>
                let scope := ChildRenderScope.capture state
                let parentContext := state.context
                let parentFacts? := state.layoutFacts?
                let childFacts? := parentFacts? >>= (·.child? index)
                let boundary? :=
                  state.retainedChildBoundary? entryState segment index childFacts?
                let state := boundary?.getD state
                let renderChild (state : RenderState) :=
                  match originalPlanForTree state.source child childFacts? with
                  | some islandPlan =>
                      let rendered :=
                        state.emitOriginalTree child
                          (formatLeadingBoundary :=
                            formatOriginalChildLeadingBoundary parentContext segment
                              index)
                          (islandPlan? := some islandPlan)
                      if !checkWidth || layoutProbeHasNotOverflowed rendered then
                        some (rendered, false)
                      else
                        none
                  | none =>
                      probeLayoutWithoutRuleBreaksCore?
                        {
                          state with
                            context := parentContext.push segment index
                            layoutFacts? := childFacts?
                        }
                        (LineBreakRules.Segment.ofTree child) checkWidth
                let rendered? := renderChild state
                -- Retry only the body at its retained boundary; the prefix already fits.
                let retryState? :=
                  if rendered?.isNone
                      && checkWidth
                      && boundary?.isNone
                      && childRetainsRuleSourceBreak state.source segment index
                          childFacts? then do
                    let plan := LayoutPlan.resolve entryState.context segment
                    let point ←
                      plan.breakPoints.find?
                        fun point =>
                          point.index == index
                          && point.indentLevels > 0
                          && plan.keepsPrefixWithChildFirstLine index
                    let placement := entryState.withChildPlacement segment plan
                    some
                      (state.withPendingIndent
                        (breakPointIndent placement segment plan point))
                  else
                    none
                let rendered? := rendered?.orElse fun _ => retryState? >>= renderChild
                match rendered? with
                | some (rendered, childRetainedBreak) =>
                    loop (scope.restore rendered)
                      (retainedBreak
                        || boundary?.isSome
                        || retryState?.isSome
                        || childRetainedBreak) rest
                | none => none
      let rendered? := loop state false segment.indexes
      rendered?.filter
        fun (_, retainedBreak) =>
          !retainedBreak
          || !((LayoutPlan.resolve state.context segment).breakPoints.any
                (·.indentLevels == 0))

def probeLayoutWithoutRuleBreaks? (state : RenderState) (segment : LineBreakRules.Segment)
    : Option RenderState :=
  (probeLayoutWithoutRuleBreaksCore? state segment true).map (·.1)

def currentLineFitsWith (state : RenderState) (suffix : String) : Bool :=
  !introducesCompletedLineOverflow state.currentLine suffix state.options.lineWidth
  && lineFitsWithTrailingWidth
      (currentLineAfterAppend state.currentLine suffix) state.lineFitSuffixWidth
      state.options.lineWidth

def firstLineWithBreakFlag (text : String) : String × Bool :=
  let rec loop : List Char → List Char → String × Bool
    | [], current => (String.ofList current.reverse, false)
    | '\n' :: _, current => (String.ofList current.reverse, true)
    | char :: rest, current => loop rest (char :: current)
  loop (SpaceRules.normalizeLineEndings text).toList []

def RenderState.withoutLineFitSuffix (state : RenderState) : RenderState :=
  { state with lineFitSuffixWidth := 0 }

partial def firstTokenWithContext?
    (context : LineBreakRules.RuleContext) (tree : SyntaxTree.Tree)
    : Option (LineBreakRules.RuleContext × SyntaxTree.Token) :=
  match tree with
  | .missing => none
  | .leaf token => if token.lexeme.isEmpty then none else some (context, token)
  | .node _ _ =>
      let segment := LineBreakRules.Segment.ofTree tree
      segment.indexes.findSome?
        fun index =>
          segment.child? index >>= firstTokenWithContext? (context.push segment index)

def suffixMayContinueAcrossRuleBreak (context : LineBreakRules.RuleContext)
    (segment : LineBreakRules.Segment) (index : Nat)
    : Bool :=
  match segment.child? index >>= SyntaxTree.Tree.firstToken? with
  | some token =>
      LineBreakRules.suffixTokenAction (context.push segment index) token == .emit
  | none => false

def treeStartsWithStructuralSuffix (tree : SyntaxTree.Tree) : Bool :=
  match firstTokenWithContext? {} tree with
  | some (context, token) =>
      LineBreakRules.suffixTokenAction context token == .emit
      && LineBreakRules.suffixTokenAction { ancestors := [] } token != .emit
  | none => false

def groupedSuffixMayContinueAcrossRuleBreak
    (segment : LineBreakRules.Segment) (index : Nat)
    : Bool :=
  match segment.child? index with
  | some child@(.node _ _) =>
      treeStartsWithStructuralSuffix child
  | _ => false

def WhitespaceState.appendText (state : WhitespaceState) (text : String)
    : WhitespaceState :=
  { state with currentLine := currentLineAfterAppend state.currentLine text }

def WhitespaceState.hasBlankBoundaryBefore
    (state : WhitespaceState) (tree : SyntaxTree.Tree)
    : Bool :=
  match state.lastToken?, SyntaxTree.Tree.firstToken? tree with
  | some left, some right =>
      let trivia := SyntaxTree.sourceText state.source left.span.stop right.span.start
      hasBlankLineStructure trivia
  | _, _ => false

def WhitespaceState.afterToken (state : WhitespaceState) (token : SyntaxTree.Token)
    : WhitespaceState :=
  {
    state with
      lastToken? := some token
      pendingIndent? := none
      movePendingCommentAfterToken := false
  }

def WhitespaceState.afterFlatTreeForSuffix
    (state : WhitespaceState) (tree : SyntaxTree.Tree)
    : WhitespaceState :=
  match SyntaxTree.Tree.lastToken? tree with
  | some token => state.afterToken token
  | none => state

structure SuffixState where
  whitespaceState : WhitespaceState
  suffixWidth : Nat
  delimiterDepth : Nat := 0

def SuffixState.appendText (state : SuffixState) (text : String) : SuffixState × Bool :=
  let (addedWidth, stopped) := firstLineAppendWidth text
  let whitespaceState :=
    if stopped then
      state.whitespaceState
    else
      state.whitespaceState.appendText text
  ({ whitespaceState, suffixWidth := state.suffixWidth + addedWidth }, stopped)

def SuffixState.emitToken (state : SuffixState) (token : SyntaxTree.Token)
    (preserveLines : Bool := false)
    : SuffixState × Bool :=
  if token.lexeme.isEmpty then
    (state, false)
  else
    let text :=
      state.whitespaceState.defaultWhitespace token preserveLines ++ token.lexeme
    let (state, stopped) := state.appendText text
    let delimiterDepth := LayoutPlan.suffixDelimiterDepthAfter state.delimiterDepth token
    (
      {
        state with
          whitespaceState := state.whitespaceState.afterToken token
          delimiterDepth
      },
      stopped
    )

def SuffixState.appendCommentTriviaBeforeToken
    (state : SuffixState) (token : SyntaxTree.Token)
    : SuffixState :=
  let trivia :=
    match state.whitespaceState.lastToken? with
    | some left =>
        SyntaxTree.sourceText state.whitespaceState.source left.span.stop token.span.start
    | none => token.leading.text
  let boundary := SourceBoundary.ofText trivia
  if boundary.hasComment && !boundary.startsOnNewLine then
    (state.appendText (state.whitespaceState.defaultWhitespace token false)).1
  else
    state

def SuffixState.appendCommentTriviaBeforeTree
    (state : SuffixState) (tree : SyntaxTree.Tree)
    : SuffixState :=
  match SyntaxTree.Tree.firstToken? tree with
  | some token => state.appendCommentTriviaBeforeToken token
  | none => state

def SuffixState.emitOriginalFirstLine (state : SuffixState) (tree : SyntaxTree.Tree)
    : SuffixState × Bool :=
  match SyntaxTree.Tree.firstToken? tree, SyntaxTree.Tree.lastToken? tree with
  | some firstToken, some lastToken =>
      let text :=
        state.whitespaceState.defaultWhitespace firstToken true
        ++ SyntaxTree.sourceText state.whitespaceState.source firstToken.span.start
            lastToken.span.stop
      let (state, stopped) := state.appendText text
      let state :=
        if stopped then
          state
        else
          { state with whitespaceState := state.whitespaceState.afterToken lastToken }
      (state, stopped)
  | _, _ => (state, false)

partial def measureSuffixOfTree
    (context : LineBreakRules.RuleContext) (state : SuffixState)
    (tree : SyntaxTree.Tree)
    (facts? : Option TreeLayoutFacts := none)
    : SuffixState × Bool :=
  match tree with
  | .missing => (state, false)
  | .leaf token =>
      if 0 < state.delimiterDepth then
        state.emitToken token false
      else
        match LineBreakRules.suffixTokenAction context token with
        | .skip => (state, false)
        | .emit => state.emitToken token false
        | .stop => (state.appendCommentTriviaBeforeToken token, true)
  | .node _ _ =>
      if (originalPlanForTree state.whitespaceState.source tree facts?).isSome then
        state.emitOriginalFirstLine tree
      else
        let segment := LineBreakRules.Segment.ofTree tree
        let plan := LayoutPlan.resolve context segment
        segment.indexes.foldl
          (fun (state, stopped) index =>
            if stopped then
              (state, true)
            else
              match segment.child? index with
              | none => (state, false)
              | some child =>
                  if segment.start < index
                      && plan.hasBreakAt index
                      && (plan.isMandatory
                          || !suffixMayContinueAcrossRuleBreak context segment index) then
                    (state.appendCommentTriviaBeforeTree child, true)
                  else
                    let childContext := context.push segment index
                    measureSuffixOfTree childContext state child
                      (facts? >>= (·.child? index)))
          (state, false)

def RenderState.firstLineOfOriginalTree (state : RenderState) (tree : SyntaxTree.Tree)
    : RenderState × Bool :=
  match SyntaxTree.Tree.firstToken? tree, SyntaxTree.Tree.lastToken? tree with
  | some firstToken, some lastToken =>
      let emitted :=
        state.defaultWhitespace firstToken
        ++ SyntaxTree.sourceText state.source firstToken.span.start lastToken.span.stop
      let (firstLine, stopped) := firstLineWithBreakFlag emitted
      (
        {
          state.appendOutput firstLine with
            lastToken? := some lastToken
            pendingIndent? := none
            pendingCommandBoundary? := none
            movePendingCommentAfterToken := false
        },
        stopped
      )
  | _, _ => (state, false)

partial def renderFirstLineOfTree (state : RenderState) (tree : SyntaxTree.Tree)
    : RenderState × Bool :=
  match tree with
  | .missing => (state, false)
  | .leaf token =>
      if token.lexeme.isEmpty then
        (state, false)
      else
        let emitted := state.defaultWhitespace token false ++ token.lexeme
        let (firstLine, stopped) := firstLineWithBreakFlag emitted
        (
          {
            state.appendOutput firstLine with
              lastToken? := some token
              pendingIndent? := none
              pendingCommandBoundary? := none
              movePendingCommentAfterToken := false
          },
          stopped
        )
  | .node _ _ =>
      if (originalPlanForTree state.source tree state.layoutFacts?).isSome then
        state.firstLineOfOriginalTree tree
      else
        let segment := LineBreakRules.Segment.ofTree tree
        segment.indexes.foldl
          (fun (state, stopped) index =>
            if stopped then
              (state, true)
            else
              match segment.child? index with
              | none => (state, false)
              | some child =>
                  if segment.start < index
                      && hasRuleBreakAt state.context segment index then
                    (state, true)
                  else
                    let childContext := state.context.push segment index
                    let (rendered, stopped) :=
                      renderFirstLineOfTree
                        {
                          state with
                            context := childContext
                            layoutFacts? := state.layoutFacts? >>= (·.child? index)
                        }
                        child
                    (
                      {
                        rendered with
                          context := state.context, layoutFacts? := state.layoutFacts?
                      },
                      stopped
                    ))
          (state.withoutLineFitSuffix, false)

partial def lineFitSuffixAfterChild
    (state : RenderState) (segment : LineBreakRules.Segment) (index : Nat)
    (child : SyntaxTree.Tree)
    : Nat × Bool :=
  let afterChild := state.whitespaceState.afterFlatTreeForSuffix child
  let context := state.context
  let rec loop (suffixState : SuffixState) (nextIndex : Nat) : SuffixState × Bool :=
    if nextIndex < segment.stop then
      match segment.child? nextIndex with
      | some nextChild =>
          if suffixState.whitespaceState.hasBlankBoundaryBefore nextChild then
            (suffixState.appendCommentTriviaBeforeTree nextChild, false)
          else
            let childContext := context.push segment nextIndex
            let (rendered, stopped) :=
              measureSuffixOfTree childContext suffixState nextChild
                (state.layoutFacts? >>= (·.child? nextIndex))
            if stopped then (rendered, false) else loop rendered (nextIndex + 1)
      | none => loop suffixState (nextIndex + 1)
    else
      let suffixState :=
        match segment.parentChild? segment.stop with
        | some nextChild => suffixState.appendCommentTriviaBeforeTree nextChild
        | none => suffixState
      (suffixState, true)
  let (suffixState, reachedEnd) :=
    loop { whitespaceState := afterChild, suffixWidth := 0 } (index + 1)
  (suffixState.suffixWidth, reachedEnd)

def firstRuleBreakAfter
    (context : LineBreakRules.RuleContext) (segment : LineBreakRules.Segment)
    (index suffixStop : Nat)
    : Nat :=
  let plan := LayoutPlan.resolve context segment
  plan.breakPoints.foldl
    (fun stop breakPoint =>
      if index < breakPoint.index
          && breakPoint.index < stop
          && !suffixMayContinueAcrossRuleBreak context segment breakPoint.index
          && !groupedSuffixMayContinueAcrossRuleBreak segment breakPoint.index then
        breakPoint.index
      else
        stop)
    suffixStop

def lineFitSuffixForChild
    (state : RenderState) (segment : LineBreakRules.Segment) (index suffixStop : Nat)
    (child : SyntaxTree.Tree)
    : Nat :=
  let suffixStop := firstRuleBreakAfter state.context segment index suffixStop
  let suffixSegment := segment.slice segment.start suffixStop
  let (localSuffix, reachedEnd) := lineFitSuffixAfterChild state suffixSegment index child
  let inheritedSuffix :=
    if suffixStop == segment.stop && reachedEnd then
      state.lineFitSuffixWidth
    else
      0
  localSuffix + inheritedSuffix

/-! ## Source-break discovery -/

structure SourceBreakLayout where
  segment : LineBreakRules.Segment
  breaks : List SourceBreak

def SourceBreakLayout.breakAt? (layout : SourceBreakLayout) (index : Nat)
    : Option SourceBreak :=
  layout.breaks.find? fun sourceBreak => sourceBreak.index == index

def SourceBreakLayout.nextBreakIndex (layout : SourceBreakLayout) (index : Nat) : Nat :=
  match layout.breaks.find? fun sourceBreak => index < sourceBreak.index with
  | some sourceBreak => sourceBreak.index
  | none => layout.segment.stop

def hasSourceBreakBetweenTokens
    (source : String) (leftToken rightToken : SyntaxTree.Token)
    : Bool :=
  let trivia := SyntaxTree.sourceText source leftToken.span.stop rightToken.span.start
  SpaceRules.hasLineStructure trivia

def sourceBreaksInSegment (source : String) (segment : LineBreakRules.Segment)
    : List SourceBreak :=
  match segment.children? with
  | none => []
  | some children =>
      let step (state : Option SyntaxTree.Token × List SourceBreak) (index : Nat) :=
        let (left?, breaks) := state
        let break? :=
          if segment.start < index then
            match left?, children[index]? >>= SyntaxTree.Tree.firstToken? with
            | some left, some right =>
                if hasSourceBreakBetweenTokens source left right then
                  some { index, indent := 0 }
                else
                  none
            | _, _ => none
          else
            none
        let left? :=
          match children[index]? >>= SyntaxTree.Tree.lastToken? with
          | some token => some token
          | none => left?
        let breaks :=
          match break? with
          | some sourceBreak => sourceBreak :: breaks
          | none => breaks
        (left?, breaks)
      let (_, breaks) := (List.range segment.stop).foldl step (none, [])
      breaks.reverse

def commentForcesBreakAt
    (source : String) (segment : LineBreakRules.Segment) (index : Nat)
    : Bool :=
  match LayoutPlan.tokenBoundaryAt? segment index with
  | some (left, right) =>
      (SourceBoundary.betweenTokens source left right).commentForcesBreak
  | none => false

def treeContainsCommentForcedBreak
    (source : String) (tree : SyntaxTree.Tree)
    (facts? : Option TreeLayoutFacts := none)
    : Bool :=
  (treeLayoutSummary source tree facts?).containsCommentForcedBreak

def treeContainsLineCommentForcedBreak (source : String) (tree : SyntaxTree.Tree)
    (facts? : Option TreeLayoutFacts := none)
    : Bool :=
  (treeLayoutSummary source tree facts?).containsLineCommentForcedBreak

def commentTriviaBeforeTree? (state : RenderState) (tree : SyntaxTree.Tree)
    : Option String := do
  let left ← state.lastToken?
  let right ← tree.firstToken?
  let boundary := SourceBoundary.betweenTokens state.source left right
  if boundary.hasComment then
    some boundary.text
  else
    none

def sourceBreaksAllowedByBreakPoints
    (source : String) (segment : LineBreakRules.Segment)
    (breakPoints : List LineBreakRules.BreakPoint)
    : List SourceBreak :=
  (sourceBreaksInSegment source segment).filter
    fun sourceBreak =>
      breakPoints.any fun breakPoint => breakPoint.index == sourceBreak.index

def childStartsWithCommentedDelimiter
    (source : String) (segment : LineBreakRules.Segment) (index : Nat)
    : Bool :=
  match segment.child? index with
  | some child =>
      match child.tokens.toList.filter (SyntaxTree.tokenComesFromSource source) with
      | opening :: next :: _ =>
          let boundary := SourceBoundary.betweenTokens source opening next
          child.startsWithOpeningDelimiter
          && boundary.hasComment
          && boundary.hasLineStructure
      | _ => false
  | none => false

def sourceBrokenCommentedDelimiterAt
    (source : String) (segment : LineBreakRules.Segment) (index : Nat)
    : Bool :=
  match LayoutPlan.tokenBoundaryAt? segment index with
  | some (left, right) =>
      hasSourceBreakBetweenTokens source left right
      && childStartsWithCommentedDelimiter source segment index
  | none => false

def sourceBreakBeforeSegmentStart? (state : RenderState)
    (segment : LineBreakRules.Segment)
    : Option SourceBreak := do
  let left ← state.lastToken?
  let right ← segmentFirstToken? segment
  let trivia := SyntaxTree.sourceText state.source left.span.stop right.span.start
  if SpaceRules.hasLineStructure trivia then
    some { index := segment.start, indent := 0 }
  else
    none

def sourceBreaksAllowedByBreakPointsInState
    (state : RenderState) (segment : LineBreakRules.Segment)
    (breakPoints : List LineBreakRules.BreakPoint)
    : List SourceBreak :=
  let sourceBreaks := sourceBreaksAllowedByBreakPoints state.source segment breakPoints
  if breakPoints.any fun breakPoint => breakPoint.index == segment.start then
    match sourceBreakBeforeSegmentStart? state segment with
    | some sourceBreak => sourceBreak :: sourceBreaks
    | none => sourceBreaks
  else
    sourceBreaks

def segmentHasAllowedSourceBreaks
    (source : String) (context : LineBreakRules.RuleContext)
    (segment : LineBreakRules.Segment)
    : Bool :=
  let plan := LayoutPlan.resolve context segment
  plan.preservesSourceBreaks
  && !(sourceBreaksAllowedByBreakPoints source segment plan.breakPoints).isEmpty

partial def segmentHasRuleSourceBreaks
    (source : String) (context : LineBreakRules.RuleContext)
    (segment : LineBreakRules.Segment)
    : Bool :=
  match segment.parent with
  | .missing => false
  | .leaf _ => false
  | .node _ _ =>
      if segmentHasAllowedSourceBreaks source context segment then
        true
      else
        let rec loop : List Nat → Bool
          | [] => false
          | index :: rest =>
              match segment.child? index with
              | none => false
              | some child =>
                  let childSegment := LineBreakRules.Segment.ofTree child
                  segmentHasRuleSourceBreaks source (context.push segment index)
                    childSegment
                  || loop rest
        loop segment.indexes

partial def segmentAllowsLayoutWithoutRuleBreaks
    (source : String) (context : LineBreakRules.RuleContext)
    (segment : LineBreakRules.Segment) (respectSourceBreaks : Bool := true)
    (facts? : Option TreeLayoutFacts := none)
    : Bool :=
  match segment.parent with
  | .missing => true
  | .leaf _ => true
  | .node _ _ =>
      match originalPlanForTree source segment.parent facts? with
      | some islandPlan =>
          islandPlan.policy.multiline == .preserveWithoutRuleBreaks
          || !treeSourceHasLineStructure source segment.parent
      | none =>
          let plan := LayoutPlan.resolve context segment
          if (!plan.isFlow
                && treeContainsLineCommentForcedBreak source segment.parent facts?)
              || plan.isMandatory
              || (plan.breakPoints.any (·.indentLevels == 0)
                  && segmentContainsMultilineOriginalEmission source segment facts?) then
            false
          else
            match segment.singleChild? with
            | some (index, child) =>
                segmentAllowsLayoutWithoutRuleBreaks source (context.push segment index)
                  (LineBreakRules.Segment.ofTree child) true
                  (facts? >>= (·.child? index))
            | none =>
                if respectSourceBreaks
                    && segmentHasAllowedSourceBreaks source context segment then
                  false
                else
                  let rec loop : List Nat → Bool
                    | [] => true
                    | index :: rest =>
                        match segment.child? index with
                        | none => true
                        | some child =>
                            segmentAllowsLayoutWithoutRuleBreaks source
                              (context.push segment index)
                              (LineBreakRules.Segment.ofTree child) true
                              (facts? >>= (·.child? index))
                            && loop rest
                  loop segment.indexes

structure LayoutProbe where
  fits : Bool
  flat : Bool
  rendered? : Option RenderState := none

def RenderState.commitLayoutProbe (state : RenderState) (probe : LayoutProbe)
    : RenderState :=
  match probe.rendered? with
  | none => state
  | some rendered =>
      {
        state with
          output := state.output ++ rendered.output
          outputLineBreakCount :=
            state.outputLineBreakCount + rendered.outputLineBreakCount
          completedLineOverflowCount :=
            state.completedLineOverflowCount + rendered.completedLineOverflowCount
          introducedAtomicOverflowCount :=
            state.introducedAtomicOverflowCount + rendered.introducedAtomicOverflowCount
          currentLine := rendered.currentLine
          lastToken? := rendered.lastToken?
          pendingIndent? := rendered.pendingIndent?
          pendingCommandBoundary? := rendered.pendingCommandBoundary?
          preserveNextStandaloneCommentIndent :=
            rendered.preserveNextStandaloneCommentIndent
          movePendingCommentAfterToken := rendered.movePendingCommentAfterToken
          brokenJoins := rendered.brokenJoins
      }

def measureLayout
    (state : RenderState) (segment : LineBreakRules.Segment)
    (respectSourceBreaks : Bool := true)
    : LayoutProbe :=
  if !segmentAllowsLayoutWithoutRuleBreaks state.source state.context segment
        respectSourceBreaks state.layoutFacts? then
    { fits := false, flat := false }
  else
    let probe := state.forFitProbe
    let rendered? :=
      if lineFits state.currentLine state.options.lineWidth then
        probeLayoutWithoutRuleBreaks? probe segment
      else
        (probeLayoutWithoutRuleBreaksCore? probe segment false).map (·.1)
    match rendered? with
    | none => { fits := false, flat := false }
    | some rendered =>
        let fits :=
          if lineFits state.currentLine state.options.lineWidth then
            renderedCandidateFits probe rendered
          else
            currentLineFitsWith state rendered.output
        {
          fits
          flat := fits && !renderedSegmentIsMultiline probe rendered segment
          rendered? := some rendered
        }

def nestedLayoutFits (state : RenderState) (segment : LineBreakRules.Segment) : Bool :=
  let plan := LayoutPlan.resolve state.context segment
  (measureLayout (state.withChildPlacement segment plan) segment).fits

def LayoutProbe.acceptedForRule
    (probe : LayoutProbe)
    (isFlow : Bool) (breakPoints : List LineBreakRules.BreakPoint)
    : Bool :=
  if isFlow && breakPoints.any fun breakPoint => breakPoint.indentLevels == 0 then
    probe.flat
  else
    probe.fits

def segmentFirstTokenColumn (state : RenderState) (segment : LineBreakRules.Segment)
    : Nat :=
  match segmentFirstToken? segment with
  | some token => state.nextTokenColumn token
  | none => state.currentColumn

def RenderState.extendTailIndentation
    (state : RenderState) (_segment : LineBreakRules.Segment) (parentIndentation : Nat)
    : RenderState :=
  let inheritedIndentation :=
    match state.tailIndentation? with
    | some indentation => max indentation parentIndentation
    | none => parentIndentation
  { state with tailIndentation? := some inheritedIndentation }

def ruleRetainsSourceBreakAt
    (state : RenderState) (segment : LineBreakRules.Segment)
    (plan : LayoutPlan.Plan) (index : Nat)
    : Bool :=
  if plan.formatsOriginalLeadingBoundary index
      && plan.keepsPrefixWithChildFirstLine index then
    false
  else if index == segment.start then
    (sourceBreakBeforeSegmentStart? state segment).isSome
  else if segment.start < index then
    let boundary? := do
      let right ← segment.child? index >>= SyntaxTree.Tree.firstToken?
      let parentSegment := segment.slice 0 segment.stop
      let leftIndex ← LineBreakRules.previousContentIndex? parentSegment index
      let left ← segment.parentChild? leftIndex >>= SyntaxTree.Tree.lastToken?
      some (left, right)
    boundary?.any fun (left, right) => hasSourceBreakBetweenTokens state.source left right
  else
    false

def sourceBreaksForRule?
    (state : RenderState) (segment : LineBreakRules.Segment)
    (plan : LayoutPlan.Plan)
    : Option (List SourceBreak) :=
  let sourceBreaks :=
    plan.breakPoints.filterMap
      fun breakPoint =>
        if ruleRetainsSourceBreakAt state segment plan breakPoint.index then
          some
            {
              index := breakPoint.index,
              indent := breakPointIndent state segment plan breakPoint
            }
        else
          none
  if sourceBreaks.isEmpty then
    none
  else
    some sourceBreaks

/-! ## Flow rendering decisions -/

structure FlowRenderContext where
  segment : LineBreakRules.Segment
  plan : LayoutPlan.Plan
  sourceBreaks : List SourceBreak
  entryState : RenderState

def FlowRenderContext.breakAt? (flow : FlowRenderContext) (index : Nat)
    : Option LineBreakRules.BreakPoint :=
  flow.plan.breakPoints.find? fun breakPoint => breakPoint.index == index

def FlowRenderContext.hasSourceBreakAt (flow : FlowRenderContext) (index : Nat) : Bool :=
  flow.sourceBreaks.any fun sourceBreak => sourceBreak.index == index

def FlowRenderContext.nextBreakIndex (flow : FlowRenderContext) (index : Nat) : Nat :=
  match flow.plan.breakPoints.find? fun breakPoint => index < breakPoint.index with
  | some breakPoint => breakPoint.index
  | none => flow.segment.stop

def FlowRenderContext.suffixMayContinueAcrossBreak
    (flow : FlowRenderContext) (index : Nat)
    : Bool :=
  flow.plan.keepsPrefixWithChildFirstLine index
  || groupedSuffixMayContinueAcrossRuleBreak flow.segment index

def FlowRenderContext.stateForPieceFit
    (flow : FlowRenderContext) (state : RenderState) (index : Nat)
    : RenderState :=
  let nextBreakIndex := flow.nextBreakIndex index
  if nextBreakIndex == flow.segment.stop then
    state
  else
    match flow.segment.child? (nextBreakIndex - 1) with
    | some child =>
        let suffixStop :=
          if flow.suffixMayContinueAcrossBreak nextBreakIndex then
            flow.segment.stop
          else
            nextBreakIndex
        let suffixWidth :=
          lineFitSuffixForChild state flow.segment (nextBreakIndex - 1) suffixStop child
        { state with lineFitSuffixWidth := suffixWidth }
    | none => state

def FlowRenderContext.stateForChildFit
    (flow : FlowRenderContext) (state : RenderState) (index : Nat)
    (child : SyntaxTree.Tree)
    : RenderState :=
  let nextBreakIndex := flow.nextBreakIndex index
  let suffixStop :=
    if flow.suffixMayContinueAcrossBreak nextBreakIndex then
      flow.segment.stop
    else
      nextBreakIndex
  let suffixWidth := lineFitSuffixForChild state flow.segment index suffixStop child
  { state with lineFitSuffixWidth := suffixWidth }

def FlowRenderContext.measurePiece
    (flow : FlowRenderContext) (state : RenderState) (index : Nat)
    : LayoutProbe :=
  measureLayout (flow.stateForPieceFit state index)
    (flow.segment.slice index (flow.nextBreakIndex index))
    false

def FlowRenderContext.measureChild
    (flow : FlowRenderContext) (state : RenderState) (index : Nat)
    (context : LineBreakRules.RuleContext)
    (childSegment : LineBreakRules.Segment)
    (respectSourceBreaks : Bool := true)
    : LayoutProbe :=
  let probe :=
    {
      flow.stateForChildFit state index childSegment.parent with
        context
        layoutFacts? := state.layoutFacts? >>= fun facts => facts.child? index
    }
  let plan := LayoutPlan.resolve context childSegment
  measureLayout (probe.withChildPlacement childSegment plan) childSegment
    respectSourceBreaks

def FlowRenderContext.childFirstLineFits
    (flow : FlowRenderContext) (state : RenderState) (index : Nat)
    (context : LineBreakRules.RuleContext) (child : SyntaxTree.Tree)
    : Bool :=
  let probe :=
    {
      flow.stateForChildFit state index child with
        context
        layoutFacts? := state.layoutFacts? >>= fun facts => facts.child? index
    }
  let segment := LineBreakRules.Segment.ofTree child
  let probe := probe.withChildPlacement segment (LayoutPlan.resolve context segment)
  let (rendered, _) := renderFirstLineOfTree probe child
  !outputIntroducedLineBreak probe rendered
  && lineFitsWithTrailingWidth rendered.currentLine rendered.lineFitSuffixWidth
      rendered.options.lineWidth

def FlowRenderContext.childLeadingOwnedPieceFits
    (flow : FlowRenderContext) (state : RenderState) (index : Nat)
    (context : LineBreakRules.RuleContext) (child : SyntaxTree.Tree)
    : Bool :=
  let segment := LineBreakRules.Segment.ofTree child
  let plan := LayoutPlan.resolve context segment
  match plan.breakPoints.head? with
  | some breakPoint =>
      if plan.formatsOriginalLeadingBoundary breakPoint.index then
        let probe :=
          {
            flow.stateForChildFit state index child with
              context
              layoutFacts? := state.layoutFacts? >>= fun facts => facts.child? index
              lineFitSuffixWidth := 0
          }
        (measureLayout (probe.withChildPlacement segment plan)
          (segment.slice segment.start breakPoint.index) false).flat
      else
        flow.childFirstLineFits state index context child
  | none => flow.childFirstLineFits state index context child

def FlowRenderContext.childSourceFirstLineFitsAfterPrefix
    (flow : FlowRenderContext) (state : RenderState) (index : Nat)
    (child : SyntaxTree.Tree)
    : Bool :=
  let probe := flow.stateForChildFit state index child
  match probe.lastToken?, child.firstToken?,
        treeFirstSourceLineWidth? probe.source child with
  | some left, some first, some firstLineWidth =>
      let spacingWidth := (SpaceRules.spaceBetweenTokens left first).length
      treeSourceHasLineStructure probe.source child
      && probe.currentColumn + spacingWidth + firstLineWidth + probe.lineFitSuffixWidth
          <= probe.options.lineWidth
  | _, _, _ => false

def FlowRenderContext.withBreak
    (flow : FlowRenderContext) (state : RenderState)
    (breakPoint : LineBreakRules.BreakPoint)
    : RenderState :=
  let entryIndentation :=
    if flow.plan.base == .rounded && outputIntroducedLineBreak flow.entryState state then
      max flow.entryState.segmentIndentation
        (indentationLevelForColumn state.currentIndent)
    else
      flow.entryState.segmentIndentation
  let entryBaseColumn :=
    if entryIndentation == flow.entryState.segmentIndentation then
      flow.entryState.segmentBaseColumn
    else
      entryIndentation * indentationSpaces
  let base :=
    ruleBreakBase flow.entryState flow.segment flow.plan
      entryBaseColumn entryIndentation breakPoint
  state.withRuleBreakIndent base.column base.indentation breakPoint

def FlowRenderContext.childSourceFirstLineFitsAfterBreak
    (flow : FlowRenderContext) (state : RenderState) (index : Nat)
    (child : SyntaxTree.Tree)
    : Bool :=
  let brokenState :=
    match flow.breakAt? index with
    | some breakPoint => flow.withBreak state breakPoint
    | none => state.withPendingIndent (state.segmentBaseIndent + indentationSpaces)
  let probe := flow.stateForChildFit brokenState index child
  match treeFirstSourceLineWidth? probe.source child with
  | some firstLineWidth =>
      probe.currentColumn + firstLineWidth + probe.lineFitSuffixWidth
      <= probe.options.lineWidth
  | none => false

def FlowRenderContext.stateForForcedNestedChild?
    (flow : FlowRenderContext) (state : RenderState) (index : Nat)
    (child : SyntaxTree.Tree)
    (breakAfterPreviousChild : Bool)
    (childFit : Thunk LayoutProbe)
    (keepPrefixWithChildFirstLine : Bool)
    (childStartsWithLineBreakingComment : Bool)
    : Option RenderState :=
  match flow.breakAt? index with
  | some breakPoint =>
      if index == flow.segment.start then
        if childFit.get.fits then
          some state
        else
          some
          <| state.withPendingIndent
              (state.currentIndent + breakPoint.indentLevels * indentationSpaces)
      else if keepPrefixWithChildFirstLine then
        if childStartsWithLineBreakingComment then
          none
        else if (originalPlanForTree state.source child
                  (state.layoutFacts? >>= (·.child? index))).isSome
                && (!flow.plan.formatsOriginalLeadingBoundary index
                    || !OriginalTree.canUseStructuralOverflowFallback child)
                && (!childFit.get.fits
                    || !flow.childSourceFirstLineFitsAfterPrefix state index child)
                && !childFit.get.flat then
          some <| flow.withBreak state breakPoint
        else
          none
      else if breakAfterPreviousChild
              || !childFit.get.fits
              || flow.hasSourceBreakAt index
              || commentForcesBreakAt state.source flow.segment index
              || (let summary :=
                    treeLayoutSummary state.source child
                      (state.layoutFacts? >>= (·.child? index))
                  (summary.containsMultilineOriginalEmission
                    || summary.startsWithRetainedOriginalBoundary)
                  && !childFit.get.flat)
              || treeContainsCommentForcedBreak state.source child
                  (state.layoutFacts? >>= (·.child? index))
              || (let pieceFit := flow.measurePiece state index
                  (breakPoint.indentLevels == 0 && !pieceFit.flat) || !pieceFit.fits) then
        some <| flow.withBreak state breakPoint
      else
        none
  | none =>
      if index == flow.segment.start then some state else none

def segmentRangeFirstTree? (segment : LineBreakRules.Segment) (start stop : Nat)
    : Option SyntaxTree.Tree :=
  let rec loop (index : Nat) : Option SyntaxTree.Tree :=
    if index < stop then
      match segment.child? index with
      | some tree => if tree.firstToken?.isSome then some tree else loop (index + 1)
      | none => loop (index + 1)
    else
      none
  loop start

inductive CommandBoundaryPlan where
  | preserve
  | fixed (spacing : CommandBoundarySpacing)
  | blankLineIfMultiline

def commandBoundaryPlan
    (sequenceKind : LineBreakRules.CommandSequenceKind)
    (previous current : LineBreakRules.CommandKind)
    (previousMultiline : Bool)
    : CommandBoundaryPlan :=
  match sequenceKind with
  | .module | .header => .fixed .blankLine
  | .imports =>
      match previous, current with
      | .publicImport, .publicImport | .ordinaryImport, .ordinaryImport =>
          .fixed .lineBreak
      | _, _ => .fixed .blankLine
  | .commands =>
      match previous, current with
      | .moduleDoc, _ => .fixed .blankLine
      | .declaration, .declaration =>
          if previousMultiline then .fixed .blankLine else .blankLineIfMultiline
      | _, _ => .preserve

/-! ## Recursive rendering -/

mutual

  partial def renderSegment (state : RenderState) (segment : LineBreakRules.Segment)
      (prepared? : Option LayoutPlan.Plan := none)
      : RenderState :=
    match state.layoutFacts?.bind (·.summary.retryOwner?) with
    | some owner =>
        if segment.start == 0
            && segment.stop == (LineBreakRules.Segment.ofTree segment.parent).stop then
          renderRetryOwner state segment prepared? owner
        else
          renderSegmentCore state segment prepared?
    | none => renderSegmentCore state segment prepared?

  partial def renderRetryOwner (state : RenderState) (segment : LineBreakRules.Segment)
      (prepared? : Option LayoutPlan.Plan) (owner : LayoutTree.RetryOwner)
      : RenderState :=
    -- First collect simultaneous failures; later attempts may abandon a doomed tail.
    -- Only this retry boundary receives incomplete attempts, never fit comparisons.
    let rendered :=
      renderSegmentCore state segment prepared?
        (stopAfterBrokenJoin := !owner.disabled.isEmpty)
    let first := owner.tree.firstToken?.map (·.span.start.byteIdx) |>.getD 0
    let last := owner.tree.lastToken?.map (·.span.stop.byteIdx) |>.getD 0
    let broken :=
      rendered.brokenJoins.filter
        fun key => first <= key && key < last && !state.brokenJoins.contains key
    if broken.isEmpty then
      rendered
    else
      let disabled := broken.fold (fun acc key => acc.insert key) owner.disabled
      let view := LayoutTree.prepare state.source owner.tree disabled owner.boundaries
      let retryFacts :=
        if state.retryFacts.isEmpty then
          TreeLayoutFacts.cacheOfTree state.source segment.parent owner.boundaries
        else
          state.retryFacts
      let rendered :=
        renderSegment
          {
            state with
              layoutFacts? :=
                some (TreeLayoutFacts.ofPrepared state.source view retryFacts)
              retryFacts
              guardedJoins := state.guardedJoins.filter fun key => !broken.contains key
          }
          (LineBreakRules.Segment.ofTree view.tree)
      {
        rendered with
          guardedJoins := state.guardedJoins,
          layoutFacts? := state.layoutFacts?
          retryFacts := state.retryFacts
      }

  partial def renderSegmentCore (state : RenderState) (segment : LineBreakRules.Segment)
      (prepared? : Option LayoutPlan.Plan := none)
      (stopAfterBrokenJoin : Bool := false)
      : RenderState :=
    let plan := prepared?.getD (LayoutPlan.resolve state.context segment)
    let tailIndentationStop? :=
      match segment.parent with
      | .node _ children =>
          if segment.start == 0 && segment.stop == children.size then
            if plan.liftsTail && segment.start < segment.stop then
              some (segment.stop - 1)
            else
              none
          else
            state.tailIndentationStop?
      | _ => none
    let state :=
      match segment.parent with
      | .node _ _ =>
          if plan.liftsTail && !plan.inheritsBase then
            match segmentFirstToken? segment with
            | some token =>
                let baseColumn := state.nextTokenColumn token
                {
                  state with
                    segmentBaseColumn := baseColumn
                    segmentIndentation := indentationLevelForColumn baseColumn
                }
            | none => state
          else
            state
      | _ => state
    let state :=
      match segment.parent with
      | .node _ children =>
          if segment.start == 0 && segment.stop == children.size then
            {
              state with
                breakIndentationShift :=
                  computeRuleBreakShift state plan state.segmentBaseColumn
                    state.segmentIndentation plan.breakPoints
            }
          else
            state
      | _ => state
    let tailIndentationAnchors :=
      match segment.parent with
      | .node _ children =>
          if segment.start == 0
              && segment.stop == children.size
              && tailIndentationStop?.isSome then
            plan.breakPoints.map
              fun breakPoint =>
                {
                  stop := breakPoint.index
                  indentation :=
                    indentationLevelForColumn
                      (breakPointIndent state segment plan breakPoint)
                }
          else
            state.tailIndentationAnchors
      | _ => []
    let state := { state with tailIndentationStop?, tailIndentationAnchors }
    let state := state.traceSegment segment plan.name
    match segment.parent with
    | .missing => state
    | .leaf token => state.emitToken token
    | .node _ children =>
        if segment.start == 0 && segment.stop == children.size then
          match originalPlanForTree state.source segment.parent state.layoutFacts? with
          | some islandPlan =>
              state.emitOriginalTree segment.parent (islandPlan? := some islandPlan)
          | none =>
              renderSegmentByPlan state segment plan stopAfterBrokenJoin
        else
          renderSegmentByPlan state segment plan stopAfterBrokenJoin

  partial def renderSegmentByPlan (state : RenderState) (segment : LineBreakRules.Segment)
      (plan : LayoutPlan.Plan)
      (stopAfterBrokenJoin : Bool := false)
      : RenderState :=
    let facts :=
      match state.layoutFacts? with
      | some facts => facts
      | none => TreeLayoutFacts.ofTree state.source segment.parent
    let state :=
      if facts.summary.originalPlan?.isSome then
        {
          state with
            layoutFacts? := some (facts.withAlternative state.source (.structural #[]))
        }
      else
        state
    if plan.isAtomic then
      renderWithoutRuleBreaks state segment
    else if plan.isMandatory && !plan.breakPoints.isEmpty then
      renderBalancedSegment state segment plan
        (stopAfterBrokenJoin := stopAfterBrokenJoin)
    else if plan.breakPoints.isEmpty && !plan.isFlow then
      renderBalancedSegment state segment plan
        (stopAfterBrokenJoin := stopAfterBrokenJoin)
    else if plan.preservesSourceBreaks then
      renderUsingExistingBreaks state segment plan stopAfterBrokenJoin
    else
      let probe := measureLayout state segment false
      let hasRetainedSourceBreak :=
        plan.breakPoints.any
          fun breakPoint =>
            commentForcesBreakAt state.source segment breakPoint.index
            || sourceBrokenCommentedDelimiterAt state.source segment breakPoint.index
      let keepsPrefixWithChildFirstLine :=
        segment.indexes.any fun index => plan.keepsPrefixWithChildFirstLine index
      if probe.acceptedForRule plan.isFlow plan.breakPoints
          && (!plan.isFlow
              || probe.flat
              || (!segmentContainsMultilineOriginalEmission state.source segment
                    state.layoutFacts?
                  && !treeContainsCommentForcedBreak state.source segment.parent
                        state.layoutFacts?))
          && (!keepsPrefixWithChildFirstLine || probe.flat)
          && !hasRetainedSourceBreak then
        state.commitLayoutProbe probe
      else
        renderAfterFlatFailure state segment plan stopAfterBrokenJoin

  partial def renderRuleLayout
      (state : RenderState) (segment : LineBreakRules.Segment)
      (plan : LayoutPlan.Plan)
      (stopAfterBrokenJoin : Bool := false)
      : RenderState :=
    if plan.isFlow then
      renderFlowSegment state segment plan
    else
      renderBalancedSegment state segment plan
        (stopAfterBrokenJoin := stopAfterBrokenJoin)

  partial def renderAfterFlatFailure
      (state : RenderState) (segment : LineBreakRules.Segment)
      (plan : LayoutPlan.Plan)
      (stopAfterBrokenJoin : Bool := false)
      : RenderState :=
    let fallback (_ : Unit) := renderRuleLayout state segment plan stopAfterBrokenJoin
    let movesLeadingCommentWithPrefix :=
      segment.indexes.any
        fun index =>
          plan.formatsOriginalLeadingBoundary index
          && commentForcesBreakAt state.source segment index
          && (segment.child? index).any
              fun child =>
                !child.firstToken?.any
                  fun token => SpaceRules.isDelimiterCloserToken token.lexeme
    if !plan.isFlow then
      fallback ()
    else if movesLeadingCommentWithPrefix
            || segment.indexes.any
                fun index => plan.keepsPrefixWithChildFirstLine index then
      fallback ()
    else
      match sourceBreaksForRule? state segment plan with
      | none => fallback ()
      | some sourceBreaks =>
          match renderFlowSegmentWithSourceBreaks? state segment sourceBreaks with
          | some candidate =>
              if renderedCandidateFits state candidate then candidate else fallback ()
          | none => fallback ()

  partial def renderUsingExistingBreaks
      (state : RenderState) (segment : LineBreakRules.Segment)
      (plan : LayoutPlan.Plan)
      (stopAfterBrokenJoin : Bool := false)
      : RenderState :=
    let renderFlatOrRuleLayout (_ : Unit) :=
      let probe := measureLayout state segment false
      if probe.acceptedForRule plan.isFlow plan.breakPoints
          && !treeContainsLineCommentForcedBreak state.source segment.parent
                state.layoutFacts? then
        state.commitLayoutProbe probe
      else
        renderRuleLayout state segment plan stopAfterBrokenJoin
    if !plan.isFlow then
      if plan.breakPoints.any
          fun breakPoint =>
            ruleRetainsSourceBreakAt state segment plan breakPoint.index then
        renderBalancedSegment state segment plan
          (stopAfterBrokenJoin := stopAfterBrokenJoin)
      else
        renderFlatOrRuleLayout ()
    else
      match sourceBreaksForRule? state segment plan with
      | some sourceBreaks =>
          match renderFlowSegmentWithSourceBreaks? state segment sourceBreaks with
          | some rendered =>
              if renderedCandidateFits state rendered then
                rendered
              else
                renderRuleLayout state segment plan stopAfterBrokenJoin
          | none =>
              if segmentContainsMultilineOriginalEmission state.source segment
                  state.layoutFacts? then
                renderRuleLayout state segment plan stopAfterBrokenJoin
              else
                renderFlatOrRuleLayout ()
      | none => renderFlatOrRuleLayout ()

  partial def renderNestedSegment
      (state : RenderState) (segment : LineBreakRules.Segment) (index : Nat)
      (child : SyntaxTree.Tree) (suffixStop? : Option Nat := none)
      (keepLeadingCommentWithPrefix : Bool := false)
      : RenderState :=
    let childLayoutFacts? := state.layoutFacts? >>= (·.child? index)
    let originalPlan? := originalPlanForTree state.source child childLayoutFacts?
    let emitOriginal := originalPlan?.isSome
    let childContext := state.context.push segment index
    let childSegment := LineBreakRules.Segment.ofTree child
    let childPlan := LayoutPlan.resolve childContext childSegment
    let childBreakPoints :=
      if emitOriginal then
        []
      else
        childPlan.breakPoints
    let inheritsBase := childPlan.inheritsBase
    let startAlignment := childPlan.startAlignment
    let suffixStop := suffixStop?.getD segment.stop
    let lineFitSuffix := lineFitSuffixForChild state segment index suffixStop child
    let firstToken? := SyntaxTree.Tree.firstToken? child
    let commentTrivia? := commentTriviaBeforeTree? state child
    let commentForcesBreak :=
      (keepLeadingCommentWithPrefix && commentForcesBreakAt state.source segment index)
      || commentTrivia?.any
          fun trivia =>
            (SourceBoundary.ofText trivia).commentForcesBreak
    let inlineCommentNeedsBreak :=
      if state.pendingIndent?.isSome || commentForcesBreak || commentTrivia?.isNone then
        false
      else
        let probe :=
          {
            state with
              context := childContext
              layoutFacts? := childLayoutFacts?
              lineFitSuffixWidth := lineFitSuffix
          }
        let (rendered, _) := renderFirstLineOfTree probe child
        !renderedCandidateFits probe rendered
    let state :=
      if keepLeadingCommentWithPrefix && commentForcesBreak then
        let indent :=
          if firstToken?.any
              fun token => SpaceRules.isDelimiterCloserToken token.lexeme then
            state.segmentBaseIndent
          else
            state.segmentBaseIndent + indentationSpaces
        state.withCommentBoundaryIndent indent true
      else if state.pendingIndent?.isSome
              || (!commentForcesBreak && !inlineCommentNeedsBreak) then
        state
      else
        let indent :=
          if firstToken?.any
              fun token => SpaceRules.isDelimiterCloserToken token.lexeme then
            state.segmentBaseIndent
          else
            state.segmentBaseIndent + indentationSpaces
        state.withCommentBoundaryIndent indent commentForcesBreak
    let state :=
      if inheritsBase || startAlignment == .none then
        state
      else if nestedLayoutFits
                {
                  state with
                    context := childContext
                    layoutFacts? := childLayoutFacts?
                    lineFitSuffixWidth := lineFitSuffix
                }
                childSegment then
        state
      else if startAlignment == .preferred && !state.allowsStartAlignment then
        state
      else
        let naturalStartColumn := state.segmentStartColumn childSegment
        let alignedStartColumn := indentationPastColumn naturalStartColumn
        state.appendOutput <| spaces (alignedStartColumn - naturalStartColumn)
    let sourceLayoutStart? := state.sourceLayoutStart? child
    let startsOnNewSourceLine := sourceLayoutStart?.isSome
    let parentRelativeOriginalColumn? := sourceLayoutStart?.map (·.2)
    let formatLeadingBoundary :=
      formatOriginalChildLeadingBoundary state.context segment index
    let state :=
      match state.pendingIndent?, firstToken? with
      | some desiredIndent, some firstToken =>
          if LayoutPlan.treeHasUnbreakableFirstLine state.source child childPlan then
            match treeFirstSourceLineWidth? state.source child with
            | some firstLineWidth =>
                if desiredIndent + firstLineWidth <= state.options.lineWidth then
                  state
                else
                  let sourceColumn := state.sourceMap.columnAt firstToken.span.start
                  let renderedParentRelativeColumn? :=
                    match state.lastToken? with
                    | some leftToken =>
                        if state.currentLine.endsWith leftToken.lexeme then
                          let sourceAnchor :=
                            state.sourceMap.columnAt leftToken.span.start
                          let outputAnchor :=
                            lineWidth state.currentLine - leftToken.lexeme.length
                          some
                          <| ({
                                sourceColumn := sourceAnchor, outputColumn := outputAnchor
                              }
                              : Rebase.Anchor).shiftColumn
                              sourceColumn
                        else
                          none
                    | none => none
                  let targetColumn :=
                    let singleTokenRecovery := child.singleToken?.isSome
                    let atomicRecovery := childPlan.isAtomic || singleTokenRecovery
                    let canUseSourceColumn :=
                      atomicRecovery || child.startsWithOpeningDelimiter
                    let parentRelativeColumn :=
                      sourceLayoutStart?.map (·.2)
                      |>.getD (state.layoutAnchor.shiftColumn sourceColumn)
                    let minimumRecoveryColumn :=
                      if singleTokenRecovery then
                        desiredIndent - indentationSpaces
                      else if childPlan.isAtomic then
                        max (max 1 state.layoutAnchor.outputColumn)
                          (desiredIndent - indentationSpaces)
                      else
                        desiredIndent
                    let fitsAt column :=
                      minimumRecoveryColumn <= column
                      && column + firstLineWidth <= state.options.lineWidth
                    match renderedParentRelativeColumn? with
                    | some renderedParentRelativeColumn =>
                        if fitsAt renderedParentRelativeColumn then
                          some renderedParentRelativeColumn
                        else if canUseSourceColumn && fitsAt sourceColumn then
                          some sourceColumn
                        else
                          none
                    | none =>
                        if fitsAt parentRelativeColumn then
                          some parentRelativeColumn
                        else if canUseSourceColumn && fitsAt sourceColumn then
                          some sourceColumn
                        else
                          none
                  match targetColumn with
                  | some targetColumn =>
                      { state with pendingIndent? := some targetColumn }
                  | none => state
            | none => state
          else
            state
      | _, _ => state
    let scope := ChildRenderScope.capture state
    let childState :=
      {
        state.withChildPlacement childSegment childPlan with
          context := childContext
          layoutFacts? := childLayoutFacts?
          lineFitSuffixWidth := lineFitSuffix
          trace := state.trace.pushPath index
      }
    -- A retained boundary uses the parent anchor, not a hypothetical inline column.
    let childState :=
      if startsOnNewSourceLine
          && state.pendingIndent?.isNone
          && !formatLeadingBoundary
          && (treeLayoutSummary state.source child
                childLayoutFacts?).startsWithRetainedOriginalBoundary then
        { childState with layoutAnchor := state.layoutAnchor }
      else
        childState
    let childState :=
      if state.tailIndentationStop?.any fun stop => index < stop then
        let anchorIndentation :=
          match state.tailIndentationAnchors.find? fun anchor => index < anchor.stop with
          | some anchor => anchor.indentation
          | none => state.segmentIndentation
        childState.extendTailIndentation childSegment anchorIndentation
      else
        childState
    let emitOriginalAt
        (respectPendingIndent : Bool)
        (targetColumn? : Option Nat)
        (islandPlan? : Option OriginalTree.IslandPlan)
        : RenderState :=
      childState.emitOriginalTree child
        (formatLeadingBoundary := formatLeadingBoundary)
        (respectPendingIndent := respectPendingIndent)
        (rebaseSourceTextTargetColumn? := targetColumn?)
        (islandPlan? := islandPlan?)
    let rendered :=
      if emitOriginal
          && OriginalTree.canUseStructuralLayoutAfterParentMove child
          && (formatLeadingBoundary && OriginalTree.canUseStructuralOverflowFallback child
              || state.pendingIndent?.any
                  fun desiredIndent =>
                    parentRelativeOriginalColumn? != some desiredIndent) then
        renderSegmentByPlan childState childSegment childPlan
      else if emitOriginal then
        emitOriginalAt
          (!startsOnNewSourceLine || state.pendingCommandBoundary?.isSome)
          none originalPlan?
      else
        renderSegment childState childSegment
          (some { childPlan with breakPoints := childBreakPoints })
    let rendered :=
      let overflowCount := renderedOverflowCount childState rendered
      let suffixOverflowsPreservedProof :=
        originalPlan?.any
          fun plan =>
            plan.policy.content == .proof
            && renderedOutputOverflowCount childState rendered == 0
            && 0 < overflowCount
      let alternative? := do
        let plan ← originalPlan?
        let first ← child.firstToken?
        if renderedOutputOverflowCount childState rendered == 0 then
          none
        else
          let shift :=
            childState.segmentStartColumn childSegment
            - state.sourceMap.columnAt first.span.start
          OriginalTree.overflowAlternative? state.sourceMap child plan shift
            state.options.lineWidth
      if emitOriginal
          && (OriginalTree.canUseStructuralOverflowFallback child
              || suffixOverflowsPreservedProof
              || alternative?.isSome)
          && 0 < overflowCount then
        let structuralState :=
          match alternative? with
          | some alternative =>
              let facts :=
                match childLayoutFacts? with
                | some facts => facts
                | none => TreeLayoutFacts.ofTree state.source child
              {
                childState with
                  layoutFacts? := some (facts.withAlternative state.source alternative)
              }
          | none => childState
        let structural := renderSegmentByPlan structuralState childSegment childPlan
        preferCandidateWithFewerOverflows childState rendered structural
      else
        rendered
    let rendered :=
      if childPlan.isAtomic && atomicTreeIntroducedOverflow childState rendered child then
        {
          rendered with
            introducedAtomicOverflowCount :=
              rendered.introducedAtomicOverflowCount + 1
        }
      else
        rendered
    let rendered :=
      if !emitOriginal
          || !originalPlan?.any
                fun plan => plan.policy.anchor == .preferParentRelative then
        rendered
      else
        match parentRelativeOriginalColumn? with
        | none => rendered
        | some targetColumn =>
            let original := emitOriginalAt true (some targetColumn) originalPlan?
            preferCandidateWithFewerOverflows childState rendered original
    let introducedAtomicOverflow :=
      rendered.introducedAtomicOverflowCount != childState.introducedAtomicOverflowCount
    let rendered :=
      if emitOriginal
          || !introducedAtomicOverflow
          || !LineBreakRules.canRetainParentRelativeOriginalLayoutForOverflow
                childContext child then
        rendered
      else
        match parentRelativeOriginalColumn? with
        | none => rendered
        | some targetColumn =>
            let targetColumn := max targetColumn childState.segmentBaseIndent
            let original := emitOriginalAt true (some targetColumn) none
            preferCandidateWithFewerOverflows childState rendered original
    let rendered :=
      if emitOriginal
          || !introducedAtomicOverflow
          || !LineBreakRules.canRetainOriginalLayoutForOverflow childContext child then
        rendered
      else
        let targetColumn? :=
          sourceLayoutStart?.map
            fun (sourceColumn, _) =>
              max (childState.layoutAnchor.shiftColumn sourceColumn)
                childState.segmentBaseIndent
        if targetColumn? == parentRelativeOriginalColumn? then
          rendered
        else
          let original := emitOriginalAt true targetColumn? none
          preferCandidateWithFewerOverflows childState rendered original
    scope.restore rendered

  partial def renderChildren (state : RenderState) (segment : LineBreakRules.Segment)
      : RenderState :=
    match segment.parent with
    | .missing => state
    | .leaf token => state.emitToken token
    | .node _ _ =>
        segment.indexes.foldl
          (fun state index =>
            match segment.child? index with
            | some child => renderNestedSegment state segment index child
            | none => state)
          state

  partial def renderSegmentRange
      (state : RenderState) (segment : LineBreakRules.Segment)
      (start stop : Nat)
      : RenderState :=
    if start >= stop then
      state
    else if start == segment.start && stop == segment.stop then
      renderChildren state (segment.slice start stop)
    else
      renderSegment state (segment.slice start stop)

  partial def renderFlowSegmentWithSourceBreaks?
      (state : RenderState) (segment : LineBreakRules.Segment) (breaks : List SourceBreak)
      : Option RenderState :=
    let layout : SourceBreakLayout := { segment, breaks }
    let rec loop (state : RenderState) (index : Nat) : Option RenderState :=
      if index < segment.stop then
        match segment.child? index with
        | none => loop state (index + 1)
        | some child =>
            let state :=
              match layout.breakAt? index with
              | some sourceBreak =>
                  state.withPendingIndent sourceBreak.indent
              | none => state
            let before := state
            let rendered :=
              renderNestedSegment state segment index child
                (some (layout.nextBreakIndex index))
            if renderedTreeIsMultiline before rendered child
                && (layout.breakAt? index).isNone then
              none
            else
              loop rendered (index + 1)
      else
        some state
    loop state segment.start

  partial def renderFlowSegment
      (state : RenderState) (segment : LineBreakRules.Segment)
      (plan : LayoutPlan.Plan)
      : RenderState :=
    match SyntaxTree.Tree.firstToken? segment.parent with
    | none => renderChildren state segment
    | some _ =>
        let tightSuffixIndex? :=
          segment.indexes.find?
            fun index =>
              plan.keepsPrefixWithChildFirstLine index
              && (segment.child? index).any
                  fun child =>
                    (LineBreakRules.Segment.ofTree child).size == 0
                    && !commentForcesBreakAt state.source segment index
        let earlierBreaks :=
          match tightSuffixIndex? with
          | some suffixIndex =>
              plan.breakPoints.filter fun point => point.index < suffixIndex
          | none => []
        let needsEarlierBreaks :=
          !earlierBreaks.isEmpty && !(measureLayout state segment false).fits
        let tightSuffixIsDelimiterCloser :=
          tightSuffixIndex?.any
            fun index =>
              (segment.child? index >>= SyntaxTree.Tree.firstToken?).any
                fun token => SpaceRules.isDelimiterCloserToken token.lexeme
        if needsEarlierBreaks && !tightSuffixIsDelimiterCloser then
          renderBalancedSegment state segment { plan with breakPoints := earlierBreaks }
            false
        else
          let flow : FlowRenderContext :=
            {
              segment
              plan
              sourceBreaks :=
                if plan.preservesSourceBreaks then
                  sourceBreaksAllowedByBreakPointsInState state segment plan.breakPoints
                else
                  []
              entryState := state
            }
          renderFlowChildren state flow segment.start false

  partial def renderFlowChildren
      (state : RenderState) (flow : FlowRenderContext) (index : Nat)
      (breakAfterPreviousChild : Bool)
      : RenderState :=
    if index >= flow.segment.stop then
      state
    else
      match flow.segment.child? index with
      | none =>
          renderFlowChildren state flow (index + 1) breakAfterPreviousChild
      | some child =>
          let state :=
            if index + 1 == flow.segment.stop
                && flow.plan.inheritsBase
                && flow.plan.roundsUpBase then
              {
                state with
                  segmentBaseColumn := flow.entryState.segmentBaseColumn
                  segmentIndentation := flow.entryState.segmentIndentation
              }
            else
              state
          let childSegment := LineBreakRules.Segment.ofTree child
          let childContext := state.context.push flow.segment index
          let keepsPrefixWithChildFirstLine :=
            flow.plan.keepsPrefixWithChildFirstLine index
          let childFirstLineFits :=
            if keepsPrefixWithChildFirstLine then
              flow.childLeadingOwnedPieceFits state index childContext child
            else
              false
          let childStartsWithLineBreakingComment :=
            commentForcesBreakAt state.source flow.segment index
            || (commentTriviaBeforeTree? state child).any
                fun trivia => (SourceBoundary.ofText trivia).commentForcesBreak
          let childIsDelimiterCloser :=
            child.firstToken?.any
              fun token => SpaceRules.isDelimiterCloserToken token.lexeme
          let attachDelimiterCloser :=
            childIsDelimiterCloser
            && keepsPrefixWithChildFirstLine
            && !childStartsWithLineBreakingComment
          let state :=
            if attachDelimiterCloser then
              { state with pendingIndent? := none }
            else
              state
          let childFit : Thunk LayoutProbe :=
            ⟨fun _ =>
              flow.measureChild state index childContext childSegment
                (index == flow.segment.start)⟩
          let childStartsWithUnbreakableOriginalFirstLine :=
            (state.layoutFacts? >>= (·.child? index)).any
              (·.summary.startsWithUnbreakableOriginalFirstLine)
          let childFirstLineCannotFitAfterBreak :=
            (flow.breakAt? index).isNone
            && childStartsWithUnbreakableOriginalFirstLine
            && !flow.childSourceFirstLineFitsAfterBreak state index child
          let keepPrefixWithChildFirstLine :=
            (keepsPrefixWithChildFirstLine
              && !childStartsWithLineBreakingComment
              && (childIsDelimiterCloser
                  || childFirstLineFits
                  || childFirstLineCannotFitAfterBreak
                  || flow.childSourceFirstLineFitsAfterPrefix state index child))
            || (!childIsDelimiterCloser
                && childStartsWithLineBreakingComment
                && (keepsPrefixWithChildFirstLine
                    || flow.plan.formatsOriginalLeadingBoundary index))
          let renderNestedAndContinue (state : RenderState) :=
            let before := state
            let nextBreakIndex := flow.nextBreakIndex index
            let suffixStop :=
              if flow.suffixMayContinueAcrossBreak nextBreakIndex then
                flow.segment.stop
              else
                nextBreakIndex
            let renderNested (state : RenderState) :=
              renderNestedSegment state flow.segment index child (some suffixStop)
                (keepPrefixWithChildFirstLine && childStartsWithLineBreakingComment)
            let rendered := renderNested state
            let rendered :=
              match flow.breakAt? index with
              | some breakPoint =>
                  if state.pendingIndent?.isNone
                      && 0 < renderedOutputOverflowCount state rendered then
                    let candidate := renderNested (flow.withBreak state breakPoint)
                    if renderedOutputOverflowCount state candidate
                        < renderedOutputOverflowCount state rendered then
                      candidate
                    else
                      rendered
                  else
                    rendered
              | none => rendered
            renderFlowChildren rendered flow (index + 1)
              (renderedTreeIsMultiline before rendered child)
          match flow.stateForForcedNestedChild? state index child breakAfterPreviousChild
                  childFit keepPrefixWithChildFirstLine
                  childStartsWithLineBreakingComment with
          | some state => renderNestedAndContinue state
          | none =>
              let childFit := childFit.get
              if segmentHasRuleSourceBreaks state.source childContext childSegment then
                renderNestedAndContinue state
              else if childFit.fits
                      && !(keepPrefixWithChildFirstLine
                            && (childStartsWithLineBreakingComment
                                || (childIsDelimiterCloser
                                    && state.pendingIndent?.isSome))) then
                renderFlowChildren (state.commitLayoutProbe childFit) flow (index + 1)
                  false
              else if (if keepsPrefixWithChildFirstLine then
                          childFirstLineFits
                        else
                          flow.childFirstLineFits state index childContext child)
                      || keepPrefixWithChildFirstLine then
                renderNestedAndContinue state
              else
                let state :=
                  match flow.breakAt? index with
                  | some breakPoint => flow.withBreak state breakPoint
                  | none =>
                      state.withPendingIndent
                        (state.segmentBaseIndent + indentationSpaces)
                renderNestedAndContinue state

  partial def renderBalancedSegment
      (state : RenderState) (segment : LineBreakRules.Segment)
      (plan : LayoutPlan.Plan)
      (resolvePartialSegments : Bool := true)
      (stopAfterBrokenJoin : Bool := false)
      : RenderState :=
    if plan.breakPoints.isEmpty then
      segment.indexes.foldl
        (fun state index =>
          match segment.child? index with
          | some child =>
              let childIsDelimiterCloser :=
                child.firstToken?.any
                  fun token => SpaceRules.isDelimiterCloserToken token.lexeme
              let commentForcesBreak :=
                commentForcesBreakAt state.source segment index
                || (commentTriviaBeforeTree? state child).any
                    fun trivia => (SourceBoundary.ofText trivia).commentForcesBreak
              let state :=
                if childIsDelimiterCloser
                    && plan.keepsPrefixWithChildFirstLine index
                    && !commentForcesBreak then
                  { state with pendingIndent? := none }
                else
                  state
              renderNestedSegment state segment index child
          | none => state)
        state
    else
      let entryIndentation := state.segmentIndentation
      let entryBaseColumn := state.segmentBaseColumn
      let entryTailIndentation? := state.tailIndentation?
      let stateForPiece (state : RenderState) (firstPiece : Bool) : RenderState :=
        if firstPiece then
          { state with tailIndentation? := entryTailIndentation? }
        else
          { state with tailIndentation? := none }
      let renderPiece (state : RenderState) (start stop : Nat) (firstPiece : Bool)
          (preserveSuffix : Bool := false)
          : RenderState :=
        let state := stateForPiece state firstPiece
        let rendered :=
          if !resolvePartialSegments then
            renderChildren state (segment.slice start stop)
          else if preserveSuffix then
            renderSegmentRange state segment start stop
          else
            renderSegmentRange { state with lineFitSuffixWidth := 0 } segment start stop
        {
          rendered with
            tailIndentation? := entryTailIndentation?
            lineFitSuffixWidth := state.lineFitSuffixWidth
        }
      let stateAfterBreak (rendered : RenderState)
          (breakPoint : LineBreakRules.BreakPoint)
          : RenderState :=
        let base :=
          ruleBreakBase rendered segment plan entryBaseColumn entryIndentation breakPoint
        rendered.withRuleBreakIndent base.column base.indentation breakPoint
      let entryBrokenCount := state.brokenJoins.size
      let rec renderOrdinaryPieces (state : RenderState) (start : Nat) (firstPiece : Bool)
          : List LineBreakRules.BreakPoint → RenderState
        | [] => renderPiece state start segment.stop firstPiece true
        | breakPoint :: rest =>
            let rendered := renderPiece state start breakPoint.index firstPiece
            let rest := rest.dropWhile fun next => next.index == breakPoint.index
            if stopAfterBrokenJoin && rendered.brokenJoins.size > entryBrokenCount then
              rendered
            else
              renderOrdinaryPieces (stateAfterBreak rendered breakPoint)
                breakPoint.index false rest
      let rec renderCommandPieces
          (state : RenderState) (start : Nat) (firstPiece : Bool)
          (sequenceKind : LineBreakRules.CommandSequenceKind)
          (previousKind? : Option LineBreakRules.CommandKind)
          (previousMultiline : Bool)
          : List LineBreakRules.BreakPoint → RenderState
        | breaks =>
            let stop := breaks.head?.map (·.index) |>.getD segment.stop
            let finalPiece := breaks.isEmpty
            let currentTree? := segmentRangeFirstTree? segment start stop
            let currentKind? := currentTree?.map LineBreakRules.commandKind
            let boundaryPlan :=
              match previousKind?, currentKind? with
              | some previousKind, some currentKind =>
                  commandBoundaryPlan sequenceKind previousKind currentKind
                    previousMultiline
              | _, _ => .preserve
            let pieceState :=
              match boundaryPlan with
              | .fixed spacing => { state with pendingCommandBoundary? := some spacing }
              | .preserve | .blankLineIfMultiline => state
            let rendered := renderPiece pieceState start stop firstPiece finalPiece
            let currentMultiline :=
              match currentTree? with
              | some tree => renderedTreeIsMultiline pieceState rendered tree
              | none => false
            let rendered :=
              match boundaryPlan, currentMultiline, currentTree? with
              | .blankLineIfMultiline, true, some tree =>
                  state.ensureBlankCommandBoundaryBeforeRenderedTree rendered tree
              | _, _, _ => rendered
            match breaks with
            | [] => rendered
            | breakPoint :: rest =>
                let rest := rest.dropWhile fun next => next.index == breakPoint.index
                renderCommandPieces (stateAfterBreak rendered breakPoint)
                  breakPoint.index false sequenceKind currentKind? currentMultiline rest
      match LineBreakRules.commandSequenceKind? state.context segment with
      | some sequenceKind =>
          renderCommandPieces state segment.start true sequenceKind none false
            plan.breakPoints
      | none => renderOrdinaryPieces state segment.start true plan.breakPoints

end

def RenderState.finalTrivia (state : RenderState) : String :=
  match state.lastToken? with
  | some token =>
      let boundary :=
        SourceBoundary.ofText
        <| SyntaxTree.sourceText state.source token.span.stop state.source.endPos.offset
      if boundary.hasComment
          && boundary.hasLineStructure
          && !boundary.startsOnNewLine then
        let cleanedBoundary := boundary.cleaned
        let sourceCommentColumn :=
          boundary.firstCommentColumn? (state.sourceMap.columnAt token.span.stop)
        let targetCommentColumn :=
          cleanedBoundary.firstCommentColumn? (lineWidth state.currentLine)
        cleanedBoundary.forTreeBoundary
          (sourceCommentColumn.getD 0) (targetCommentColumn.getD 0) 0 ""
      else
        SpaceRules.cleanFinalTrivia boundary.text
  | none =>
      SpaceRules.cleanFinalTrivia state.source

private def renderModuleState (moduleTree : SyntaxTree.Module) (options : Options)
    (trace : Bool := false)
    : RenderState :=
  let sourceMap := SyntaxTree.SourcePositionMap.ofString moduleTree.source
  let initial := LayoutTree.prepare moduleTree.source moduleTree.tree
  let rec render (remaining : Nat) (view : LayoutTree.Prepared)
      (disabled : Std.HashSet Nat)
      : RenderState :=
    let state :=
      renderSegment
        {
          options,
          source := moduleTree.source,
          sourceMap
          layoutFacts? := some (TreeLayoutFacts.ofPrepared moduleTree.source view)
          guardedJoins := view.guardedJoins
          trace := { enabled := trace }
        }
        (LineBreakRules.Segment.ofTree view.tree)
    if state.brokenJoins.isEmpty then
      state
    else
      match remaining with
      | 0 => state
      | remaining + 1 =>
          let disabled := state.brokenJoins.fold (fun acc key => acc.insert key) disabled
          render remaining
            (LayoutTree.prepare moduleTree.source moduleTree.tree disabled
              view.boundaries)
            disabled
  -- Only committed output can disable a join; each retry removes at least one.
  render initial.guardedJoins.size initial {}

def renderModuleTree (moduleTree : SyntaxTree.Module) (options : Options := {})
    : String :=
  let state := renderModuleState moduleTree options
  SpaceRules.normalizeFinalNewline
  <| SpaceRules.stripTrailingWhitespace (state.output ++ state.finalTrivia)

def renderModuleTreeWithTrace (moduleTree : SyntaxTree.Module) (options : Options := {})
    : String × String :=
  let state := renderModuleState moduleTree options true
  let formatted :=
    SpaceRules.normalizeFinalNewline
    <| SpaceRules.stripTrailingWhitespace (state.output ++ state.finalTrivia)
  (formatted, state.trace.formatWithOutput formatted)

end Formatter
end LeanFmt
