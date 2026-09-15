import Std.Sync.Mutex

namespace LeanFmt.Driver

structure StatusState where
  line : String := ""
  spinnerIndex : Nat := 0

structure StatusRenderer where
  out : IO.FS.Stream
  enabled : Bool
  state : Std.Mutex StatusState

def StatusRenderer.resetLine : String :=
  "\x1B[2K\r"

def StatusRenderer.spinnerFrames : Array String :=
  #["|", "/", "-", "\\"]

def StatusRenderer.create (out : IO.FS.Stream) : IO StatusRenderer := do
  pure { out, enabled := ← out.isTty, state := ← Std.Mutex.new {} }

def StatusRenderer.render (renderer : StatusRenderer) (message : String) : IO Unit := do
  if renderer.enabled then
    renderer.state.atomically do
      let state ← get
      let frame := spinnerFrames[state.spinnerIndex % spinnerFrames.size]!
      let line := s!"{frame} {message}"
      renderer.out.putStr (resetLine ++ line)
      renderer.out.flush
      set { state with line, spinnerIndex := state.spinnerIndex + 1 }

def StatusRenderer.clear (renderer : StatusRenderer) : IO Unit := do
  renderer.state.atomically do
    let state ← get
    if !state.line.isEmpty then
      renderer.out.putStr resetLine
      renderer.out.flush
      set { state with line := "" }

def StatusRenderer.withOutput (renderer : StatusRenderer) (action : IO α) : IO α :=
  renderer.state.atomically do
    let line := (← get).line
    if !line.isEmpty then
      renderer.out.putStr resetLine
      renderer.out.flush
    try
      action
    finally
      if !line.isEmpty then
        renderer.out.putStr (resetLine ++ line)
        renderer.out.flush

end LeanFmt.Driver
