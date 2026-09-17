import LeanFmt.Driver
import LeanFmt.Tests.ProjectSyntax

namespace LeanFmt.Tests.EnvironmentLoading

private def assertTrue (label : String) (value : Bool) : IO Unit := do
  unless value do
    throw <| IO.userError s!"assertion failed: {label}"

def run : IO Unit := do
  let loader ← Driver.loadEnvironmentLoader {}
  assertTrue "loader creation does not import the default environment"
    (← loader.default.get).isNone
  assertTrue "loader creation does not import an exact environment"
    (← loader.lastExact.get).isNone
  IO.FS.withTempDir
    fun root => do
      let ordinary := root / "Ordinary.lean"
      let imported := root / "Imported.lean"
      let ordinarySource := "def ordinary : Nat := 1\n"
      let importedSource :=
        "import LeanFmt.Tests.ProjectSyntax\n\ndef imported := project_syntax\n"
      IO.FS.writeFile ordinary ordinarySource
      IO.FS.writeFile imported importedSource
      let (defaults, imports) ←
        Driver.partitionDefaultEnvironmentFiles loader 2 [ordinary, imported]
      assertTrue "mixed classification retains default and exact ownership"
        (defaults.map (·.1) == [ordinary] && imports == [imported])
      assertTrue "classification does not initialize environments"
        ((← loader.default.get).isNone && (← loader.lastExact.get).isNone)
      let spec ← LeanEnvironment.specForSource importedSource imported.toString
      let exact ← loader.environmentForSpec spec
      assertTrue "explicit imports use an exact environment"
        (match exact.origin with
          | .importedExact => true
          | _ => false)
      let parsed ←
        SyntaxTree.parseModuleStringWithEnv exact.environment importedSource
          imported.toString
      assertTrue "lazy loading retains imported parser syntax"
        (parsed.tree.containsNodeKind (.raw `projectSyntax))
      let reused ← loader.environmentForSpec spec
      assertTrue "exact environments remain cached independently"
        (match reused.origin with
          | .reusedExact => true
          | _ => false)
      assertTrue "exact imports do not initialize the default environment"
        (← loader.default.get).isNone
      let options : Driver.Options :=
        { check := true, checkException := true, checkIdempotent := true }
      assertTrue "empty default batches succeed"
        ((← Driver.formatDefaultEnvironmentFiles loader options []) == 0)
      assertTrue "empty batches do not initialize the default environment"
        (← loader.default.get).isNone
      assertTrue "default-only files still format with all diagnostics"
        ((← Driver.formatDefaultEnvironmentFiles loader options [ordinary]) == 0)
      let some environment ← loader.default.get
      | throw <| IO.userError "default formatting did not populate the cache"
      assertTrue "the cached default environment includes Lean"
        (environment.getModuleIdx? `Lean).isSome
      let marker := `LeanFmt.Tests.CachedDefault
      loader.default.set (some (environment.setMainModule marker))
      let selected ← loader.environmentForSource options ordinarySource ordinary.toString
      assertTrue "default selection reuses the cached environment"
        (selected.mainModule == marker)
      assertTrue "default loading does not discard the exact environment"
        (← loader.lastExactEnvironment? spec.key).isSome
  let worker ← Driver.loadEnvironmentLoader { worker := true }
  let spec ← LeanEnvironment.specForSource "def ordinary : Nat := 1\n" "worker.lean"
  let result ← worker.environmentForSpec spec
  assertTrue "exact workers retain their import lifetime policy" worker.leakExact
  assertTrue "exact workers do not substitute the default environment"
    (match result.origin with
      | .importedExact => true
      | _ => false)
  assertTrue "exact workers leave the default cache empty" (← worker.default.get).isNone

end LeanFmt.Tests.EnvironmentLoading
