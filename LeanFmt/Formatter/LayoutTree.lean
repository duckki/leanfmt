import LeanFmt.Formatter.SourceBoundary

namespace LeanFmt.Formatter.LayoutTree

open SyntaxTree

private def prependElseToClause (elseKeyword : Tree) (parts : Array Tree)
    : Option (Array Tree) := do
  let .node .ifThenElseClause children ← parts[0]? | none
  some <| parts.set! 0 (.node .ifThenElseClause (#[elseKeyword] ++ children))

private def continuationParts? (source : String) (parts : Array Tree)
    : Option (Array Tree) := do
  if parts.size != 4 then
    none
  let delimiter ← parts[2]?
  let .node (.ifThenElseChain _) continuation ← parts[3]? | none
  let left ← delimiter.lastToken?
  let right ← continuation[0]? >>= Tree.firstToken?
  if (SourceBoundary.betweenTokens source left right).commentForcesBreak then
    none
  prependElseToClause delimiter continuation

/-- Flatten one uninterrupted run before visiting its children, so long chains
do not repeatedly prepare and copy their complete continuation tails. -/
private partial def chainParts (source : String) (parts : Array Tree) (acc : Array Tree)
    : Array Tree :=
  match continuationParts? source parts with
  | some continuation =>
      chainParts source continuation (acc.push parts[0]! |>.push parts[1]!)
  | none => acc ++ parts

private partial def prepare? (source : String) : Tree → Option Tree
  | .node kind children =>
      let joined? :=
        match kind with
        | .ifThenElseChain _ => do
            let continuation ← continuationParts? source children
            some <| chainParts source continuation #[children[0]!, children[1]!]
        | _ => none
      Id.run do
        let mut prepared := joined?.getD children
        let mut changed := joined?.isSome
        for index in [:prepared.size] do
          if let some child := prepare? source prepared[index]! then
            prepared := prepared.set! index child
            changed := true
        return if changed then some (.node kind prepared) else none
  | _ => none

/-- Source-boundary-sensitive layout preparation shares unchanged syntax subtrees.
Only uninterrupted conditional continuations acquire a balanced layout owner. -/
def prepare (source : String) (tree : Tree) : Tree :=
  (prepare? source tree).getD tree

end LeanFmt.Formatter.LayoutTree
