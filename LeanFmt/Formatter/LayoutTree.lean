import LeanFmt.Formatter.SourceBoundary

namespace LeanFmt.Formatter.LayoutTree

open SyntaxTree

structure RetryOwner where
  tree : Tree
  disabled : Std.HashSet Nat
  boundaries : SourceBoundary.Cache := {}
deriving Repr

structure Prepared where
  tree : Tree
  /-- UTF-8 source offsets of tokens joined to the immediately preceding token. -/
  guardedJoins : Std.HashSet Nat := {}
  /-- Original owners at paths in the prepared view, for subtree-local retries. -/
  retryOwners : Array (List Nat × RetryOwner) := #[]
  boundaries : SourceBoundary.Cache := {}

private structure PreparationState where
  guardedJoins : Std.HashSet Nat := {}
  retryOwners : Array (List Nat × RetryOwner) := #[]
  boundaries : SourceBoundary.Cache := {}

private def prependElseToClause (elseKeyword : Tree) (parts : Array Tree)
    : Option (Array Tree) := do
  let .node .ifThenElseClause children ← parts[0]? | none
  some <| parts.set! 0 (.node .ifThenElseClause (#[elseKeyword] ++ children))

private def continuationParts? (source : String) (disabled : Std.HashSet Nat)
    (parts : Array Tree)
    : StateM PreparationState (Option (Array Tree × Option Nat)) := do
  let tokens? : Option (Tree × Array Tree × Token × Token) := do
    if parts.size != 4 then none
    let delimiter ← parts[2]?
    let .node (.ifThenElseChain _) continuation ← parts[3]? | none
    let left ← delimiter.lastToken?
    let right ← continuation[0]? >>= Tree.firstToken?
    some (delimiter, continuation, left, right)
  let some (delimiter, continuation, left, right) := tokens? | return none
  if disabled.contains right.span.start.byteIdx then return none
  let (boundary, boundaries) :=
    SourceBoundary.cachedFacts source left right (← get).boundaries
  modify fun state => { state with boundaries }
  if boundary.commentForcesBreak then return none
  return do
    let joined ← prependElseToClause delimiter continuation
    some (joined, if boundary.hasComment then some right.span.start.byteIdx else none)

/-- Flatten one uninterrupted run before visiting its children, so long chains
do not repeatedly prepare and copy their complete continuation tails. -/
private partial def chainParts (source : String) (disabled : Std.HashSet Nat)
    (parts : Array Tree) (acc : Array Tree)
    : StateM PreparationState (Array Tree) := do
  match ← continuationParts? source disabled parts with
  | some (continuation, guard?) =>
      if let some guard := guard? then
        modify fun state => { state with guardedJoins := state.guardedJoins.insert guard }
      chainParts source disabled continuation (acc.push parts[0]! |>.push parts[1]!)
  | none => pure (acc ++ parts)

private partial def prepare? (source : String) (disabled : Std.HashSet Nat)
    (path : List Nat)
    : Tree → StateM PreparationState (Option Tree)
  | .node kind children => do
      let guardCount := (← get).guardedJoins.size
      let joined? : Option (Array Tree) ←
        match kind with
        | .ifThenElseChain _ => do
            let some (continuation, guard?) ← continuationParts? source disabled children
            | pure none
            if let some guard := guard? then
              modify
                fun state =>
                  { state with guardedJoins := state.guardedJoins.insert guard }
            let joined ←
              chainParts source disabled continuation #[children[0]!, children[1]!]
            pure (some joined)
        | _ => pure none
      if guardCount < (← get).guardedJoins.size then
        modify
          fun state =>
            {
              state with
                retryOwners :=
                  state.retryOwners.push
                    (path.reverse, { tree := .node kind children, disabled })
            }
      let mut prepared := joined?.getD children
      let mut changed := joined?.isSome
      for index in [:prepared.size] do
        if let some child ← prepare? source disabled (index :: path) prepared[index]! then
          prepared := prepared.set! index child
          changed := true
      return if changed then some (.node kind prepared) else none
  | _ => pure none

/-- Source-boundary-sensitive layout preparation shares unchanged syntax subtrees.
Only uninterrupted conditional continuations acquire a balanced layout owner. -/
def prepare (source : String) (tree : Tree) (disabled : Std.HashSet Nat := {})
    (boundaries : SourceBoundary.Cache := {})
    : Prepared :=
  let (prepared?, state) := (prepare? source disabled [] tree).run { boundaries }
  {
    tree := prepared?.getD tree,
    guardedJoins := state.guardedJoins,
    retryOwners :=
      state.retryOwners.map
        fun (path, owner) =>
          (path, { owner with boundaries := state.boundaries })
    boundaries := state.boundaries
  }

end LeanFmt.Formatter.LayoutTree
