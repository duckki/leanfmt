import LeanFmt.Formatter.LineBreakRules
import LeanFmt.Formatter.SourceBoundary

namespace LeanFmt
namespace Formatter
namespace LayoutPlan

inductive Mode where
  | atomic
  | mandatory
  | balanced
  | flow
deriving BEq, Repr

inductive SourceBreakPolicy where
  | ignore
  | preserve
deriving BEq, Repr

inductive BasePolicy where
  | local
  | inherited
  | rounded
  | inheritedRounded
deriving BEq, Repr

def BasePolicy.ofFlags (inheritBase roundUp : Bool) : BasePolicy :=
  match inheritBase, roundUp with
  | false, false => .local
  | true, false => .inherited
  | false, true => .rounded
  | true, true => .inheritedRounded

def BasePolicy.inherits : BasePolicy → Bool
  | .inherited | .inheritedRounded => true
  | .local | .rounded => false

def BasePolicy.roundsUp : BasePolicy → Bool
  | .rounded | .inheritedRounded => true
  | .local | .inherited => false

inductive TailPolicy where
  | unchanged
  | lift
deriving BEq, Repr

inductive PrefixPolicy where
  | independent
  | keepWithChildFirstLine
deriving BEq, Repr

inductive LeadingBoundaryPolicy where
  | preserveWithOriginal
  | formatWithParent
deriving BEq, Repr

structure ChildBoundaryPlan where
  index : Nat
  prefixPolicy : PrefixPolicy := .independent
  originalLeading : LeadingBoundaryPolicy := .preserveWithOriginal
deriving BEq, Repr

structure Plan where
  name : String
  mode : Mode
  sourceBreaks : SourceBreakPolicy
  base : BasePolicy
  tail : TailPolicy
  startAlignment : LineBreakRules.StartAlignment
  breakPoints : List LineBreakRules.BreakPoint
  children : List ChildBoundaryPlan
deriving Repr

def contentChildIndexAtOrAfter? (segment : LineBreakRules.Segment) (index : Nat)
    : Option Nat :=
  segment.indexes.find?
    fun candidate =>
      index <= candidate
      && match segment.child? candidate with
          | some child => LineBreakRules.treeHasContent child
          | none => false

def tokenBoundaryAt? (segment : LineBreakRules.Segment) (index : Nat)
    : Option (SyntaxTree.Token × SyntaxTree.Token) := do
  let leftIndex ← LineBreakRules.previousContentIndex? segment index
  let rightIndex ← contentChildIndexAtOrAfter? segment index
  let leftTree ← segment.child? leftIndex
  let rightTree ← segment.child? rightIndex
  let leftToken ← SyntaxTree.Tree.lastToken? leftTree
  let rightToken ← SyntaxTree.Tree.firstToken? rightTree
  some (leftToken, rightToken)

def preservesTightTokenBoundary
    (segment : LineBreakRules.Segment) (breakPoint : LineBreakRules.BreakPoint)
    : Bool :=
  match tokenBoundaryAt? segment breakPoint.index with
  | some (left, right) =>
      !SpaceRules.isTrailingSeparatorToken right.lexeme
      && !SpaceRules.preservesTightDotSpacing left right
      && !SpaceRules.preservesTightQuotedNameSpacing left right
      && !(left.span.stop == right.span.start
            && !LineBreakRules.suffixOpeningDelimiterLexeme left.lexeme
            && SpaceRules.preservesTightPostfixSpacing right)
  | none => true

def moveAfterTrailingSeparator
    (segment : LineBreakRules.Segment) (breakPoint : LineBreakRules.BreakPoint)
    : LineBreakRules.BreakPoint :=
  match contentChildIndexAtOrAfter? segment breakPoint.index with
  | some separatorIndex =>
      match segment.child? separatorIndex >>= SyntaxTree.Tree.singleToken? with
      | some separator =>
          if SpaceRules.isTrailingSeparatorToken separator.lexeme then
            match contentChildIndexAtOrAfter? segment (separatorIndex + 1) with
            | some nextIndex => { breakPoint with index := nextIndex }
            | none => breakPoint
          else
            breakPoint
      | none => breakPoint
  | none => breakPoint

def normalizeBreakPoints
    (segment : LineBreakRules.Segment)
    (breakPoints : List LineBreakRules.BreakPoint)
    : List LineBreakRules.BreakPoint :=
  (breakPoints.map (moveAfterTrailingSeparator segment)
    |>.filter
        fun breakPoint =>
          segment.start <= breakPoint.index
          && breakPoint.index < segment.stop
          && preservesTightTokenBoundary segment breakPoint)
  |>.mergeSort fun left right => left.index < right.index

