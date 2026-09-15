import Lean
import Init.Tactics

syntax (name := projectSyntax) "project_syntax" : term
syntax (name := lemma) (priority := default + 1) declModifiers
  group("lemma " declId ppIndent(declSig) declVal) : command
syntax (name := projectTypeStar) "Type*" : term
syntax "ring1" : tactic
namespace Batteries.Tactic.Alias
syntax (name := aliasLR) declModifiers "alias "
  "⟨" Lean.Parser.Term.binderIdent ", " Lean.Parser.Term.binderIdent "⟩" " := " ident : command
end Batteries.Tactic.Alias
namespace Mathlib.Notation3
open Lean Parser Command
syntax foldKind := &"foldl" <|> &"foldr"
syntax bindersItem := atomic("(" "..." ")")
syntax foldAction := "(" ident ppSpace strLit "*" (precedence)? " => " foldKind
  " (" ident ppSpace ident " => " term ") " term ")"
syntax identOptScoped :=
  ident (notFollowedBy(":" "(" "scoped") precedence)? (":" "(" "scoped " ident " => " term ")")?
syntax notation3Item := strLit <|> bindersItem <|> identOptScoped <|> foldAction
syntax prettyPrintOpt := "(" &"prettyPrint" " := " (&"true" <|> &"false") ")"
syntax (name := notation3) (docComment)? (Term.attributes)? Term.attrKind
  "notation3" (precedence)? (namedName)? (namedPrio)?
  (ppSpace prettyPrintOpt)? (ppSpace notation3Item)+ " => " term : command
end Mathlib.Notation3
syntax (name := projectBigSum) "psum " ident " in " term ", " term : term
namespace Mathlib.Tactic.TermCongr
syntax (name := termCongr) "pcongr(" "$" term ")" : term
end Mathlib.Tactic.TermCongr
declare_syntax_cat projectClause
syntax (name := projectInClause) " in " ident : projectClause
syntax "#project_clause" projectClause : command
syntax (name := projectDelimitedConfig) "project_config(" ident " := " ident ")" : term
syntax (name := projectMatrixLiteral) "#pm[" term "," term ";" term "," term "]" : term
syntax "project_generated(" term ", " term ")" : term
syntax:max (name := projectTightIndexed) (priority := high) term noWs "[" term "]" : term
syntax (name := contextClassifiedTactic) "context_classified_tactic " ident ident : tactic
syntax (name := contextTermTactic) "context_term_tactic " term : tactic
syntax (name := projectSaysTactic) "project_simp? " term " says " tacticSeq : tactic
syntax (name := projectHeaderClauseTactic)
  "project_filter_upwards" (" [" term,* "]")?
  (" with" (ppSpace colGt term:max)*)? (" using " term)? : tactic
declare_syntax_cat projectProofSeq
syntax (name := projectProofStep) "project_step " ident : projectProofSeq
syntax (name := projectOpaqueArrowTactic)
  "project_conv_lhs" " => " projectProofSeq : tactic
syntax (name := projectConversionLeft)
  "project_lhs" (" at " ident)? (" in " (Lean.Parser.Tactic.Conv.occs)? term)?
  " => " Lean.Parser.Tactic.Conv.convSeq : tactic
syntax (name := projectConversionRight)
  "project_rhs" (" at " ident)? (" in " (Lean.Parser.Tactic.Conv.occs)? term)?
  " => " Lean.Parser.Tactic.Conv.convSeq : tactic
syntax (name := projectTryTactic) "project_try? " term : tactic
syntax (name := projectOptionalSaysTactic)
  tactic " project_says" (colGt tacticSeq)? : tactic
syntax (name := projectPrefixedDeclaration) "project_haveI' " letDecl : doElem
syntax (name := projectConfiguredPrefixedDeclaration)
  "project_have_config' " ("[" ident "] ")? letDecl : doElem
syntax (name := projectTermCommand) "#project_term " ident term : command
syntax (name := projectWrappedTerm) "project_wrapped " term : term
syntax (name := projectAnnotatedApplication) "project_apply" ppSpace term : term
syntax (name := projectAnnotatedLayout)
  ppGroup("project_layout" ppSpace term) ppLine ppIndent(term) : term
syntax (name := projectOptionalTermCommand) "#project_optional " ident (term)? : command
syntax (name := projectWhereTermCommand) "#project_where " ident " where " term : command
syntax (name := projectLemma) (priority := default + 1) declModifiers
  group("project_lemma " declId ppIndent(declSig) declVal) : command
syntax (name := projectSignatureOnlyDeclaration)
  "project_signature " declId ppIndent(declSig) : command
elab (name := projectNoteCommand) "#project_note " (docComment)? : command =>
  pure ()

elab (name := projectNoteTactic) "#project_note " (docComment)? : tactic =>
  pure ()

syntax (name := projectNoteTerm) "#project_note " (docComment)? term : term

namespace BigOperators

syntax bigOpBinder := ident (" ∈ " term)?
syntax bigOpBinders := bigOpBinder
syntax (name := bigsum) "∑ " bigOpBinders ", " term:67 : term
syntax (name := projectIntegral) "∫ " ident " in " term ", " term " ∂" term : term
syntax (name := projectIntervalIntegral) "∫ " ident " in " term ".." term ", " term : term

end BigOperators

syntax (name := projectIndexedSup) "⨆ " ident " : " term ", " term : term
syntax (name := projectModifiedForall) "∀ᵉ " ident " ∈ " term ", " term : term

namespace ProjectGenerated

scoped elab:max "TestScopedHead%" ppSpace first:term:arg ppSpace _second:term:arg ppSpace
    _third:term:arg : term =>
  Lean.Elab.Term.elabTerm first none

end ProjectGenerated

namespace Qq

scoped syntax (name := «termQ(__)») "q(" term (" : " term)? ")" : term
scoped syntax (name := «termQ(__)_1») "q1(" term ")" : term

end Qq
