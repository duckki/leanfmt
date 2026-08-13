# leanfmt

leanfmt is an opinionated formatter for Lean code, written in Lean.

It is built for projects that care about trust as much as style: leanfmt parses
files with Lean's own parser, loads project syntax extensions, preserves source
tokens and comments, and refuses to silently rewrite code when its safety checks
do not pass.

The style is structural. Continuation lines lead with the token that explains
how they connect, while indentation shows the nesting.

```lean
def parenthesizedConjunctionChain (schema : Schema) : Prop :=
  namesAreUnique (schema.allTypes.map TypeDefinition.name)
  ∧ schema.objectType schema.queryType
  ∧ (∀ typeDefinition,
      typeDefinition ∈ schema.types -> typeDefinitionWellFormed schema typeDefinition)
  ∧ (∀ typeName objectTypeName,
      objectTypeName ∈ schema.getPossibleTypes typeName
      -> schema.objectType objectTypeName)
```

See the [formatting design](docs/design.md) for the full style guide and more
examples.

## Why Use It

- **Lean-native**: uses Lean's parser and the active Lake environment, so custom
  syntax is handled in the same context as your project.
- **Structure-preserving**: works from a lossless syntax tree and formats
  whitespace around the code you wrote.
- **Conservative by design**: checks token preservation, comments, parsing, and
  idempotence; if formatting cannot be proven safe, the original source stays in
  place.
- **Practical for adoption**: format one file, a directory, or only files changed
  in a branch.

## Quick Start

Add leanfmt to `lakefile.toml`:

```toml
[[require]]
name = "leanfmt"
git = "https://github.com/duckki/leanfmt.git"
rev = "vX.Y.Z"
```

Resolve the dependency without changing your project's Lean toolchain:

```sh
lake update --keep-toolchain
```

Format a file:

```sh
lake exe fmt MyProject/File.lean
```

Check formatting in CI:

```sh
lake exe fmt --check -r MyProject
```

## Usage

Common options:

```text
--version              Print the installed leanfmt and Lean version.
--line-width <number>  Set the target line width. Default: 90.
```

### Format Common Targets

```sh
# One file
lake exe fmt MyProject/File.lean

# Files directly inside a directory
lake exe fmt MyProject

# A directory tree
lake exe fmt -r MyProject

# A project with a 100-column convention
lake exe fmt --line-width 100 -r MyProject
```

Directory traversal skips hidden descendants by default. Explicitly supplied
hidden paths are still processed. Pass `--include-hidden` to include hidden
descendants.

### Check Without Rewriting

```sh
lake exe fmt --check -r MyProject
```

`--check` exits nonzero if a file would change or cannot be formatted, which
makes it suitable for CI and pre-commit validation.

### Format Only Current Changes

This is the easiest way to adopt leanfmt incrementally.

```sh
# Check staged Lean files before committing
lake exe fmt --check $(git diff --cached --name-only --diff-filter=ACMR -- '*.lean')

# Format Lean files changed since HEAD
lake exe fmt $(git diff --name-only --diff-filter=ACMR HEAD -- '*.lean')

# CI: check files changed on this branch
lake exe fmt --check $(git diff --name-only --diff-filter=ACMR origin/main...HEAD -- '*.lean')
```

Run these commands only when the `git diff --name-only ... '*.lean'` list is
nonempty. If your repository uses spaces in file names, pass those paths
explicitly.

### Tune The Run

```sh
# Use a specific worker count
lake exe fmt --jobs 8 -r MyProject

# Print the installed formatter version
lake exe fmt --version
```

Multi-file package invocations use concurrent workers by default. leanfmt follows
the selected Lake environment for each file group, including imported syntax
extensions.

### Leave Code Alone

Preserve the next complete syntax node:

```lean
-- leanfmt: off next
def handAligned   :   Nat:=
       1
```

Preserve a manual source region:

```lean
-- leanfmt: off
def handAligned   :   Nat:=
       1
-- leanfmt: on
```

leanfmt still formats parseable chunks outside ignored regions and keeps marker
lines and enclosed lines unchanged, apart from normal line-ending handling.

## Safety Model

leanfmt's formatter pipeline is intentionally narrow:

```text
Lean parser
  -> lossless syntax tree
  -> syntax regrouping
  -> spacing and line-break rules
  -> width-aware renderer
  -> preservation and idempotence checks
```

The formatter preserves code tokens, token order, comments, and protected source
regions. With `--check-exception --check-idempotent`, CI can also fail on
unexpected code changes, actionable line overflow, missing formatting rules, or a
non-idempotent result.

## Status

leanfmt is under active development. Review formatting diffs before broad
rollout, start with changed files, and use `--check` in CI once the project is
ready.

## Learn More

- [Introducing LeanFmt](https://duckki.github.io/2026/08/11/introducing-leanfmt.html)
- [Contributing](CONTRIBUTING.md)
- [Design](docs/design.md)
- [Architecture](docs/architecture.md)
- [Development](docs/development.md)
- [Comparison](docs/comparison.md)

## License

leanfmt is released under the [MIT License](LICENSE).
