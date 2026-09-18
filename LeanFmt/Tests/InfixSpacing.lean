import LeanFmt
import LeanFmt.Tests.InfixSyntax

namespace LeanFmt.Tests.InfixSpacing

open Lean

private def assertTrue (label : String) (condition : Bool) : IO Unit := do
  unless condition do
    throw <| IO.userError s!"infix-spacing assertion failed: {label}"

private def assertFormatting (env : Environment) (source expected : String)
    (width : Nat := 90)
    : IO Unit := do
  let source := "open scoped ProjectInfixSpacing\n\n" ++ source
  let options : Formatter.Options := { lineWidth := width }
  let result <- Formatter.formatSourceWithEnvDetailed env source "infix-spacing.lean"
                  options
  assertTrue "no safety fallback" (!result.fellBack)
  assertTrue s!"expected {expected} in\n{result.formatted}"
    ((result.formatted.splitOn expected).length > 1)
  let before <- SyntaxTree.parseModuleStringWithEnv env source
  let after <- SyntaxTree.parseModuleStringWithEnv env result.formatted
  assertTrue "preservation and width"
    (Formatter.Diagnostics.formattingSafetyExceptions before after options).isEmpty
  let again <- Formatter.formatSourceWithEnv env result.formatted
                "infix-spacing-again.lean" options
  assertTrue "independent idempotency" (again == result.formatted)

def run (level : OLeanLevel := .private) : IO Unit := do
  let env <- SyntaxTree.importEnvironment #[{ module := `LeanFmt.Tests.InfixSyntax }]
              (level := level)
  for (kind, before, after)
      in [
        (`ProjectInfixSpacing.tight, true, true),
        (`ProjectInfixSpacing.leftTight, true, false),
        (`ProjectInfixSpacing.rightTight, false, true),
        (`ProjectInfixSpacing.spaced, false, false),
        (`«term_+_», false, false),
        (`«term_^_», false, false)
      ] do
    assertTrue s!"{kind} has explicit boundary spacing"
      ((ParserLayout.kindFacts env {} kind).infixSpacing?
        == some { tightBefore := before, tightAfter := after })
  for kind
      in [
        `unknownInfixKind,
        `ProjectInfixSpacing.explicitSpaces,
        `ProjectInfixSpacing.opaqueOperand,
        `ProjectInfixSpacing.overridden
      ] do
    assertTrue s!"{kind} does not infer tightness from unavailable metadata"
      (ParserLayout.kindFacts env {} kind).infixSpacing?.isNone
  for (input, expected)
      in [
        ("1⁄2", "1⁄2"),
        ("1⁄2 ~+~3⁄4", "1⁄2 ~+~ 3⁄4"),
        ("1~+~2⁄3", "1 ~+~ 2⁄3"),
        ("1~!~2 ~?~3", "1~!~ 2 ~?~3"),
        ("1+2*3^4", "1 + 2 * 3 ^ 4"),
        ("1 ⁄ 2", "1 ⁄ 2"),
        ("1~#~2", "1 ~#~ 2"),
        ("1~:~2", "1 ~:~ 2"),
        ("1~%~2", "1 ~%~ 2"),
        ("1 /- keep -/⁄2", " /- keep -/⁄2"),
        ("1⁄ -- keep the source break\n  2", "-- keep the source break\n")
      ] do
    assertFormatting env s!"def target := {input}\n" expected
  assertFormatting env
    "example (W F : Nat) (h : W⁄F = 0) : W⁄F = 0 := h\n"
    "(h : W⁄F = 0)"
  assertFormatting env
    "def wrapped := firstLongOperandName⁄secondLongOperandName ~+~ thirdLongOperandName⁄fourthLongOperandName\n"
    "⁄fourthLongOperandName" 48
  let tree <- SyntaxTree.parseModuleStringWithEnv env
                "open scoped ProjectInfixSpacing\n\ndef mixed := 1⁄2 ~+~ 3⁄4\n"
  assertTrue "mixed spacing keeps equal-precedence flattening"
    (tree.tree.firstInfixChainChildCount? `ProjectInfixSpacing.tight == some 7)

end LeanFmt.Tests.InfixSpacing
