module

public import Lean

public meta section

namespace ProjectInfixSpacing

scoped notation:65 (name := tight) a:65 "⁄" b:66 => Nat.add a b
scoped notation:65 (name := leftTight) a:65 "~!~ " b:66 => Nat.add a b
scoped notation:65 (name := rightTight) a:65 " ~?~" b:66 => Nat.add a b
scoped notation:65 (name := spaced) a:65 " ~+~ " b:66 => Nat.add a b
syntax:65 (name := explicitSpaces) term:65 ppSpace "~:~" ppSpace term:66 : term
syntax:65 (name := opaqueOperand) term:65 "~#~" atomic(term:66) : term
syntax:65 (name := overridden) term:65 "~%~" term:66 : term

@[formatter ProjectInfixSpacing.overridden]
def overriddenFormatter : Lean.PrettyPrinter.Formatter := pure ()

end ProjectInfixSpacing
