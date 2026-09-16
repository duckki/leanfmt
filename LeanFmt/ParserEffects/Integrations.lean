import LeanFmt.ParserEffects

namespace LeanFmt.ParserEffects

open Lean

inductive Integration where
  | leanBench
deriving BEq, Repr

def Integration.name : Integration → String
  | .leanBench => "lean-bench"

def Integration.ofName? : String → Option Integration
  | "lean-bench" => some .leanBench
  | _ => none

/-- A compatibility fingerprint of the imported declarations, not a security hash. -/
def moduleFingerprint? (env : Environment) (moduleName : Name) : Option UInt64 := do
  let index ← env.getModuleIdx? moduleName
  let data ← env.header.moduleData[index.toNat]?
  return data.constants.foldl (init := 0)
    fun result info =>
      mixHash result (hash (info.name, info.levelParams, info.type, info.value? true))

def checkModuleFingerprints (env : Environment) (integration : Integration)
    (auditedModules : List (Name × List UInt64))
    : Except String Unit := do
  for (name, expected) in auditedModules do
    unless (moduleFingerprint? env name).any expected.contains do
      throw
        s!"parser integration {integration.name}: unaudited implementation of {name}; disable the integration or audit this version"

private def applyLeanBench (env : Environment) : Except String Environment := do
  if (env.getModuleIdx? `LeanBench.Setup).isNone then
    return env
  -- lean-bench fa30c2763cf523f3ac8e46dc3a1dad0845a40098, Lean 4.33.0-rc1.
  -- Setup generates ordinary defs and runtime registry initializers; Env's
  -- register/registerFixed update IO refs, not parser extensions or scopes.
  -- The private and exported import views contain different declaration data.
  let auditedModules : List (Name × List UInt64) :=
    [
      (`LeanBench.Core, [16369158626939951246, 6933624278038236923]),
      (`LeanBench.Env, [11655025511616254456, 18025155142193163064]),
      (`LeanBench.Setup, [17454409488819664854, 2807035389963998951])
    ]
  checkModuleFingerprints env .leanBench auditedModules
  let env ← registerNeutralHandler env `LeanBench.elabSetupBenchmark
  registerNeutralHandler env `LeanBench.elabSetupFixedBenchmark

def Integration.apply : Integration → Environment → Except String Environment
  | .leanBench => applyLeanBench

def applyIntegrations (env : Environment) (integrations : List Integration)
    : Except String Environment :=
  integrations.foldlM (fun env integration => integration.apply env) env

end LeanFmt.ParserEffects
