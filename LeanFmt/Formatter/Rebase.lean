namespace LeanFmt
namespace Formatter
namespace Rebase

/-- A source-layout column and the output column to which it has moved. -/
structure Anchor where
  sourceColumn : Nat := 0
  outputColumn : Nat := 0
deriving BEq, Repr

def Anchor.shiftColumn (anchor : Anchor) (sourceColumn : Nat) : Nat :=
  if anchor.sourceColumn <= anchor.outputColumn then
    sourceColumn + (anchor.outputColumn - anchor.sourceColumn)
  else
    sourceColumn - min sourceColumn (anchor.sourceColumn - anchor.outputColumn)

end Rebase
end Formatter
end LeanFmt
