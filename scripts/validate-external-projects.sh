#!/usr/bin/env bash

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
readonly SCRIPT_DIR
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)" || exit 1
readonly REPO_ROOT
readonly FORMATTER="$REPO_ROOT/.lake/build/bin/fmt"
readonly WORK_DIR="${LEANFMT_VALIDATION_DIR:-$REPO_ROOT/.scratch/external-validation}"
readonly VALIDATION_FILES_PER_BATCH="${LEANFMT_VALIDATION_BATCH_SIZE:-100}"
readonly BUILD_FILES_PER_BATCH=1000
readonly FORMATTER_WORKER_JOBS="${LEANFMT_VALIDATION_FORMATTER_JOBS:-}"
readonly FORMATTER_LINE_WIDTH="${LEANFMT_VALIDATION_LINE_WIDTH:-}"
readonly DEFAULT_FILE_SELECTOR="${LEANFMT_VALIDATION_FILE_PATTERN:-*.lean}"
readonly FORMATTER_BUILD_ROOT="$WORK_DIR/formatter-toolchains"
readonly SETUP_RUNTIME_HELPER="$REPO_ROOT/scripts/lake-setup-runtime.lean"

failures=0
CURRENT_TOOLCHAIN=""
PROJECT_FORMATTER=""
PROJECT_TOOLCHAIN=""

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/validate-external-projects.sh [--files FILE_SELECTOR] [--build-target TARGET]... [--batch N | --start-batch N] [--reuse-clone] [--skip-initial-build] [--skip-final-build] GIT_REPO[::FILE_SELECTOR]...
  scripts/validate-external-projects.sh [--files FILE_SELECTOR] [--build-target TARGET]... [--batch N | --start-batch N] [--reuse-clone] [--skip-initial-build] [--skip-final-build] NAME=GIT_REPO[::FILE_SELECTOR]...
  scripts/validate-external-projects.sh --checkpoint [--files FILE_SELECTOR] GIT_REPO[::FILE_SELECTOR]...
  scripts/validate-external-projects.sh --checkpoint [--files FILE_SELECTOR] NAME=GIT_REPO[::FILE_SELECTOR]...

Each project argument must name an explicit git clone source. The validator
creates a fresh clone under .scratch/external-validation/ before formatting
unless --reuse-clone is passed.
Only selected source files owned by a Lake module target are formatted. Other
tracked Lean files are reported as unowned and skipped. Formatter output is
staged until every requested batch passes, then changed files are applied to
the clone and rebuilt. This keeps imported artifacts stable between batches.
Pass --skip-final-build to omit the complete build after every requested
formatter batch succeeds. A formatter failure never triggers a build.
The complete build before formatting still runs.
Repeat --build-target TARGET to build explicit Lake targets before and after
formatting instead of each project's default targets. The selected targets
apply to every project argument in that invocation.
Pass --start-batch N to validate batch N and every later batch. Pass
--reuse-clone to keep an existing scratch clone, and --skip-initial-build to
omit its already-completed pre-format build while resuming validation.
Pass --checkpoint for the lighter checkpoint gate. It reuses an existing clone
and the Lake ownership/runtime manifests recorded by a previous successful full
validation of the same revision, toolchain, and selected file set. It runs all
formatter diagnostics and idempotency checks, applies the staged output for
review, and skips every target-project build. Run the ordinary command for the
full release gate and to establish or refresh the checkpoint baseline.

Set LEANFMT_VALIDATION_LINE_WIDTH=N to pass --line-width N to every formatter
invocation. For example, validate mathlib at width 100 with:

  LEANFMT_VALIDATION_LINE_WIDTH=100 scripts/validate-external-projects.sh \
    --files Mathlib mathlib=$HOME/work/lean-libs/mathlib4

Set LEANFMT_VALIDATION_FORMATTER_JOBS=N to limit concurrent formatter workers.
The automatic default uses the hardware count for every formatter worker group.

The validator reads each project's lean-toolchain. When it differs from
leanfmt's toolchain, the current formatter source is built automatically with
the target toolchain in .scratch/external-validation/formatter-toolchains/.
Lake setup files supply native libraries and parser plugins in their required load
order when target syntax depends on compiled extensions.
EOF
}

section() {
  printf '\n==> %s\n' "$1"
}

run_phase_result() {
  local description="$1"
  shift
  local started_at=$SECONDS

  section "$description"
  if "$@"; then
    printf 'PASSED (%ds): %s\n' "$((SECONDS - started_at))" "$description"
    return 0
  else
    local status=$?
    printf 'FAILED (exit %d, %ds): %s\n' \
      "$status" "$((SECONDS - started_at))" "$description" >&2
    failures=$((failures + 1))
    return "$status"
  fi
}

run_phase() {
  run_phase_result "$@"
  return 0
}

run_optional_phase() {
  local description="$1"
  shift
  local started_at=$SECONDS

  section "$description"
  if "$@"; then
    printf 'PASSED (%ds): %s\n' "$((SECONDS - started_at))" "$description"
  else
    local status=$?
    printf 'SKIPPED (exit %d, %ds): %s\n' \
      "$status" "$((SECONDS - started_at))" "$description" >&2
  fi
}

