# Stability and compatibility

Starting with 1.0, leanfmt commits to the formatting style, CLI, and public
library API described here. The [design guide](design.md) defines the style;
the [architecture guide](architecture.md) explains its implementation.

## Versioning and formatting output

| Release | Allowed changes |
| --- | --- |
| Patch (`1.0.x`) | Correctness, preservation, idempotency, and documented-style bug fixes; performance and compatible toolchain fixes. A formatting bug fix may change output. |
| Minor (`1.x.0`) | Additional syntax support and compatible features. Newly supported syntax may format differently; existing supported syntax retains the established style except for bug fixes. |
| Major (`2.0.0`) | Deliberate broad restyling, incompatible public interface changes, or removal of a supported Lean version. |

A style preference alone is not a bug fix. Output changes must identify the
violated style rule or correctness property, include focused regression coverage,
and be described in release notes. Changes to defaults that alter the established
style, such as the default line width of 90, require a major release.

Idempotency means formatting an output again with the same formatter, options,
and environment produces the same text. It does not promise identical output
across formatter upgrades or Lean versions. Pin the leanfmt Git tag, Lean
toolchain, project dependencies, and formatting options for reproducible runs.
Review diffs when updating any of them.

## CLI contract

The public executable is `fmt`, normally invoked through `lake exe fmt` or the
project's `lake env`. These interfaces retain their documented meaning in 1.x:

- File and directory arguments; `--recursive` / `-r` and `--include-hidden`.
- `--line-width`, `--jobs` / `-j`, `--check`, `--help` / `-h`, and `--version`.
- The `leanfmt: off`, `leanfmt: on`, and `leanfmt: off next` source markers.

Ordinary formatting writes successful results in place. Parsing, preservation,
or convergence failures are reported without writing the affected file; other
files in the invocation may still succeed.
An ordinary `--check` invocation writes nothing and returns zero only when all
selected files are already formatted and no file fails. Formatting, argument,
or worker failures return a nonzero status. Exact diagnostic wording and worker
output order are not machine-readable compatibility contracts.

The documented validation switches `--check-exception`, `--check-idempotent`,
and `--check-missing-rules` also retain their meanings. With any of these
switches, `--check` is a dry run: formatting drift is reported but does not by
itself fail the invocation; diagnostics and processing failures determine the
exit status. Use plain `--check` when CI must reject formatting drift.

Profiling, traces, import-cache controls, worker protocol options, and parser
integration adapters are development interfaces outside the stable CLI contract.
In particular, an audited `--parser-integration` adapter may reject an upstream
implementation it has not audited.

## Public library API

Import `LeanFmt`. The stable source-level API consists of:

| Declaration | Contract |
| --- | --- |
| `LeanFmt.Formatter.Options` | Construct options with named fields and defaults, such as `{ lineWidth := 100 }`. The `lineWidth : Nat` field and its default of 90 are stable; use a positive width. Future compatible fields may have defaults. |
| `LeanFmt.Formatter.formatSource` | `(source : String) (fileName : String := "<input>") (options : Options := {}) : IO String`. Uses the default environment importing `Lean`. |
| `LeanFmt.Formatter.formatSourceWithEnv` | `(env : Lean.Environment) (source : String) (fileName : String := "<input>") (options : Options := {}) : IO String`. Uses the caller-supplied environment for project syntax. |

These functions normalize line endings and run preservation and convergence
checks. On a preservation or convergence fallback they warn and return the
original source with normalized line endings; parsing and environment errors
may raise an `IO` error. A returned string alone is therefore not a success
report for a validation pipeline. Use the CLI when exit-status reporting and
project environment discovery are needed.

Other declarations reachable through `import LeanFmt` are implementation or
development APIs, even when Lean permits importing them. This includes the
lossless syntax-tree representation, renderer and rule structures, `Internal`
and `Debug` namespaces, the detailed-result API, and the single-pass
`formatModule` / `formatModuleWithEnv` functions. They are not covered by 1.x
source compatibility. Compile the library with the project's Lean toolchain;
there is no cross-toolchain binary compatibility promise.

## Supported Lean versions and platforms

The 1.0 baseline tests these exact releases:

| Lean version | Coverage |
| --- | --- |
| 4.36.0 | Development toolchain; full Linux CI gate and local macOS validation. |
| 4.35.0, 4.34.1, 4.33.1, 4.32.0 | Linux builds and compatibility smoke suites. The external Flare and GraphQL builds also exercise 4.35.0. |

The CI matrix is in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml).
macOS CI additionally checks native plugin loading on the current toolchain and
4.33.0-rc1; that focused regression does not establish general support for the
release candidate. Other Lean releases and Windows are not covered by this
release's validation.

Support for the listed Lean releases remains through 1.x. Additional supported
versions are documented with their test coverage; removing a listed version
requires a major leanfmt release. Update dependencies with
`lake update --keep-toolchain` to retain the downstream project's Lean version.
See the [development guide](development.md#lean-version-compatibility) for
matching a formatter binary to the project's toolchain.

## Safety boundaries

leanfmt checks tokens, comments, parsing, syntax structure, and convergence.
The CLI rejects detected preservation or convergence failures and leaves the
affected file unchanged. Width diagnostics distinguish actionable overflow from
protected layouts and indivisible tokens; the configured width is not an
absolute bound on every physical line.

These checks are not a proof of semantic equivalence. Lean macros and
elaborators can inspect source positions that the syntax signature does not
capture. Unknown custom syntax can also require conservative source retention.
The release gate therefore builds projects before and after formatting. Keep a
project build in downstream adoption and upgrade checks as well. The
[architecture guide](architecture.md#preservation-check-limitation-layout-sensitive-elaboration)
documents the known class of limitation and its regression coverage.
