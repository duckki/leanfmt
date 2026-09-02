import LeanFmt.Formatter.SpaceRules
import Lean.PrettyPrinter.Formatter

namespace LeanFmt.RegisteredFormatAudit

open Lean

/-!
This module is an audit-only adapter for Lean's executable formatter registrations.
It observes a rendered `Std.Format`, but never supplies layout to leanfmt's production
regrouping or rendering pipeline.
-/

structure BreakObservation where
  tokenIndex : Nat
  indentLevels : Nat
deriving BEq, Repr

structure Alignment where
  rendered : String
  tokenCount : Nat
  breaks : Array BreakObservation
deriving BEq, Repr

inductive Rejection where
  | notRegistered
  | missingSourceSpan
  | incompleteSourceCoverage
  | sourceComment
  | formatterFailure (message : String)
  | leadingWhitespace
  | multilineToken (tokenIndex : Nat)
  | tokenMismatch (tokenIndex : Nat) (expected found : String)
  | unsupportedWhitespace (tokenIndex : Nat)
  | unsupportedIndentation (tokenIndex columns : Nat)
  | trailingOutput (text : String)
deriving BEq, Repr

inductive Result where
  | aligned (alignment : Alignment)
  | rejected (reason : Rejection)
deriving BEq, Repr

structure Options where
  lineWidth : Nat := 100
  indentWidth : Nat := 2
  leanOptions : Lean.Options := {}
deriving Inhabited

private def isLayoutWhitespace (char : Char) : Bool :=
  char == ' ' || char == '\t' || char == '\n' || char == '\r'

private def takeLayoutWhitespace : List Char -> List Char × List Char
  | char :: rest =>
      if isLayoutWhitespace char then
        let (space, remaining) := takeLayoutWhitespace rest
        (char :: space, remaining)
      else
        ([], char :: rest)
  | [] => ([], [])

private def consumePrefix : List Char -> List Char -> Option (List Char)
  | [], input => some input
  | expected :: expectedRest, actual :: actualRest =>
      if expected == actual then
        consumePrefix expectedRest actualRest
      else
        none
  | _ :: _, [] => none

private def preview (chars : List Char) : String :=
  String.ofList (chars.take 24)

private def splitAtNewline : List Char -> List Char × List Char
  | '\n' :: rest => ([], rest)
  | char :: rest =>
      let (before, after) := splitAtNewline rest
      (char :: before, after)
  | [] => ([], [])

private def breakIndentation? (tokenIndex indentWidth : Nat) (space : List Char)
    : Except Rejection (Option Nat) := do
  if space.any fun char => char == '\t' || char == '\r' then
    throw <| .unsupportedWhitespace tokenIndex
  let newlineCount := space.count '\n'
  if newlineCount == 0 then
    pure none
  else if newlineCount != 1 then
    throw <| .unsupportedWhitespace tokenIndex
  else
    let (before, after) := splitAtNewline space
    if !before.isEmpty || !after.all (· == ' ') then
      throw <| .unsupportedWhitespace tokenIndex
    let columns := after.length
    if indentWidth == 0 || columns % indentWidth != 0 then
      throw <| .unsupportedIndentation tokenIndex columns
    pure <| some (columns / indentWidth)

def alignRendered
    (tokens : Array SyntaxTree.Token) (rendered : String) (indentWidth : Nat := 2)
    : Result :=
  let rec go
      (tokenIndex : Nat) (remainingTokens : List SyntaxTree.Token)
      (remainingOutput : List Char) (breaks : Array BreakObservation)
      : Result :=
    match remainingTokens with
    | [] =>
        if remainingOutput.isEmpty then
          .aligned { rendered, tokenCount := tokens.size, breaks }
        else
          .rejected (.trailingOutput (preview remainingOutput))
    | token :: rest =>
        if token.lexeme.contains '\n' || token.lexeme.contains '\r' then
          .rejected (.multilineToken tokenIndex)
        else
          let (space, afterSpace) := takeLayoutWhitespace remainingOutput
          if tokenIndex == 0 && !space.isEmpty then
            .rejected .leadingWhitespace
          else
            match breakIndentation? tokenIndex indentWidth space with
            | .error reason => .rejected reason
            | .ok indentation? =>
                match consumePrefix token.lexeme.toList afterSpace with
                | none =>
                    .rejected
                      (.tokenMismatch tokenIndex token.lexeme (preview afterSpace))
                | some remainingOutput =>
                    let breaks :=
                      match indentation? with
                      | some indentLevels =>
                          breaks.push { tokenIndex, indentLevels }
                      | none => breaks
                    go (tokenIndex + 1) rest remainingOutput breaks
  go 0 tokens.toList rendered.toList #[]

def sourceHasInterTokenComment (source : String) (tokens : Array SyntaxTree.Token)
    : Bool :=
  let rec go : List SyntaxTree.Token -> Bool
    | left :: right :: rest =>
        Formatter.SpaceRules.hasCommentStart
          (SyntaxTree.sourceText source left.span.stop right.span.start)
        || go (right :: rest)
    | _ => false
  go tokens.toList

def sourceTokensForSyntax (moduleTree : SyntaxTree.Module) (stx : Syntax)
    : Except Rejection (Array SyntaxTree.Token) := do
  let some start := stx.getPos? (canonicalOnly := true)
  | throw .missingSourceSpan
  let some stop := stx.getTailPos? (canonicalOnly := true)
  | throw .missingSourceSpan
  let tokens :=
    moduleTree.sourceOrderedTokens.filter
      fun token =>
        SyntaxTree.tokenComesFromSource moduleTree.source token
        && start <= token.span.start
        && token.span.stop <= stop
  let some first := tokens[0]?
  | throw .incompleteSourceCoverage
  let some last := tokens.back?
  | throw .incompleteSourceCoverage
  if first.span.start == start && last.span.stop == stop then
    pure tokens
  else
    throw .incompleteSourceCoverage

private def registeredFormat
    (env : Environment) (source fileName : String) (stx : Syntax)
    (options : Lean.Options)
    : IO (Except String Std.Format) := do
  let context : Core.Context :=
    {
      fileName
      fileMap := FileMap.ofString source
      options
      ref := stx
    }
  let state : Core.State := { env }
  try
    let action :=
      PrettyPrinter.format (PrettyPrinter.Formatter.formatterForKind stx.getKind) stx
    let (document, _) <- Core.CoreM.toIO action context state
    pure <| .ok document
  catch exception =>
    pure <| .error (toString exception)

def auditSyntax
    (env : Environment) (moduleTree : SyntaxTree.Module) (stx : Syntax)
    (fileName : String := "<registered-format-audit>") (options : Options := {})
    : IO Result := do
  if ParserLayout.metadataSourceForKind env stx.getKind != .registered then
    pure <| .rejected .notRegistered
  else
    match sourceTokensForSyntax moduleTree stx with
    | .error reason => pure <| .rejected reason
    | .ok tokens =>
        if sourceHasInterTokenComment moduleTree.source tokens then
          pure <| .rejected .sourceComment
        else
          let formatted <- registeredFormat env moduleTree.source fileName stx
                            options.leanOptions
          match formatted with
          | .error message => pure <| .rejected (.formatterFailure message)
          | .ok document =>
              pure <| alignRendered tokens (Std.Format.pretty document options.lineWidth)

end LeanFmt.RegisteredFormatAudit