validate_positive_integer() {
  local name="$1"
  local value="$2"

  if [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
    return 0
  fi

  printf '%s must be a positive integer, got %q.\n' "$name" "$value" >&2
  return 2
}

validate_boolean() {
  local name="$1"
  local value="$2"

  if [[ "$value" == "0" || "$value" == "1" ]]; then
    return 0
  fi

  printf '%s must be 0 or 1, got %q.\n' "$name" "$value" >&2
  return 2
}

read_lean_toolchain() {
  local project_dir="$1"
  local toolchain_file="$project_dir/lean-toolchain"
  local toolchain=""

  if [[ ! -f "$toolchain_file" ]]; then
    printf 'Missing Lean toolchain file: %s\n' "$toolchain_file" >&2
    return 2
  fi

  IFS= read -r toolchain < "$toolchain_file" || true
  toolchain="${toolchain%$'\r'}"
  if [[ -z "$toolchain" ]]; then
    printf 'Empty Lean toolchain file: %s\n' "$toolchain_file" >&2
    return 2
  fi

  printf '%s\n' "$toolchain"
}

toolchain_cache_key() {
  local toolchain="$1"
  printf '%s\n' "${toolchain//[^[:alnum:]._-]/_}"
}

sync_formatter_source() {
  local destination="$1"
  local path parent

  mkdir -p "$destination"
  find "$destination" -mindepth 1 -maxdepth 1 ! -name .lake \
    -exec rm -rf {} +

  while IFS= read -r -d '' path; do
    if [[ "$path" == */* ]]; then
      parent="${path%/*}"
      mkdir -p "$destination/$parent"
    fi
    cp -p "$REPO_ROOT/$path" "$destination/$path" || return $?
  done < <(git -C "$REPO_ROOT" ls-files -co --exclude-standard -z)
}

select_project_formatter() {
  local project_name="$1"
  local project_dir="$2"
  local cache_key build_dir formatter

  PROJECT_TOOLCHAIN="$(read_lean_toolchain "$project_dir")" || return $?
  printf 'leanfmt toolchain: %s\n' "$CURRENT_TOOLCHAIN"
  printf '%s toolchain: %s\n' "$project_name" "$PROJECT_TOOLCHAIN"

  if [[ "$PROJECT_TOOLCHAIN" == "$CURRENT_TOOLCHAIN" ]]; then
    PROJECT_FORMATTER="$FORMATTER"
    printf 'Using current-toolchain formatter: %s\n' "$PROJECT_FORMATTER"
    return 0
  fi

  cache_key="$(toolchain_cache_key "$PROJECT_TOOLCHAIN")"
  build_dir="$FORMATTER_BUILD_ROOT/$cache_key"
  formatter="$build_dir/.lake/build/bin/fmt"

  printf 'Preparing formatter source for %s in %s\n' \
    "$PROJECT_TOOLCHAIN" "$build_dir"
  sync_formatter_source "$build_dir" || return $?
  printf '%s\n' "$PROJECT_TOOLCHAIN" > "$build_dir/lean-toolchain"
  (cd "$build_dir" && lake build fmt) || return $?

  if [[ ! -x "$formatter" ]]; then
    printf 'Compatible formatter executable was not built: %s\n' \
      "$formatter" >&2
    return 1
  fi

  PROJECT_FORMATTER="$formatter"
  printf 'Using target-toolchain formatter: %s\n' "$PROJECT_FORMATTER"
}

clone_project() {
  local source="$1"
  local destination="$2"

  rm -rf "$destination"
  git clone "$source" "$destination"
}

absolute_path() {
  local path="$1"

  if [[ "$path" == /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$PWD" "$path"
  fi
}

project_name_from_path() {
  local path="$1"
  local name

  name="$(basename "$path")"
  name="${name%.git}"
  printf '%s\n' "$name"
}

validate_local_git_repo() {
  local path="$1"

  if [[ ! -d "$path" ]]; then
    printf 'Project path does not exist or is not a directory: %s\n' "$path" >&2
    return 2
  fi
  if ! git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'Project path is not a git repository: %s\n' "$path" >&2
    return 2
  fi
}

normalize_project_source() {
  local source="$1"

  if [[ -d "$source" ]]; then
    absolute_path "$source"
  else
    printf '%s\n' "$source"
  fi
}

validate_project_source() {
  local source="$1"

  if [[ -d "$source" ]]; then
    validate_local_git_repo "$source"
  fi
}

seed_local_lake_packages() {
  local source="$1"
  local destination="$2"

  if [[ -d "$source/.lake/packages" ]]; then
    mkdir -p "$destination/.lake"
    rm -rf "$destination/.lake/packages"
    cp -R "$source/.lake/packages" "$destination/.lake/"
  fi
}

get_build_cache() {
  local project_dir="$1"

  if [[ "${LEANFMT_VALIDATION_SKIP_CACHE:-0}" == "1" ]]; then
    printf 'Skipping the Lake build cache (LEANFMT_VALIDATION_SKIP_CACHE=1).\n'
    return 0
  fi

  (cd "$project_dir" && lake exe cache get)
}

build_project() {
  local project_dir="$1"
  shift
  (cd "$project_dir" && lake build "$@")
}

query_project_source_group() {
  local project_dir="$1"
  local owned_file="$2"
  local unowned_file="$3"
  local setup_file="$4"
  shift 4
  local -a sources=("$@")
  local -a targets=()
  local source olean setup
  local output error status split

  for source in "${sources[@]}"; do
    targets+=("$project_dir/$source:olean")
  done

  output="$(mktemp "$WORK_DIR/lake-query.XXXXXX")" || return 1
  error="$(mktemp "$WORK_DIR/lake-query-error.XXXXXX")" || {
    rm -f "$output"
    return 1
  }
  if (cd "$project_dir" && lake query "${targets[@]}") > "$output" 2> "$error"; then
    printf '%s\n' "${sources[@]}" >> "$owned_file"
    while IFS= read -r olean; do
      if [[ -z "$olean" ]]; then
        continue
      fi
      setup="${olean%%/lib/lean/*}/ir/${olean#*/lib/lean/}"
      setup="${setup%.olean}.setup.json"
      printf '%s\n' "$setup" >> "$setup_file"
    done < "$output"
    rm -f "$output" "$error"
    return 0
  else
    status=$?
  fi

  if grep -q '^error: unknown module source path ' "$error"; then
    rm -f "$output" "$error"
    if ((${#sources[@]} == 1)); then
      printf '%s\n' "${sources[0]}" >> "$unowned_file"
      return 0
    fi
    split=$((${#sources[@]} / 2))
    query_project_source_group "$project_dir" "$owned_file" "$unowned_file" \
      "$setup_file" "${sources[@]:0:split}" || return $?
    query_project_source_group "$project_dir" "$owned_file" "$unowned_file" \
      "$setup_file" "${sources[@]:split}" || return $?
    return 0
  fi

  cat "$error" >&2
  rm -f "$output" "$error"
  return "$status"
}

classify_and_build_project_sources() {
  local project_dir="$1"
  local selected_file="$2"
  local owned_file="$3"
  local unowned_file="$4"
  local setup_file="$5"
  local -a batch=()
  local source

  : > "$owned_file"
  : > "$unowned_file"
  : > "$setup_file"
  while IFS= read -r source; do
    if [[ -z "$source" ]]; then
      continue
    fi
    batch+=("$source")
    if ((${#batch[@]} == VALIDATION_FILES_PER_BATCH)); then
      query_project_source_group "$project_dir" "$owned_file" "$unowned_file" \
        "$setup_file" "${batch[@]}" || return $?
      batch=()
    fi
  done < "$selected_file"
  if ((${#batch[@]} > 0)); then
    query_project_source_group "$project_dir" "$owned_file" "$unowned_file" \
      "$setup_file" "${batch[@]}" || return $?
  fi
}

collect_setup_runtime_manifest() {
  local project_dir="$1"
  local setup_file="$2"
  local output_file="$3"

  (cd "$project_dir" && lake env lean --run "$SETUP_RUNTIME_HELPER" \
    "$setup_file" "$output_file")
}

prepare_staged_sources() {
  local project_dir="$1"
  local stage_dir="$2"
  local owned_file="$3"
  local reuse_stage="$4"
  local source staged parent

  if ((reuse_stage == 0)); then
    rm -rf "$stage_dir"
  fi
  mkdir -p "$stage_dir"
  while IFS= read -r source; do
    if [[ -z "$source" ]]; then
      continue
    fi
    staged="$stage_dir/$source"
    if [[ -f "$staged" ]]; then
      continue
    fi
    parent="${staged%/*}"
    mkdir -p "$parent"
    cp -p "$project_dir/$source" "$staged" || return $?
  done < "$owned_file"
}

apply_staged_sources() {
  local project_dir="$1"
  local stage_dir="$2"
  local owned_file="$3"
  local changed_file="$4"
  local source staged target

  : > "$changed_file"
  while IFS= read -r source; do
    if [[ -z "$source" ]]; then
      continue
    fi
    staged="$stage_dir/$source"
    target="$project_dir/$source"
    if ! cmp -s "$staged" "$target"; then
      cp -p "$staged" "$target" || return $?
      printf '%s\n' "$source" >> "$changed_file"
    fi
  done < "$owned_file"
}

build_project_source_file() {
  local project_dir="$1"
  local source_file="$2"
  local -a batch=()
  local source

  while IFS= read -r source; do
    if [[ -z "$source" ]]; then
      continue
    fi
    batch+=("$project_dir/$source")
    if ((${#batch[@]} == BUILD_FILES_PER_BATCH)); then
      (cd "$project_dir" && lake build "${batch[@]}") || return $?
      batch=()
    fi
  done < "$source_file"
  if ((${#batch[@]} > 0)); then
    (cd "$project_dir" && lake build "${batch[@]}") || return $?
  fi
}

selected_lean_files() {
  local project_dir="$1"
  local file_selector="$2"
  local file

  if [[ -f "$project_dir/$file_selector" ]]; then
    if [[ "$file_selector" == *.lean ]]; then
      printf '%s\0' "$project_dir/$file_selector"
    fi
  elif [[ -d "$project_dir/$file_selector" ]]; then
    while IFS= read -r -d '' file; do
      if [[ "$file" == *.lean ]]; then
        printf '%s\0' "$project_dir/$file"
      fi
    done < <(git -C "$project_dir" ls-files -z -- "$file_selector")
  else
    while IFS= read -r -d '' file; do
      printf '%s\0' "$project_dir/$file"
    done < <(git -C "$project_dir" ls-files -z -- "$file_selector")
  fi
}

collect_selected_lean_files() {
  local project_dir="$1"
  local file_selector="$2"
  local file

  while IFS= read -r -d '' file; do
    printf '%s\0' "$file"
  done < <(selected_lean_files "$project_dir" "$file_selector")
}

write_selected_source_list() {
  local project_dir="$1"
  local output_file="$2"
  shift 2
  local file

  : > "$output_file"
  for file in "$@"; do
    printf '%s\n' "${file#"$project_dir/"}" >> "$output_file"
  done
}

write_checkpoint_identity() {
  local output_file="$1"
  local project_dir="$2"
  local file_selector="$3"
  local project_toolchain="$4"
  local revision

  revision="$(git -C "$project_dir" rev-parse HEAD)" || return $?
  {
    printf 'revision=%s\n' "$revision"
    printf 'toolchain=%s\n' "$project_toolchain"
    printf 'file-selector=%s\n' "$file_selector"
  } > "$output_file"
}

validate_checkpoint_baseline() {
  local project_dir="$1"
  local file_selector="$2"
  local project_toolchain="$3"
  local checkpoint_file="$4"
  local selected_file="$5"
  local owned_file="$6"
  local unowned_file="$7"
  local setup_file="$8"
  local runtime_file="$9"
  shift 9
  local -a selected_files=("$@")
  local expected_identity current_selected source

  expected_identity="$(mktemp "$WORK_DIR/checkpoint-identity.XXXXXX")" || return 1
  current_selected="$(mktemp "$WORK_DIR/checkpoint-sources.XXXXXX")" || {
    rm -f "$expected_identity"
    return 1
  }
  write_checkpoint_identity "$expected_identity" "$project_dir" \
    "$file_selector" "$project_toolchain" || {
    rm -f "$expected_identity" "$current_selected"
    return 1
  }
  write_selected_source_list "$project_dir" "$current_selected" \
    "${selected_files[@]}"

  if [[ ! -f "$checkpoint_file" ]] || \
      ! cmp -s "$expected_identity" "$checkpoint_file"; then
    printf '%s\n' \
      'Checkpoint baseline is missing or does not match this revision, toolchain, and file selector.' \
      'Run one full validation without checkpoint or skip options to establish it.' >&2
    rm -f "$expected_identity" "$current_selected"
    return 2
  fi
  if [[ ! -f "$selected_file" ]] || \
      ! cmp -s "$current_selected" "$selected_file"; then
    printf '%s\n' \
      'The selected source set has changed since the checkpoint baseline.' \
      'Run one full validation without checkpoint or skip options to refresh it.' >&2
    rm -f "$expected_identity" "$current_selected"
    return 2
  fi
  rm -f "$expected_identity" "$current_selected"

  for source in "$owned_file" "$unowned_file" "$setup_file" "$runtime_file"; do
    if [[ ! -f "$source" ]]; then
      printf 'Checkpoint baseline manifest is missing: %s\n' "$source" >&2
      printf '%s\n' \
        'Run one full validation without checkpoint or skip options to refresh it.' >&2
      return 2
    fi
  done
  while IFS= read -r source; do
    if [[ -n "$source" && ! -f "$project_dir/$source" ]]; then
      printf 'Checkpoint source is missing: %s\n' "$source" >&2
      return 2
    fi
  done < "$owned_file"
}

run_formatter_file_group() {
  local project_dir="$1"
  local list_file="$2"
  local formatter="$3"
  local runtime_dynlibs="$4"
  local runtime_plugins="$5"
  shift 5

  local -a formatter_command=(lake env "$formatter")
  local -a runtime_environment=()
  if [[ -n "$FORMATTER_LINE_WIDTH" ]]; then
    formatter_command+=(--line-width "$FORMATTER_LINE_WIDTH")
  fi
  if [[ -n "$FORMATTER_WORKER_JOBS" ]]; then
    formatter_command+=(--jobs "$FORMATTER_WORKER_JOBS")
  fi
  if [[ -n "$runtime_dynlibs" ]]; then
    runtime_environment+=("LEANFMT_LOAD_DYNLIBS=$runtime_dynlibs")
  fi
  if [[ -n "$runtime_plugins" ]]; then
    runtime_environment+=("LEANFMT_LOAD_PLUGINS=$runtime_plugins")
  fi

  (
    cd "$project_dir" || exit 1
    if ((${#runtime_environment[@]} == 0)); then
      xargs -0 "${formatter_command[@]}" "$@" < "$list_file"
    else
      xargs -0 env "${runtime_environment[@]}" \
        "${formatter_command[@]}" "$@" < "$list_file"
    fi
  )
}

write_file_batch() {
  local output_file="$1"
  local first_index="$2"
  local count="$3"
  shift 3
  local -a files_ref=("$@")
  local index

  : > "$output_file"
  for ((index = first_index; index < first_index + count; index++)); do
    printf '%s\0' "${files_ref[$index]}" >> "$output_file"
  done
}

run_logged_formatter_file_list() {
  local project_dir="$1"
  local list_file="$2"
  local log_file="$3"
  local formatter="$4"
  local runtime_dynlibs="$5"
  local runtime_plugins="$6"
  shift 6

  {
    printf 'Project directory: %s\n' "$project_dir"
    printf 'File list: %s\n' "$list_file"
    printf 'Formatter: %s\n' "$formatter"
    printf 'Formatter invocations: serial; formatter workers: concurrent\n'
    run_formatter_file_group "$project_dir" "$list_file" "$formatter" \
      "$runtime_dynlibs" "$runtime_plugins" "$@"
  } 2>&1 | tee "$log_file"
}

run_project_validation_batches() {
  local project_name="$1"
  local project_dir="$2"
  local formatter="$3"
  local file_selector="$4"
  local selected_batch="$5"
  local start_batch="$6"
  local skip_initial_build="$7"
  local skip_final_build="$8"
  local checkpoint_mode="$9"
  shift 9
  local -a build_targets=("$@")
  local -a build_command=(build_project "$project_dir")
  local -a selected_files=()
  local -a files=()
  local -a staged_files=()
  local file

  if ((${#build_targets[@]} > 0)); then
    build_command+=("${build_targets[@]}")
  fi

  while IFS= read -r -d '' file; do
    selected_files+=("$file")
  done < <(collect_selected_lean_files "$project_dir" "$file_selector")

  if ((${#selected_files[@]} == 0)); then
    printf 'No files matched %q in %s.\n' "$file_selector" "$project_dir"
    return 0
  fi

  local log_dir="$WORK_DIR/logs/$project_name"
  local state_file="$log_dir/state"
  local selected_file="$log_dir/selected-sources"
  local owned_file="$log_dir/owned-sources"
  local unowned_file="$log_dir/unowned-sources"
  local setup_file="$log_dir/setup-files"
  local runtime_file="$log_dir/runtime-library-manifest"
  local changed_file="$log_dir/changed-sources"
  local checkpoint_file="$log_dir/checkpoint-baseline"
  local stage_dir="$project_dir/.lake/leanfmt-validation/staging"
  local batch first_index count last_index list_file log_file
  local formatter_status build_status status
  local source runtime_line runtime_dynlibs runtime_plugins
  local unowned_count=0 reuse_stage=0

  mkdir -p "$log_dir"
  printf 'Formatter batch logs: %s\n' "$log_dir"

  if ((checkpoint_mode == 1)); then
    if run_phase_result \
        "Validate checkpoint baseline for $project_name ($file_selector)" \
        validate_checkpoint_baseline "$project_dir" "$file_selector" \
          "$PROJECT_TOOLCHAIN" "$checkpoint_file" "$selected_file" \
          "$owned_file" "$unowned_file" "$setup_file" "$runtime_file" \
          "${selected_files[@]}"; then
      :
    else
      status=$?
      printf 'Stopping because the checkpoint baseline is unavailable.\n' >&2
      return "$status"
    fi
  else
    rm -f "$checkpoint_file"
    write_selected_source_list "$project_dir" "$selected_file" \
      "${selected_files[@]}"
  fi

  if ((checkpoint_mode == 1)); then
    section "Reuse validated $project_name build state ($file_selector)"
    printf 'SKIPPED: checkpoint mode reuses the recorded Lake ownership and runtime state.\n'
  elif ((skip_initial_build == 1)); then
    section "Skip initial build of $project_name before formatting ($file_selector)"
    printf 'SKIPPED: initial build disabled by --skip-initial-build.\n'
  else
    if run_phase_result \
        "Build $project_name before formatting ($file_selector)" \
        "${build_command[@]}"; then
      :
    else
      status=$?
      printf 'Stopping before formatter batches after the initial build failed.\n' >&2
      return "$status"
    fi
  fi

  if ((checkpoint_mode == 0)); then
    if run_phase_result \
        "Resolve and build selected Lake modules for $project_name ($file_selector)" \
        classify_and_build_project_sources "$project_dir" "$selected_file" \
          "$owned_file" "$unowned_file" "$setup_file"; then
      :
    else
      status=$?
      printf 'Stopping before formatter batches after Lake source resolution failed.\n' >&2
      return "$status"
    fi
  fi

  while IFS= read -r source; do
    if [[ -z "$source" ]]; then
      continue
    fi
    files+=("$project_dir/$source")
    staged_files+=("$stage_dir/$source")
  done < "$owned_file"
  while IFS= read -r source; do
    if [[ -n "$source" ]]; then
      unowned_count=$((unowned_count + 1))
    fi
  done < "$unowned_file"

  if ((unowned_count > 0)); then
    printf 'Skipping %d selected Lean source(s) without Lake module ownership:\n' \
      "$unowned_count"
    while IFS= read -r source; do
      if [[ -n "$source" ]]; then
        printf '  %s\n' "$source"
      fi
    done < "$unowned_file"
  fi

  if ((${#files[@]} == 0)); then
    printf 'No selected Lean files are owned by Lake module targets.\n'
    return 0
  fi

  if ((checkpoint_mode == 1)); then
    section "Reuse recorded Lake setup runtime for $project_name"
    printf 'SKIPPED: checkpoint mode uses %s.\n' "$runtime_file"
  else
    if run_phase_result \
        "Collect Lake setup runtime for $project_name" \
        collect_setup_runtime_manifest "$project_dir" "$setup_file" \
          "$runtime_file"; then
      :
    else
      status=$?
      printf 'Stopping before formatter batches after Lake setup discovery failed.\n' >&2
      return "$status"
    fi
  fi
  IFS= read -r runtime_line < "$runtime_file" || runtime_line=""
  if [[ "$runtime_line" != *$'\t'* ]]; then
    printf 'Invalid Lake setup runtime line: %s\n' "$runtime_line" >&2
    return 1
  fi
  runtime_dynlibs="${runtime_line%%$'\t'*}"
  runtime_plugins="${runtime_line#*$'\t'}"
  if [[ -n "${LEANFMT_LOAD_DYNLIBS:-}" ]]; then
    if [[ -n "$runtime_dynlibs" ]]; then
      runtime_dynlibs="$LEANFMT_LOAD_DYNLIBS:$runtime_dynlibs"
    else
      runtime_dynlibs="$LEANFMT_LOAD_DYNLIBS"
    fi
  fi
  if [[ -n "${LEANFMT_LOAD_PLUGINS:-}" ]]; then
    if [[ -n "$runtime_plugins" ]]; then
      runtime_plugins="$LEANFMT_LOAD_PLUGINS:$runtime_plugins"
    else
      runtime_plugins="$LEANFMT_LOAD_PLUGINS"
    fi
  fi

  if [[ -n "$start_batch" ]]; then
    reuse_stage=1
  fi
  prepare_staged_sources "$project_dir" "$stage_dir" "$owned_file" \
    "$reuse_stage" || return $?

  local total_files="${#files[@]}"
  local total_batches=$(((total_files + VALIDATION_FILES_PER_BATCH - 1) / VALIDATION_FILES_PER_BATCH))
  local first_batch=1
  local last_batch="$total_batches"

  if [[ -n "$selected_batch" ]]; then
    if ((selected_batch < 1 || selected_batch > total_batches)); then
      printf 'Batch %d is out of range for %s (%d file(s), %d batch(es)).\n' \
        "$selected_batch" "$file_selector" "$total_files" "$total_batches" >&2
      return 2
    fi
    first_batch="$selected_batch"
    last_batch="$selected_batch"
  elif [[ -n "$start_batch" ]]; then
    if ((start_batch < 1 || start_batch > total_batches)); then
      printf 'Starting batch %d is out of range for %s (%d file(s), %d batch(es)).\n' \
        "$start_batch" "$file_selector" "$total_files" "$total_batches" >&2
      return 2
    fi
    first_batch="$start_batch"
  fi

  printf 'Formatter file set: %s\n' "$file_selector"
  printf 'Selected Lean files: %d; Lake-owned files: %d; unowned files: %d\n' \
    "${#selected_files[@]}" "$total_files" "$unowned_count"
  printf 'Validation batch size: %d file(s); total batches: %d\n' \
    "$VALIDATION_FILES_PER_BATCH" "$total_batches"
  printf 'Setup runtime: native libraries %s; plugins %s\n' \
    "$([[ -n "$runtime_dynlibs" ]] && printf enabled || printf none)" \
    "$([[ -n "$runtime_plugins" ]] && printf enabled || printf none)"
  printf 'Staged formatter output: %s\n' "$stage_dir"
  if [[ -n "$FORMATTER_WORKER_JOBS" ]]; then
    printf 'Formatter worker jobs override: %d\n' "$FORMATTER_WORKER_JOBS"
  else
    printf 'Formatter worker jobs override: automatic (hardware count)\n'
  fi
  if [[ -n "$selected_batch" ]]; then
    printf 'Running selected validation batch: %d\n' "$selected_batch"
  elif [[ -n "$start_batch" ]]; then
    printf 'Starting validation at batch: %d\n' "$start_batch"
  fi
  if ((checkpoint_mode == 1)); then
    printf 'Target-project builds: skipped by checkpoint mode\n'
  elif ((${#build_targets[@]} > 0)); then
    printf 'Lake build targets:'
    printf ' %s' "${build_targets[@]}"
    printf '\n'
  else
    printf 'Lake build targets: project defaults\n'
  fi

  for ((batch = first_batch; batch <= last_batch; batch++)); do
    first_index=$(((batch - 1) * VALIDATION_FILES_PER_BATCH))
    count="$VALIDATION_FILES_PER_BATCH"
    if ((first_index + count > total_files)); then
      count=$((total_files - first_index))
    fi
    last_index=$((first_index + count - 1))

    list_file="$(mktemp "$WORK_DIR/$project_name-batch-$batch.XXXXXX")" || return 1
    write_file_batch "$list_file" "$first_index" "$count" "${staged_files[@]}"
    log_file="$log_dir/batch-$batch.log"

    printf '\n-- Formatter batch %d/%d: %d file(s), indexes %d-%d --\n' \
      "$batch" "$total_batches" "$count" "$((first_index + 1))" \
      "$((last_index + 1))"
    printf 'First file: %s\n' "${files[$first_index]#"$project_dir/"}"
    printf 'Last file:  %s\n' "${files[$last_index]#"$project_dir/"}"
    printf 'Batch log:  %s\n' "$log_file"
    printf 'batch=%d\nstatus=running\nlog=%s\n' \
      "$batch" "$log_file" > "$state_file"

    formatter_status=0
    if run_phase_result \
        "Format and check $project_name batch $batch/$total_batches ($file_selector)" \
        run_logged_formatter_file_list "$project_dir" "$list_file" "$log_file" \
          "$formatter" "$runtime_dynlibs" "$runtime_plugins" \
          --check-exception --check-idempotent; then
      :
    else
      formatter_status=$?
    fi
    if ((formatter_status == 0)); then
      printf 'batch=%d\nstatus=passed\nlog=%s\n' \
        "$batch" "$log_file" > "$state_file"
    else
      printf 'batch=%d\nstatus=failed\nexit=%d\nlog=%s\n' \
        "$batch" "$formatter_status" "$log_file" > "$state_file"
    fi

    rm -f "$list_file"
    if ((formatter_status == 130 || formatter_status == 143)); then
      printf 'Stopping at validation batch %d/%d after formatter interruption.\n' \
        "$batch" "$total_batches" >&2
      return "$formatter_status"
    fi

    if ((formatter_status != 0)); then
      printf 'Stopping at validation batch %d/%d without a final build.\n' \
        "$batch" "$total_batches" >&2
      return "$formatter_status"
    fi
  done

  if run_phase_result \
      "Apply staged formatter output for $project_name ($file_selector)" \
      apply_staged_sources "$project_dir" "$stage_dir" "$owned_file" \
        "$changed_file"; then
    :
  else
    status=$?
    printf 'Stopping before the final build after staged output could not be applied.\n' >&2
    return "$status"
  fi

  if ((checkpoint_mode == 1)); then
    section "Complete $project_name checkpoint validation ($file_selector)"
    printf 'SKIPPED: checkpoint mode omits target-project builds; run full validation before release.\n'
    rm -rf "$stage_dir"
    return 0
  fi

  if ((skip_final_build == 1)); then
    section "Skip final build of $project_name after all requested formatter batches passed ($file_selector)"
    printf 'SKIPPED: final build disabled by --skip-final-build.\n'
    rm -rf "$stage_dir"
    return 0
  fi

  if [[ -s "$changed_file" ]]; then
    if run_phase_result \
        "Build changed Lake modules in $project_name ($file_selector)" \
        build_project_source_file "$project_dir" "$changed_file"; then
      :
    else
      status=$?
      printf 'Stopping before the final project build after a changed module failed.\n' >&2
      return "$status"
    fi
  else
    section "Build changed Lake modules in $project_name ($file_selector)"
    printf 'SKIPPED: formatter output did not change any Lake-owned sources.\n'
  fi

  build_status=0
  if run_phase_result \
      "Build $project_name after all requested formatter batches passed ($file_selector)" \
      "${build_command[@]}"; then
    :
  else
    build_status=$?
  fi

  if ((build_status != 0)); then
    printf 'Stopping after the final project build failed.\n' >&2
    return "$build_status"
  fi

  if [[ -z "$selected_batch" && -z "$start_batch" ]] && \
      ((skip_initial_build == 0)); then
    write_checkpoint_identity "$checkpoint_file" "$project_dir" \
      "$file_selector" "$PROJECT_TOOLCHAIN" || return $?
    printf 'Recorded checkpoint baseline: %s\n' "$checkpoint_file"
  fi

  rm -rf "$stage_dir"
  return 0
}

main() {
  local started_at=$SECONDS
  local -a projects=()
  local default_file_selector="$DEFAULT_FILE_SELECTOR"
  local selected_batch=""
  local start_batch=""
  local reuse_clone=0
  local skip_initial_build=0
  local skip_final_build=0
  local checkpoint_mode=0
  local -a build_targets=()

  validate_positive_integer LEANFMT_VALIDATION_BATCH_SIZE \
    "$VALIDATION_FILES_PER_BATCH" || return $?
  if [[ -n "$FORMATTER_WORKER_JOBS" ]]; then
    validate_positive_integer LEANFMT_VALIDATION_FORMATTER_JOBS \
      "$FORMATTER_WORKER_JOBS" || return $?
  fi
  if [[ -n "$FORMATTER_LINE_WIDTH" ]]; then
    validate_positive_integer LEANFMT_VALIDATION_LINE_WIDTH \
      "$FORMATTER_LINE_WIDTH" || return $?
  fi

  local specification project_spec file_selector project_name project_source
  while (($# > 0)); do
    specification="$1"
    shift
    if [[ "$specification" == "--help" || "$specification" == "-h" ]]; then
      usage
      return 0
    fi
    if [[ "$specification" == "--files" ]]; then
      if (($# == 0)); then
        printf 'Missing value for --files.\n' >&2
        usage
        return 2
      fi
      default_file_selector="$1"
      shift
      continue
    fi
    if [[ "$specification" == "--batch" ]]; then
      if (($# == 0)); then
        printf 'Missing value for --batch.\n' >&2
        usage
        return 2
      fi
      validate_positive_integer "--batch" "$1" || return $?
      selected_batch="$1"
      shift
      continue
    fi
    if [[ "$specification" == "--build-target" ]]; then
      if (($# == 0)); then
        printf 'Missing value for --build-target.\n' >&2
        usage
        return 2
      fi
      build_targets+=("$1")
      shift
      continue
    fi
    if [[ "$specification" == "--start-batch" ]]; then
      if (($# == 0)); then
        printf 'Missing value for --start-batch.\n' >&2
        usage
        return 2
      fi
      validate_positive_integer "--start-batch" "$1" || return $?
      start_batch="$1"
      shift
      continue
    fi
    if [[ "$specification" == "--reuse-clone" ]]; then
      reuse_clone=1
      continue
    fi
    if [[ "$specification" == "--skip-initial-build" ]]; then
      skip_initial_build=1
      continue
    fi
    if [[ "$specification" == "--skip-final-build" ]]; then
      skip_final_build=1
      continue
    fi
    if [[ "$specification" == "--checkpoint" ]]; then
      checkpoint_mode=1
      continue
    fi

    project_spec="${specification%%::*}"
    file_selector="$default_file_selector"
    if [[ "$specification" == *"::"* ]]; then
      file_selector="${specification#*::}"
    fi

    if [[ "$project_spec" == *=* ]]; then
      project_name="${project_spec%%=*}"
      project_source="${project_spec#*=}"
      if [[ -z "$project_name" || -z "$project_source" ]]; then
        printf 'Invalid project %q; expected NAME=GIT_REPO.\n' \
          "$project_spec" >&2
        usage
        return 2
      fi
    else
      project_source="$project_spec"
      project_name="$(project_name_from_path "$project_source")"
    fi

    project_source="$(normalize_project_source "$project_source")"
    validate_project_source "$project_source" || return $?
    projects+=("$project_name|$project_source|$file_selector")
  done

  if ((${#projects[@]} == 0)); then
    printf 'Missing required git repository argument.\n' >&2
    usage
    return 2
  fi
  if [[ -n "$selected_batch" && -n "$start_batch" ]]; then
    printf '%s\n' '--batch and --start-batch cannot be used together.' >&2
    usage
    return 2
  fi
  if ((checkpoint_mode == 1)); then
    if [[ -n "$selected_batch" || -n "$start_batch" ]]; then
      printf '%s\n' '--checkpoint cannot be combined with --batch or --start-batch.' >&2
      usage
      return 2
    fi
    if ((${#build_targets[@]} > 0)); then
      printf '%s\n' '--checkpoint cannot be combined with --build-target.' >&2
      usage
      return 2
    fi
    reuse_clone=1
    skip_initial_build=1
    skip_final_build=1
  fi

  mkdir -p "$WORK_DIR"

  CURRENT_TOOLCHAIN="$(read_lean_toolchain "$REPO_ROOT")" || return $?
  run_phase "Build leanfmt" lake build fmt
  if [[ ! -x "$FORMATTER" ]]; then
    printf 'Cannot continue without the formatter executable: %s\n' "$FORMATTER" >&2
    exit 1
  fi

  local project name source file_selector project_dir
  local -a validation_arguments=()
  for project in "${projects[@]}"; do
    IFS='|' read -r name source file_selector <<< "$project"
    project_dir="$WORK_DIR/$name"

    if ((reuse_clone == 1)); then
      run_phase "Reuse existing $name clone" validate_local_git_repo "$project_dir"
    else
      run_phase "Clone $name" clone_project "$source" "$project_dir"
    fi
    if [[ ! -d "$project_dir/.git" ]]; then
      printf 'Skipping %s because its clone is unavailable.\n' "$name" >&2
      continue
    fi

    if ((reuse_clone == 0)); then
      seed_local_lake_packages "$source" "$project_dir"
      run_optional_phase "Download $name build cache" get_build_cache "$project_dir"
    fi
    if run_phase_result \
        "Select a Lean-compatible formatter for $name" \
        select_project_formatter "$name" "$project_dir"; then
      :
    else
      printf 'Skipping %s because a compatible formatter is unavailable.\n' \
        "$name" >&2
      continue
    fi
    validation_arguments=(
      "$name" "$project_dir" "$PROJECT_FORMATTER" "$file_selector"
      "$selected_batch" "$start_batch" "$skip_initial_build" "$skip_final_build"
      "$checkpoint_mode"
    )
    if ((${#build_targets[@]} > 0)); then
      validation_arguments+=("${build_targets[@]}")
    fi
    run_project_validation_batches "${validation_arguments[@]}"
  done

  section "Validation summary"
  if ((failures == 0)); then
    printf 'All external validation phases passed in %ds.\n' \
      "$((SECONDS - started_at))"
    return 0
  fi

  printf '%d validation phase(s) failed in %ds; see the diagnostics above.\n' \
    "$failures" "$((SECONDS - started_at))" >&2
  return 1
}

cd "$REPO_ROOT" || exit 1
main "$@"
