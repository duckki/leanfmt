module

public meta import Lean

public meta section

namespace LeanFmt.ParserEffects

open Lean

/-!
A neutral handler may generate declarations, but must not change the parser's
grammar, token table, or scope. Its effects are deferred, not discarded: a later
unclassified command still replays the complete pending prefix.
-/

initialize neutralHandlers : SimplePersistentEnvExtension Name NameSet ←
  registerSimplePersistentEnvExtension {
    name := `LeanFmt.ParserEffects.neutralHandlers
    addEntryFn := fun handlers name => handlers.insert name
    addImportedFn :=
      fun entries =>
        entries.foldl (fun handlers names => names.foldl (·.insert ·) handlers) {}
  }

/-- Register an audited implementation, never a syntax kind or keyword. -/
def registerNeutralHandler (env : Environment) (handler : Name)
    : Except String Environment := do
  unless env.contains handler do
    throw s!"unknown parser-neutral handler: {handler}"
  return neutralHandlers.addEntry env handler

def isNeutralHandler (env : Environment) (handler : Name) : Bool :=
  (neutralHandlers.getState env).contains handler

initialize registerBuiltinAttribute {
  name := `leanfmt_parser_neutral
  descr := "the command or macro handler has no persistent parser effects"
  add :=
    fun handler stx kind => do
      Attribute.Builtin.ensureNoArgs stx
      unless kind == .global do
        throwError "leanfmt_parser_neutral requires a global registration"
      match registerNeutralHandler (← getEnv) handler with
      | .ok env => setEnv env
      | .error message => throwError message
}

end LeanFmt.ParserEffects
