import LeanFmt.Driver.Workers

namespace LeanFmt.Tests.WorkerOutput

private def capture (terminal : Bool) : IO (IO.FS.Stream × IO String) := do
  let buffer ← IO.mkRef ({} : IO.FS.Stream.Buffer)
  let stream := { IO.FS.Stream.ofBuffer buffer with isTty := pure terminal }
  pure
    (
      stream,
      do
        pure <| String.fromUTF8! (← buffer.get).data
    )

private def check (label : String) (condition : Bool) : IO Unit := do
  unless condition do
    throw <| IO.userError label

private def checkText (label expected actual : String) : IO Unit :=
  check s!"{label}\nexpected: {repr expected}\nactual: {repr actual}" (expected == actual)

private def assertStatusOutput : IO Unit := do
  let (out, contents) ← capture true
  let status ← Driver.StatusRenderer.create out
  let reset := Driver.StatusRenderer.resetLine
  status.render "first"
  status.withOutput <| out.putStr "formatted First.lean\n"
  status.render "second"
  let failed ←
    try
      status.withOutput do
        out.putStr "worker diagnostic\n"
        throw <| IO.userError "expected output failure"
      pure false
    catch _ =>
      pure true
  check "output errors propagate" failed
  status.clear
  status.clear
  checkText "messages clear and restore progress without advancing the spinner"
    (reset
      ++ "| first"
      ++ reset
      ++ "formatted First.lean\n"
      ++ reset
      ++ "| first"
      ++ reset
      ++ "/ second"
      ++ reset
      ++ "worker diagnostic\n"
      ++ reset
      ++ "/ second"
      ++ reset)
    (← contents)
  let (out, contents) ← capture false
  let status ← Driver.StatusRenderer.create out
  status.render "not a terminal"
  status.withOutput <| out.putStr "plain output"
  status.clear
  checkText "redirected output has no progress or control sequences"
    "plain output" (← contents)

private def assertConcurrentOutput : IO Unit := do
  let (out, contents) ← capture true
  let status ← Driver.StatusRenderer.create out
  status.render "running"
  let write (name : String) := do
    for index in List.range 12 do
      status.withOutput do
        out.putStr s!"{name}:{index}:"
        IO.sleep 1
        out.putStr "complete\n"
  let first ← IO.asTask (prio := .dedicated) (write "stdout")
  let second ← IO.asTask (prio := .dedicated) (write "stderr")
  for index in List.range 12 do
    status.render s!"running {index}"
    IO.sleep 1
  IO.ofExcept first.get
  IO.ofExcept second.get
  status.clear
  let text ← contents
  for name in ["stdout", "stderr"] do
    for index in List.range 12 do
      let message := s!"{name}:{index}:complete\n"
      check "progress and peer output cannot split a message"
        ((text.splitOn message).length == 2)

private def assertRelayedLines : IO Unit := do
  IO.FS.withTempDir
    fun root => do
      let file := root / "output.txt"
      let text := "first\nUnicode: ∀ α → β\nlast without newline"
      IO.FS.writeFile file text
      for terminal in [false, true] do
        let (out, contents) ← capture terminal
        let (err, errors) ← capture true
        let status ← Driver.StatusRenderer.create err
        status.render "running"
        let input ← IO.FS.Handle.mk file .read
        Driver.relayWorkerOutput status out input
        status.clear
        checkText "relay preserves Unicode and terminates only terminal fragments"
          (text ++ if terminal then "\n" else "") (← contents)
        check "progress stays on stderr" (!(← errors).contains '∀')

private def assertInteractiveWorker : IO Unit := do
  IO.FS.withTempDir
    fun root => do
      let file := root / "Example.lean"
      IO.FS.writeFile file "def  exampleValue := 0\n"
      let (out, contents) ← capture false
      let (err, errors) ← capture true
      let status ← Driver.StatusRenderer.create err
      let executable := (← IO.currentDir) / ".lake/build/bin/fmt"
      let process : Driver.WorkerProcessContext := { executable, environment := #[] }
      status.render "running worker"
      let result ←
        Driver.runEnvironmentWorkerBatch process status out { profile := true }
          .default none [file]
      check "interactive worker succeeds" (result.exitCode == 0)
      checkText "worker stdout remains separate from progress"
        s!"formatted {file}\n" (← contents)
      check "worker stderr clears progress before its diagnostic"
        (((← errors).splitOn
            (Driver.StatusRenderer.resetLine ++ "leanfmt profile:")).length
          > 1)
      checkText "worker formatting is applied" "def exampleValue := 0\n"
        (← IO.FS.readFile file)
      IO.FS.writeFile file "def invalid := ]\n"
      let result ←
        Driver.runEnvironmentWorkerBatch process status out {} .default none [file]
      check "interactive worker failure propagates" (result.exitCode != 0)
      IO.withStderr err do
        let failed ←
          status.withOutput
          <| Driver.reportWorkerBatchResult {} .default 1 1 1 1 (.ok result)
        check "parent reports worker failure" failed
      status.clear
      check "failure report is separated from progress"
        (((← errors).splitOn
            (Driver.StatusRenderer.resetLine ++ "leanfmt: worker batch 1/1")).length
          == 2)

private def assertWorkerOutputFailure : IO Unit := do
  IO.FS.withTempDir
    fun root => do
      let file := root / "Example.lean"
      let executable := (← IO.currentDir) / ".lake/build/bin/fmt"
      let process : Driver.WorkerProcessContext := { executable, environment := #[] }
      let broken (out : IO.FS.Stream) :=
        { out with putStr := fun _ => throw <| IO.userError "expected relay failure" }
      for failStderr in [false, true] do
        IO.FS.writeFile file "def  exampleValue := 0\n"
        let (out, _) ← capture false
        let (err, _) ← capture true
        let status ← Driver.StatusRenderer.create (if failStderr then broken err else err)
        let failed ←
          try
            discard
            <| Driver.runEnvironmentWorkerBatch process status
                (if failStderr then out else broken out) { profile := true } .default none
                [file]
            pure false
          catch error =>
            pure (((toString error).splitOn "expected relay failure").length > 1)
        check "a failed output destination terminates the worker and joins its readers"
          failed

def run : IO Unit := do
  assertStatusOutput
  assertConcurrentOutput
  assertRelayedLines
  assertInteractiveWorker
  assertWorkerOutputFailure

end LeanFmt.Tests.WorkerOutput