def resolve (context : LineBreakRules.RuleContext) (segment : LineBreakRules.Segment)
    : Plan :=
  let rule := LineBreakRules.formattingRuleFor segment.parent
  let mode :=
    if rule.atomic then
      Mode.atomic
    else if rule.mandatory context segment then
      Mode.mandatory
    else if rule.flow context segment then
      Mode.flow
    else
      Mode.balanced
  let sourceBreaks :=
    if rule.useExistingBreaks context segment then
      SourceBreakPolicy.preserve
    else
      SourceBreakPolicy.ignore
  let base :=
    BasePolicy.ofFlags (rule.inheritBase context segment) rule.roundUpBaseIndentation
  let tail :=
    if rule.liftsTailIndentation context segment then
      TailPolicy.lift
    else
      TailPolicy.unchanged
  let breakPoints := normalizeBreakPoints segment (rule.breakPoints context segment)
  let children :=
    segment.indexes.map
      fun index =>
        {
          index
          prefixPolicy :=
            if rule.keepPrefixWithChildFirstLine context segment index then
              PrefixPolicy.keepWithChildFirstLine
            else
              PrefixPolicy.independent
          originalLeading :=
            if rule.formatOriginalChildLeadingBoundary context segment index then
              LeadingBoundaryPolicy.formatWithParent
            else
              LeadingBoundaryPolicy.preserveWithOriginal
        }
  {
    name := rule.name
    mode
    sourceBreaks
    base
    tail
    startAlignment := rule.startAlignment context segment
    breakPoints
    children
  }

def Plan.isAtomic (plan : Plan) : Bool :=
  plan.mode == .atomic

def Plan.isMandatory (plan : Plan) : Bool :=
  plan.mode == .mandatory

def Plan.isFlow (plan : Plan) : Bool :=
  plan.mode == .flow

def Plan.preservesSourceBreaks (plan : Plan) : Bool :=
  plan.sourceBreaks == .preserve

def Plan.inheritsBase (plan : Plan) : Bool :=
  plan.base.inherits

def Plan.roundsUpBase (plan : Plan) : Bool :=
  plan.base.roundsUp

def Plan.liftsTail (plan : Plan) : Bool :=
  plan.tail == .lift

def Plan.childPolicy (plan : Plan) (index : Nat) : ChildBoundaryPlan :=
  plan.children.find? (·.index == index) |>.getD { index }

def Plan.keepsPrefixWithChildFirstLine (plan : Plan) (index : Nat) : Bool :=
  (plan.childPolicy index).prefixPolicy == .keepWithChildFirstLine

def Plan.formatsOriginalLeadingBoundary (plan : Plan) (index : Nat) : Bool :=
  (plan.childPolicy index).originalLeading == .formatWithParent

def Plan.hasBreakAt (plan : Plan) (index : Nat) : Bool :=
  plan.breakPoints.any (·.index == index)

partial def treeStartsWithProjectionChain : SyntaxTree.Tree → Bool
  | .node (.infixChain `Lean.Parser.Term.proj) _ => true
  | .node .application children =>
      children[0]?.any treeStartsWithProjectionChain
  | .node (.raw kind) children =>
      (kind == `Lean.Parser.Term.paren
        || kind == `Lean.Parser.Term.hygienicLParen
        || kind == `null)
      && children.any treeStartsWithProjectionChain
  | _ => false

def treeIsUnbreakableHead (tree : SyntaxTree.Tree) : Bool :=
  tree.singleToken?.isSome
  || treeStartsWithProjectionChain tree
  || (LineBreakRules.ruleFor tree).any (·.atomic)

partial def treeStartsWithSourceBrokenUnbreakableHead (source : String)
    : SyntaxTree.Tree → Bool
  | .node .application children =>
      match children[0]?, children[1]? with
      | some head, some firstArgument =>
          treeIsUnbreakableHead head
          && match head.lastToken?, firstArgument.firstToken? with
              | some left, some right =>
                  (SourceBoundary.betweenTokens source left right).hasLineStructure
              | _, _ => false
      | _, _ => false
  | .node (.raw kind) children =>
      (kind == `Lean.Parser.Term.paren
        || kind == `Lean.Parser.Term.hygienicLParen
        || kind == `null)
      && children.any (treeStartsWithSourceBrokenUnbreakableHead source)
  | _ => false

def treeHasUnbreakableFirstLine (source : String) (tree : SyntaxTree.Tree) (plan : Plan)
    : Bool :=
  tree.singleToken?.isSome
  || plan.isAtomic
  || treeStartsWithProjectionChain tree
  || treeStartsWithSourceBrokenUnbreakableHead source tree

def suffixDelimiterDepthAfter (depth : Nat) (token : SyntaxTree.Token) : Nat :=
  if LineBreakRules.suffixOpeningDelimiterLexeme token.lexeme then
    depth + 1
  else if LineBreakRules.suffixClosingDelimiterLexeme token.lexeme then
    depth - 1
  else
    depth

end LayoutPlan
end Formatter
end LeanFmt
