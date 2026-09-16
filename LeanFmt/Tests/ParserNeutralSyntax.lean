module

public meta import LeanFmt.ParserEffects

public meta section

open Lean Elab Command

namespace LeanFmt.Tests.ParserNeutralSyntax

syntax (name := neutralDeclaration) "neutralDeclaration " ident : command

@[command_elab LeanFmt.Tests.ParserNeutralSyntax.neutralDeclaration, leanfmt_parser_neutral]
def elabNeutralDeclaration : CommandElab :=
  fun stx => do
    match stx with
    | `(neutralDeclaration $name:ident) => elabCommand (← `(def $name := 7))
    | _ => throwUnsupportedSyntax

syntax (name := neutralMacro) "neutralMacro " ident : command

@[macro LeanFmt.Tests.ParserNeutralSyntax.neutralMacro, leanfmt_parser_neutral]
def expandNeutralMacro : Macro :=
  fun stx => do
    match stx with
    | `(neutralMacro $name:ident) => `(def $name := 8)
    | _ => Macro.throwUnsupported

end LeanFmt.Tests.ParserNeutralSyntax
