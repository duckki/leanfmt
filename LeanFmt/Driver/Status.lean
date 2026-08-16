namespace LeanFmt.Driver

structure StatusRenderer where
  out : IO.FS.Stream
  enabled : Bool
  rendered : Bool := false
  spinnerIndex : Nat := 0

def StatusRenderer.resetLine : String :=
  "\x1B[2K\r"

def StatusRenderer.spinnerFrames : Array String :=
  #["|", "/", "-", "\\"]

def StatusRenderer.nextSpinner (renderer : StatusRenderer) : String × StatusRenderer :=
  let frame := spinnerFrames[renderer.spinnerIndex % spinnerFrames.size]!
  (frame, { renderer with spinnerIndex := renderer.spinnerIndex + 1 })

def StatusRenderer.create : IO StatusRenderer := do
  let out ← IO.getStderr
  pure { out, enabled := ← out.isTty }

def StatusRenderer.render (renderer : StatusRenderer) (message : String)
    : IO StatusRenderer := do
  if renderer.enabled then
    let (frame, renderer) := renderer.nextSpinner
    renderer.out.putStr s!"{resetLine}{frame} {message}"
    renderer.out.flush
    pure { renderer with rendered := true }
  else
    pure renderer

def StatusRenderer.clear (renderer : StatusRenderer) : IO StatusRenderer := do
  if renderer.enabled && renderer.rendered then
    renderer.out.putStr resetLine
    renderer.out.flush
    pure { renderer with rendered := false }
  else
    pure renderer

end LeanFmt.Driver
