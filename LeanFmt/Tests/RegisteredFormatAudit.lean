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

private partial def findSyntaxNodes (target : Lean.SyntaxNodeKind) (stx : Lean.Syntax)
    : Array Lean.Syntax :=
  match stx with
  | node@(.node _ kind children) =>
      let nested :=
        children.foldl (fun found child => found ++ findSyntaxNodes target child) #[]
      if kind == target then #[node] ++ nested else nested
  | _ => #[]

def run (env : Lean.Environment) : IO Unit := do
  let tokens :=
    #[
      syntheticToken .ident "first",
      syntheticToken .atom "=",
      syntheticToken .ident "second"
    ]
  let document :=
    Std.Format.group
      (Std.Format.text "first ="
        ++ Std.Format.nest 2 (Std.Format.line ++ Std.Format.text "second"))
  match inspectFormat tokens document with
  | .ok layout =>
      assertTrue "symbolic audit records grouped token boundary and indentation"
        (layout.tokenCount == 3
          && layout.breaks
              == #[
                {
                  tokenIndex := 2
                  indentLevels := 1
                  kind := .soft
                  groups := #[{ id := 0, behavior := .allOrNone }]
                  sourceTags := #[]
                }
              ])
  | .error reason =>
      throw <| IO.userError s!"symbolic format alignment was rejected: {repr reason}"
  match inspectFormat tokens (Std.Format.text "first -> second") with
  | .error (.tokenMismatch 1 "=" "-") => pure ()
  | result =>
      throw <| IO.userError s!"rewritten symbolic token was accepted: {repr result}"
  let alignedDocument :=
    Std.Format.text "first =" ++ Std.Format.align false ++ Std.Format.text "second"
  match inspectFormat tokens alignedDocument with
  | .error (.columnAlignment 2 false) => pure ()
  | result =>
      throw <| IO.userError s!"column-sensitive layout was accepted: {repr result}"
  let source :=
    "def firstAudit := someFunction firstArgument secondArgument\n"
    ++ "def secondAudit := anotherFunction shortArgument finalArgument\n"
  let moduleTree <- Formatter.Internal.parseModuleWithEnv env source
                      "registered-format-audit.lean"
  let applications :=
    findSyntaxNodes `Lean.Parser.Term.app moduleTree.rawSyntax
    |>.filter
        fun stx =>
          match sourceTokensForSyntax moduleTree stx with
          | .ok tokens => tokens.size == 3
          | .error _ => false
  unless applications.size == 2 do
    throw
    <| IO.userError
        s!"registered format audit expected two application nodes, found {applications.size}"
  let audits <-
    applications.mapM
      fun application => do
        let result <- auditSyntax env moduleTree application
                        "registered-format-audit.lean"
        match result with
        | .inferred audit =>
            unless audit.candidate.family == .application
                    && audit.candidate.breaks.size == 2
                    && (audit.candidate.breaks.all
                          fun breakPoint =>
                            breakPoint.policy == .fill)
                    && audit.candidate.nestedBreakCount == 0 do
              throw
              <| IO.userError
                  s!"unexpected registered application rule: {repr audit.candidate}"
            pure audit
        | .rejected reason =>
            throw <| IO.userError s!"registered formatter was not inferred: {repr reason}"
  assertTrue "equivalent registered formatter samples produce one stable rule"
    (stableRuleCandidate? audits).isSome
  let commentedSource :=
    "def auditComment := someFunction firstArgument -- preserve this comment\n"
    ++ "  secondArgument\n"
  let commentedModule <- Formatter.Internal.parseModuleWithEnv env commentedSource
                          "registered-format-comment-audit.lean"
  let some commentedApplication :=
    (findSyntaxNodes `Lean.Parser.Term.app commentedModule.rawSyntax).find?
      fun stx =>
        match sourceTokensForSyntax commentedModule stx with
        | .ok tokens => tokens.size == 3
        | .error _ => false
  | throw <| IO.userError "comment audit input has no application node"
  let commentAudit <- auditSyntax env commentedModule commentedApplication
                        "registered-format-comment-audit.lean"
  match commentAudit with
  | .rejected .sourceComment => pure ()
  | result =>
      throw
      <| IO.userError s!"registered format audit accepted source comment: {repr result}"

end LeanFmt.Tests.RegisteredFormatAudit
