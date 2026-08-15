import Lean

syntax (name := projectSyntax) "project_syntax" : term
declare_syntax_cat projectClause
syntax (name := projectInClause) " in " ident : projectClause
syntax "#project_clause" projectClause : command
syntax (name := projectDelimitedConfig) "project_config(" ident " := " ident ")" : term
syntax (name := projectMatrixLiteral) "#pm[" term "," term ";" term "," term "]" : term
syntax:max (name := projectTightIndexed) (priority := high) term noWs "[" term "]" : term
syntax (name := contextClassifiedTactic) "context_classified_tactic " ident ident : tactic
syntax (name := contextTermTactic) "context_term_tactic " term : tactic
syntax (name := projectPrefixedDeclaration) "project_haveI' " letDecl : doElem
syntax (name := projectTermCommand) "#project_term " ident term : command
syntax (name := projectWrappedTerm) "project_wrapped " term : term
syntax (name := projectOptionalTermCommand) "#project_optional " ident (term)? : command
syntax (name := projectWhereTermCommand) "#project_where " ident " where " term : command
elab (name := projectNoteCommand) "#project_note " (docComment)? : command =>
  pure ()

elab (name := projectNoteTactic) "#project_note " (docComment)? : tactic =>
  pure ()

namespace BigOperators

syntax bigOpBinder := ident (" ∈ " term)?
syntax bigOpBinders := bigOpBinder
syntax (name := bigsum) "∑ " bigOpBinders ", " term:67 : term
syntax (name := projectIntegral) "∫ " ident " in " term ", " term " ∂" term : term

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

end Qq
