import Lean

namespace LeanFmt.Tests.RuntimeLoading

private def assertSharedAllocator (executable : System.FilePath) : IO Unit := do
  unless System.Platform.isOSX do
    return
  let symbols ← IO.Process.output { cmd := "nm", args := #["-gU", executable.toString] }
  unless symbols.exitCode == 0 do
    throw <| IO.userError s!"cannot inspect formatter runtime linkage: {symbols.stderr}"
  for symbol
      in [
        "_mi_malloc_small",
        "_mi_malloc",
        "_mi_zalloc_small",
        "_mi_free",
        "_lean_alloc_object"
      ] do
    if (symbols.stdout.splitOn "\n").any (·.endsWith s!" {symbol}") then
      throw <| IO.userError s!"formatter embeds a second runtime allocator: {symbol}"

def run : IO Unit := do
  let sysroot ← Lean.findSysroot
  let plugin :=
    if System.Platform.isWindows then
      sysroot / "bin" / "libLake_shared.dll"
    else
      sysroot
      / "lib"
      / "lean"
      / (if System.Platform.isOSX then "libLake_shared.dylib" else "libLake_shared.so")
  unless ← plugin.pathExists do
    throw <| IO.userError s!"missing installed Lake plugin: {plugin}"
  let executable :=
    (← IO.currentDir)
    / ".lake/build/bin"
    / (System.FilePath.addExtension "fmt" System.FilePath.exeExtension)
  assertSharedAllocator executable
  IO.FS.withTempDir
    fun root => do
      let imported := root / "Imported.lean"
      let ordinary := root / "Ordinary.lean"
      let source :=
        "import Lake\n\ndef runtimePluginSmoke : Nat := 1\n"
        ++ "\ntheorem runtimeAllocatorSmoke : (List.range 128).length = 128 := by decide +kernel\n"
        ++ "\nrun_cmd do\n"
        ++ "  let some (.thmInfo proof) := (← Lean.getEnv).find? `runtimeAllocatorSmoke\n"
        ++ "    | throwError \"missing runtime proof\"\n"
        ++ "  if proof.value.hasSorry then throwError \"incomplete runtime proof\"\n"
      let ordinarySource := "def runtimeDefaultSmoke : Nat := 2\n"
      IO.FS.writeFile imported source
      IO.FS.writeFile ordinary ordinarySource
      for (label, libraries, plugins)
          in [
            ("plugin", none, some plugin.toString),
            ("native", some plugin.toString, none),
            ("combined", some plugin.toString, some plugin.toString)
          ] do
        for files in [#[imported], #[imported, ordinary]] do
          let output ←
            IO.Process.output
              {
                cmd := executable.toString
                args :=
                  #["--jobs", "1", "--check", "--check-exception", "--check-idempotent"]
                  ++ files.map (·.toString)
                cwd := some root
                env :=
                  #[
                    ("LEANFMT_LOAD_DYNLIBS", libraries),
                    ("LEANFMT_LOAD_PLUGINS", plugins)
                  ]
              }
          unless output.exitCode == 0 do
            throw
            <| IO.userError
                s!"runtime loading ({label}, {files.size} files) failed ({output.exitCode}):\n{output.stdout}{output.stderr}"
          unless (← IO.FS.readFile imported) == source
                  && (← IO.FS.readFile ordinary) == ordinarySource do
            throw <| IO.userError "runtime loading check modified its inputs"

end LeanFmt.Tests.RuntimeLoading
