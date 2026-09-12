import LeanFmt.Formatter.SourceBoundary

namespace LeanFmt.Formatter.LayoutTree

open SyntaxTree

structure Prepared where
  tree : Tree
  /-- UTF-8 source offsets of tokens joined to the immediately preceding token. -/
  guardedJoins : Std.HashSet Nat := {}

private def prependElseToClause (elseKeyword : Tree) (parts : Array Tree)
    : Option (Array Tree) := do
  let .node .ifThenElseClause children ← parts[0]? | none
  some <| parts.set! 0 (.node .ifThenElseClause (#[elseKeyword] ++ children))

private def continuationParts? (source : String) (disabled : Std.HashSet Nat)
    (parts : Array Tree)
    : Option (Array Tree × Option Nat) := do
  if parts.size != 4 then
    none
  let delimiter ← parts[2]?
  let .node (.ifThenElseChain _) continuation ← parts[3]? | none
  let left ← delimiter.lastToken?
  let right ← continuation[0]? >>= Tree.firstToken?
  let boundary := SourceBoundary.betweenTokens source left right
  if disabled.contains right.span.start.byteIdx || boundary.commentForcesBreak then
    none
  let joined ← prependElseToClause delimiter continuation
  some (joined, if boundary.hasComment then some right.span.start.byteIdx else none)

/-- Flatten one uninterrupted run before visiting its children, so long chains
do not repeatedly prepare and copy their complete continuation tails. -/
private partial def chainParts (source : String) (disabled : Std.HashSet Nat)
    (parts : Array Tree) (acc : Array Tree)
    : StateM (Std.HashSet Nat) (Array Tree) := do
  match continuationParts? source disabled parts with
  | some (continuation, guard?) =>
      if let some guard := guard? then modify (·.insert guard)
      chainParts source disabled continuation (acc.push parts[0]! |>.push parts[1]!)
  | none => pure (acc ++ parts)

private partial def prepare? (source : String) (disabled : Std.HashSet Nat)
    : Tree → StateM (Std.HashSet Nat) (Option Tree)
  | .node kind children => do
      let joined? : Option (Array Tree) ←
        match kind with
        | .ifThenElseChain _ => do
            let some (continuation, guard?) := continuationParts? source disabled children
            | pure none
            if let some guard := guard? then modify (·.insert guard)
            let joined ←
              chainParts source disabled continuation #[children[0]!, children[1]!]
            pure (some joined)
        | _ => pure none
      let mut prepared := joined?.getD children
      let mut changed := joined?.isSome
      for index in [:prepared.size] do
        if let some child ← prepare? source disabled prepared[index]! then
          prepared := prepared.set! index child
          changed := true
      return if changed then some (.node kind prepared) else none
  | _ => pure none

/-- Source-boundary-sensitive layout preparation shares unchanged syntax subtrees.
Only uninterrupted conditional continuations acquire a balanced layout owner. -/
def prepare (source : String) (tree : Tree) (disabled : Std.HashSet Nat := {})
    : Prepared :=
  let (prepared?, guardedJoins) := (prepare? source disabled tree).run {}
  { tree := prepared?.getD tree, guardedJoins }

end LeanFmt.Formatter.LayoutTree
