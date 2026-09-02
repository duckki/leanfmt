import LeanFmt.Formatter
import LeanFmt.RegisteredFormatAudit

namespace LeanFmt.Tests.RegisteredFormatAudit

open LeanFmt.RegisteredFormatAudit

private def assertTrue (label : String) (value : Bool) : IO Unit := do
  unless value do
    throw <| IO.userError s!"assertion failed: {label}"

private def syntheticToken (role : SyntaxTree.TokenRole) (lexeme : String)
    : SyntaxTree.Token :=
  SyntaxTree.tokenOfSynthetic role Lean.identKind lexeme 0 0

private partial def findSyntaxNode? (target : Lean.SyntaxNodeKind)
    : Lean.Syntax -> Option Lean.Syntax
  | stx@(.node _ kind children) =>
      if kind == target then
        some stx
      else
        children.foldl
          (fun found child => found.orElse fun _ => findSyntaxNode? target child)
          none
  | _ => none

def run (env : Lean.Environment) : IO Unit := do
  let tokens :=
    #[
      syntheticToken .ident "first",
      syntheticToken .atom "=",
      syntheticToken .ident "second"
    ]
  match alignRendered tokens "first =\n  second" with
  | .aligned alignment =>
      assertTrue "registered format audit records token-indexed indentation"
        (alignment.tokenCount == 3
          && alignment.breaks == #[{ tokenIndex := 2, indentLevels := 1 }])
  | .rejected reason =>
      let message := s!"exact registered format alignment was rejected: {repr reason}"
      throw <| IO.userError message
  match alignRendered tokens "first -> second" with
  | .rejected (.tokenMismatch 1 "=" _) => pure ()
  | result =>
      let message := s!"rewritten registered format token was accepted: {repr result}"
      throw <| IO.userError message
  match alignRendered tokens "first =\n   second" with
  | .rejected (.unsupportedIndentation 2 3) => pure ()
  | result =>
      let message :=
        s!"non-level registered format indentation was accepted: {repr result}"
      throw <| IO.userError message
  let source := "def auditValue := someFunction firstArgument secondArgument\n"
  let moduleTree <- Formatter.Internal.parseModuleWithEnv env source
                      "registered-format-audit.lean"
  let some application := findSyntaxNode? `Lean.Parser.Term.app moduleTree.rawSyntax
  | throw <| IO.userError "registered format audit input has no application node"
  let applicationAudit <- auditSyntax env moduleTree application
                            "registered-format-audit.lean" { lineWidth := 20 }
  match applicationAudit with
  | .aligned alignment =>
      assertTrue "registered Lean formatter aligns its original application tokens"
        (alignment.tokenCount == 3 && !alignment.breaks.isEmpty)
  | .rejected reason =>
      throw <| IO.userError s!"registered Lean formatter did not align: {repr reason}"
  let commentedSource :=
    "def auditComment := someFunction firstArgument -- preserve this comment\n"
    ++ "  secondArgument\n"
  let commentedModule <- Formatter.Internal.parseModuleWithEnv env commentedSource
                          "registered-format-comment-audit.lean"
  let some commentedApplication :=
    findSyntaxNode? `Lean.Parser.Term.app commentedModule.rawSyntax
  | throw <| IO.userError "comment audit input has no application node"
  let commentAudit <- auditSyntax env commentedModule commentedApplication
                        "registered-format-comment-audit.lean"
  match commentAudit with
  | .rejected .sourceComment => pure ()
  | result =>
      let message := s!"registered format audit accepted source comment: {repr result}"
      throw <| IO.userError message

end LeanFmt.Tests.RegisteredFormatAudit
