import LeanFmt.Formatter.LayoutPlan
import LeanFmt.Formatter.OriginalTree
import LeanFmt.Formatter.Rebase
import LeanFmt.Formatter.SourceBoundary

namespace LeanFmt.Tests.LayoutArchitecture

def assertTrue (label : String) (value : Bool) : IO Unit := do
  unless value do
    throw <| IO.userError s!"assertion failed: {label}"

def assertSourceBoundaryFacts : IO Unit := do
  let lineComment := Formatter.SourceBoundary.ofText " -- attached\n  "
  assertTrue "line comments force physical breaks" lineComment.commentForcesBreak
  assertTrue "attached comments do not start on a source line"
    (!lineComment.startsOnNewLine)
  let inlineBlock := Formatter.SourceBoundary.ofText " /- inline -/ "
  assertTrue "single-line block comments do not force breaks"
    (!inlineBlock.commentForcesBreak)
  let multilineBlock := Formatter.SourceBoundary.ofText " /- first\nsecond -/ "
  assertTrue "multiline block comments force breaks" multilineBlock.commentForcesBreak
  let separated := Formatter.SourceBoundary.ofText "\n  -- trailing\n\n  -- leading\n\n  "
  assertTrue "blank-separated comment groups remain explicit"
    separated.hasSeparatedCommentGroups
  assertTrue "boundary records a trailing blank" separated.endsBeforeBlankLine

def assertResolvedLayoutPlan : IO Unit := do
  let application := SyntaxTree.Tree.node .application #[]
  let segment := Formatter.LineBreakRules.Segment.ofTree application
  let plan := Formatter.LayoutPlan.resolve {} segment
  assertTrue "applications resolve to flow mode" plan.isFlow
  assertTrue "resolved plan owns source-break policy" (!plan.preservesSourceBreaks)
  assertTrue "resolved breakpoints stay inside their segment"
    (plan.breakPoints.all
      fun point => segment.start <= point.index && point.index < segment.stop)

def assertOriginalIslandPolicies : IO Unit := do
  let proof := Formatter.OriginalTree.planForKind .proof
  assertTrue "proof islands retain relative layout"
    (proof.policy.relativeLayout == .retain)
  assertTrue "proof islands use pending structural indentation"
    (proof.policy.pendingIndent == .useWhenAvailable)
  assertTrue "proof islands expose unbreakable physical lines"
    (proof.policy.firstLine == .unbreakable)
  let calcPlan := Formatter.OriginalTree.planForKind .calc
  assertTrue "calc islands delegate their leading boundary"
    (calcPlan.policy.leadingBoundary == .formatStructurally)

def assertRebaseAnchor : IO Unit := do
  let movedRight : Formatter.Rebase.Anchor := { sourceColumn := 4, outputColumn := 8 }
  assertTrue "rebase anchors shift source columns together"
    (movedRight.shiftColumn 10 == 14)
  let movedLeft : Formatter.Rebase.Anchor := { sourceColumn := 8, outputColumn := 4 }
  assertTrue "rebase anchors shift left without underflow" (movedLeft.shiftColumn 2 == 0)

def run : IO Unit := do
  assertSourceBoundaryFacts
  assertResolvedLayoutPlan
  assertOriginalIslandPolicies
  assertRebaseAnchor

end LeanFmt.Tests.LayoutArchitecture
