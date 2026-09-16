import LeanFmt
import LeanFmt.Cli
import LeanFmt.Tests.ParserNeutralSyntax

namespace LeanFmt.Tests.ParserEffects

open Lean

private def assertTrue (label : String) (condition : Bool) : IO Unit := do
  unless condition do
    throw <| IO.userError s!"parser-effects assertion failed: {label}"

private def initialState (env : Environment) (input : Parser.InputContext)
    : IO SyntaxTree.ModuleParseState := do
  let (_, parserState, messages) ← Parser.parseHeader input
  SyntaxTree.checkParserMessages messages
  return { parserState, commandState := Elab.Command.mkState env }

private def assertElaborates (env : Environment) (source : String) : IO Unit := do
  let input := Parser.mkInputContext source "parser-effects.lean"
  let initial ← initialState env input
  let snapshot ←
    Language.Lean.processCommands input initial.parserState initial.commandState
  for leaf in (Language.toSnapshotTree snapshot.get).getAll do
    SyntaxTree.checkParserMessages leaf.diagnostics.msgLog

private def assertDeferredObservers (env : Environment) : IO Unit := do
  let sourcePrefix :=
    (if env.header.isModule then "public section\n" else "")
    ++ "namespace NeutralEffects\n"
    ++ "theorem evidence : True := by exact True.intro\n"
    ++ "neutralDeclaration generated\n"
    ++ "neutralMacro expanded\n"
    ++ "end NeutralEffects\n"
  let input := Parser.mkInputContext sourcePrefix "neutral-prefix.lean"
  let initial ← initialState env input
  let deferred ← SyntaxTree.parseModuleCommandsQuiet input initial true initial
  for name
      in [
        `NeutralEffects.evidence,
        `NeutralEffects.generated,
        `NeutralEffects.expanded
      ] do
    assertTrue "neutral commands do not elaborate the pending prefix"
      (!deferred.commandState.env.contains name)
  let observer :=
    "open Lean Elab Command\n"
    ++ "run_cmd do\n"
    ++ "  let some (.thmInfo proof) := (← getEnv).find? `NeutralEffects.evidence\n"
    ++ "    | throwError \"missing theorem\"\n"
    ++ "  unless proof.value.isConstOf `True.intro do\n"
    ++ "    throwError \"missing complete proof\"\n"
    ++ "  unless (← getEnv).contains `NeutralEffects.generated\n"
    ++ "      && (← getEnv).contains `NeutralEffects.expanded do\n"
    ++ "    throwError \"missing deferred command effects\"\n"
    ++ "  elabCommand (← `(notation:max \"neutralEffects%\" => NeutralEffects.generated))\n"
    ++ "example : neutralEffects% = 7 := rfl\n"
  let source := sourcePrefix ++ observer
  assertElaborates env source
  let input := Parser.mkInputContext source "neutral-observer.lean"
  let initial ← initialState env input
  let parsed ← SyntaxTree.parseModuleCommandsQuiet input initial true initial
  let reference ← SyntaxTree.replayModulePrefix input initial source.rawEndPos
  assertTrue "deferred parsing agrees with the complete frontend"
    (Formatter.Diagnostics.syntaxSignature (mkListNode parsed.commands)
      == Formatter.Diagnostics.syntaxSignature (mkListNode reference.commands))
  let formatted ← Formatter.formatSourceWithEnvDetailed env source "neutral-observer.lean"
  assertTrue "registered command formatting does not fall back" (!formatted.fellBack)
  assertElaborates env formatted.formatted
  let original ← SyntaxTree.parseModuleSyntaxWithEnv env source "neutral-original.lean"
  let output ←
    SyntaxTree.parseModuleSyntaxWithEnv env formatted.formatted "neutral-output.lean"
  assertTrue "registered command formatting preserves syntax"
    (Formatter.Diagnostics.syntaxSignature original
      == Formatter.Diagnostics.syntaxSignature output)
  assertTrue "registered command formatting is independently idempotent"
    ((← Formatter.formatSourceWithEnv env formatted.formatted "neutral-again.lean")
      == formatted.formatted)

private def assertConservativeHandlers (env : Environment) : IO Unit := do
  let handler := `LeanFmt.Tests.ParserNeutralSyntax.elabNeutralDeclaration
  assertTrue "annotations survive exact imports"
    (LeanFmt.ParserEffects.isNeutralHandler env handler)
  assertTrue "missing implementations cannot be registered"
    (LeanFmt.ParserEffects.registerNeutralHandler env `Missing.handler).toOption.isNone
  let syntaxKind := `LeanFmt.Tests.ParserNeutralSyntax.neutralDeclaration
  let registered ← IO.ofExcept (LeanFmt.ParserEffects.registerNeutralHandler env handler)
  assertTrue "repeated registration is harmless"
    (SyntaxTree.commandKindParseAction registered syntaxKind == .postpone)
  for command in ["neutralDeclaration value", "neutralMacro value"] do
    let stx ← IO.ofExcept (Parser.runParserCategory env `command command)
    assertTrue "registered implementations postpone"
      (SyntaxTree.commandParseAction env stx == .postpone)
  for setup
      in [
        "elab_rules : command\n  | `(neutralDeclaration $_name:ident) => throwUnsupportedSyntax\n",
        "macro_rules\n  | `(neutralDeclaration $_name:ident) => Macro.throwUnsupported\n"
      ] do
    let source := "open Lean Elab Command\n" ++ setup
    let input := Parser.mkInputContext source "overridden-neutral.lean"
    let initial ← initialState env input
    let replaced ← SyntaxTree.replayModulePrefix input initial source.rawEndPos
    assertTrue "an additional unaudited handler forces replay"
      (SyntaxTree.commandKindParseAction replaced.commandState.env syntaxKind
        == .frontend)
  let scope ←
    IO.ofExcept
      (LeanFmt.ParserEffects.registerNeutralHandler env `Lean.Elab.Command.elabSection)
  assertTrue "registrations cannot weaken builtin scope policy"
    (SyntaxTree.commandKindParseAction scope `Lean.Parser.Command.section == .scope)
  let fakeSource :=
    (if env.header.isModule then "public meta section\n" else "")
    ++ "open Lean Elab Command\n"
    ++ "namespace LeanBench\n"
    ++ "syntax (name := setupBenchmark) \"setup_benchmark_fake\" : command\n"
    ++ "@[command_elab setupBenchmark]\n"
    ++ "def elabSetupBenchmark : CommandElab := fun _ => pure ()\n"
    ++ "end LeanBench\n"
  let input := Parser.mkInputContext fakeSource "fake-integration.lean"
  let initial ← initialState env input
  let fake ← SyntaxTree.replayModulePrefix input initial fakeSource.rawEndPos
  let fakeEnv ←
    IO.ofExcept (LeanFmt.ParserEffects.Integration.leanBench.apply fake.commandState.env)
  assertTrue "matching a third-party handler name does not enable an integration"
    (SyntaxTree.commandKindParseAction fakeEnv `LeanBench.setupBenchmark == .frontend)
  assertTrue "integration registration leaves the input environment unchanged"
    (!LeanFmt.ParserEffects.isNeutralHandler fake.commandState.env
        `LeanBench.elabSetupBenchmark)
  let explicitlyRegistered ←
    IO.ofExcept
      (LeanFmt.ParserEffects.registerNeutralHandler fakeEnv `LeanBench.elabSetupBenchmark)
  assertTrue "explicit registration is scoped to its returned environment"
    (SyntaxTree.commandKindParseAction explicitlyRegistered `LeanBench.setupBenchmark
        == .postpone
      && SyntaxTree.commandKindParseAction fakeEnv `LeanBench.setupBenchmark == .frontend)
  let moduleName := `LeanFmt.Tests.ParserNeutralSyntax
  let some fingerprint := LeanFmt.ParserEffects.moduleFingerprint? env moduleName
  | throw <| IO.userError "missing imported fixture fingerprint"
  let check :=
    fun hashes => LeanFmt.ParserEffects.checkModuleFingerprints env .leanBench hashes
  assertTrue "the audited imported implementation is accepted"
    (check [(moduleName, [fingerprint])]).toOption.isSome
  assertTrue "an imported but unaudited implementation is rejected"
    (check [(moduleName, [fingerprint + 1])]).toOption.isNone
  assertTrue "missing audited dependencies are rejected"
    (check [(`Missing.module, [fingerprint])]).toOption.isNone

private def assertScopedOpenDeclarations (env : Environment) : IO Unit := do
  let sourcePrefix :=
    (if env.header.isModule then "public section\n" else "")
    ++ "namespace LocalOpenEffects\n"
    ++ "def value : Nat := 7\n"
    ++ "scoped notation \"localOpenValue%\" => value\n"
    ++ "end LocalOpenEffects\n"
    ++ "theorem openEvidence : True := by exact True.intro\n"
    ++ "open LocalOpenEffects in def simpleOpen := value\n"
    ++ "open scoped LocalOpenEffects in def scopedOpen := localOpenValue%\n"
    ++ "open LocalOpenEffects (value) in def selectedOpen := value\n"
    ++ "open LocalOpenEffects renaming value -> renamed in def renamedOpen := renamed\n"
  let input := Parser.mkInputContext sourcePrefix "scoped-open-prefix.lean"
  let initial ← initialState env input
  let parsed ← SyntaxTree.parseModuleCommandsQuiet input initial true initial
  for name in [`openEvidence, `simpleOpen, `scopedOpen, `selectedOpen, `renamedOpen] do
    assertTrue "temporary open scopes do not force declaration replay"
      (!parsed.commandState.env.contains name)
  assertTrue "temporary opens leave the outer parser scope unchanged"
    (parsed.commandState.scopes.head!.openDecls
      == initial.commandState.scopes.head!.openDecls)
  let source :=
    sourcePrefix
    ++ "open Lean Elab Command\n"
    ++ "run_cmd do\n"
    ++ "  let some (.thmInfo proof) := (← getEnv).find? `openEvidence\n"
    ++ "    | throwError \"missing theorem\"\n"
    ++ "  unless proof.value.isConstOf `True.intro do throwError \"missing proof body\"\n"
    ++ "example : simpleOpen = 7 ∧ scopedOpen = 7 ∧ selectedOpen = 7 ∧ renamedOpen = 7 := by decide\n"
  assertElaborates env source
  let formatted ← Formatter.formatSourceWithEnvDetailed env source "scoped-open.lean"
  assertTrue "scoped open formatting does not fall back" (!formatted.fellBack)
  assertElaborates env formatted.formatted
  assertTrue "scoped open formatting is independently idempotent"
    ((← Formatter.formatSourceWithEnv env formatted.formatted "scoped-open-again.lean")
      == formatted.formatted)
  let standalone ← IO.ofExcept (Parser.runParserCategory env `command "open Lean")
  assertTrue "standalone opens still require full preceding state"
    (SyntaxTree.commandParseAction env standalone == .frontend)
  let overrideSource :=
    (if env.header.isModule then "public meta section\n" else "")
    ++ "open Lean Elab Command\n"
    ++ "@[command_elab Lean.Parser.Command.open]\n"
    ++ "def replacedOpen : CommandElab := fun _ => throwUnsupportedSyntax\n"
  let input := Parser.mkInputContext overrideSource "overridden-open.lean"
  let initial ← initialState env input
  let replaced ← SyntaxTree.replayModulePrefix input initial overrideSource.rawEndPos
  let stx ←
    IO.ofExcept
      (Parser.runParserCategory replaced.commandState.env `command
        "open Lean in def exampleOpen := 1")
  assertTrue "an overridden temporary open handler forces replay"
    (SyntaxTree.commandParseAction replaced.commandState.env stx == .frontend)

private def assertIntegrationOptions : IO Unit := do
  let flag := "--parser-integration"
  match Cli.parseArgs [flag, "lean-bench", flag, "lean-bench", "Example.lean"] with
  | .run options =>
      assertTrue "CLI integrations are explicit and deduplicated"
        (options.parserIntegrations == [.leanBench])
      for mode in [Driver.WorkerEnvironment.default, .exact] do
        let args := options.workerArgs mode options.files
        assertTrue "integration options survive worker dispatch"
          ((args.toList.zip args.toList.tail!).any
            (fun (a, b) => a == flag && b == "lean-bench"))
  | _ => throw <| IO.userError "parser integration option rejected"
  for args in [[flag], [flag, "unknown", "Example.lean"]] do
    match Cli.parseArgs args with
    | .error _ => pure ()
    | _ => throw <| IO.userError "invalid parser integration option accepted"

def run (level : OLeanLevel := .private) : IO Unit := do
  let env ←
    SyntaxTree.importEnvironment #[{ module := `LeanFmt.Tests.ParserNeutralSyntax }]
      (level := level)
  assertConservativeHandlers env
  assertDeferredObservers env
  assertScopedOpenDeclarations env
  assertIntegrationOptions

end LeanFmt.Tests.ParserEffects
