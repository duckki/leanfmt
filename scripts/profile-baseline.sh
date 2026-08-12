#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/profile-baseline.sh [--record FILE | --compare FILE]

Profiles a stable local formatter workload and reports median phase timings.
--record writes the medians for a later same-machine comparison.
--compare fails when a phase exceeds the recorded value by the configured tolerance.

Environment:
  LEANFMT_PROFILE_SAMPLES       Timed samples after one warmup (default: 5)
  LEANFMT_PROFILE_THRESHOLD_PCT Allowed relative increase (default: 25)
  LEANFMT_PROFILE_FLOOR_MS      Allowed absolute increase floor (default: 10)
EOF
}

mode=report
baseline_file=
case "${1:-}" in
  "") ;;
  --record|--compare)
    mode=${1#--}
    baseline_file=${2:-}
    if [[ -z "$baseline_file" || $# -ne 2 ]]; then
      usage >&2
      exit 2
    fi
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

samples=${LEANFMT_PROFILE_SAMPLES:-5}
threshold_pct=${LEANFMT_PROFILE_THRESHOLD_PCT:-25}
floor_ms=${LEANFMT_PROFILE_FLOOR_MS:-10}
if ! [[ "$samples" =~ ^[1-9][0-9]*$ && "$threshold_pct" =~ ^[0-9]+$ && "$floor_ms" =~ ^[0-9]+$ ]]; then
  echo "profile-baseline: sample and tolerance values must be nonnegative integers" >&2
  exit 2
fi

targets=(
  Tests/Performance/Representative.leaninput
  LeanFmt/SyntaxTree.lean
  LeanFmt/Formatter/OriginalTree.lean
  LeanFmt/Tests/Suite.lean
)
phases=(normalize parse syntax-tree render format-total)

scratch=$(mktemp -d "${TMPDIR:-/tmp}/leanfmt-profile.XXXXXX")
trap 'rm -rf "$scratch"' EXIT

lake build fmt-test >/dev/null

run_sample() {
  local sample=$1
  local sample_dir="$scratch/sample-$sample"
  local target copy output phase value
  local copies=()
  mkdir -p "$sample_dir"
  for target in "${targets[@]}"; do
    copy="$sample_dir/$target"
    mkdir -p "$(dirname "$copy")"
    cp "$target" "$copy"
    copies+=("$copy")
  done
  output=$(lake exe fmt-test --profile "${copies[@]}" 2>&1)
  for phase in "${phases[@]}"; do
    value=$(printf '%s\n' "$output" | awk -F': ' -v phase="$phase" '
      $1 == "leanfmt profile" && $(NF - 1) == phase {
        sub(/ms$/, "", $NF)
        total += $NF
      }
      END { print total + 0 }
    ')
    printf '%s\n' "$value" >> "$scratch/$phase.samples"
  done
}

median() {
  sort -n "$1" | awk '
    { values[NR] = $1 }
    END {
      if (NR % 2 == 1) print values[(NR + 1) / 2]
      else print int((values[NR / 2] + values[NR / 2 + 1]) / 2)
    }
  '
}

run_sample warmup
for ((sample = 1; sample <= samples; sample++)); do
  run_sample "$sample"
done

results="$scratch/results"
{
  echo "version=1"
  echo "samples=$samples"
  for phase in "${phases[@]}"; do
    key=${phase//-/_}_ms
    echo "$key=$(median "$scratch/$phase.samples")"
  done
} > "$results"

echo "leanfmt profile baseline (median of $samples samples):"
grep '_ms=' "$results" | sed 's/^/  /'

if [[ "$mode" == record ]]; then
  cp "$results" "$baseline_file"
  echo "recorded baseline: $baseline_file"
elif [[ "$mode" == compare ]]; then
  if [[ ! -f "$baseline_file" ]]; then
    echo "profile-baseline: baseline file not found: $baseline_file" >&2
    exit 2
  fi
  failed=0
  for phase in "${phases[@]}"; do
    key=${phase//-/_}_ms
    current=$(awk -F= -v key="$key" '$1 == key { print $2 }' "$results")
    baseline=$(awk -F= -v key="$key" '$1 == key { print $2 }' "$baseline_file")
    if [[ -z "$baseline" || ! "$baseline" =~ ^[0-9]+$ ]]; then
      echo "profile-baseline: missing or invalid $key in $baseline_file" >&2
      exit 2
    fi
    relative_allowance=$(( (baseline * threshold_pct + 99) / 100 ))
    allowance=$relative_allowance
    if (( allowance < floor_ms )); then
      allowance=$floor_ms
    fi
    limit=$((baseline + allowance))
    if (( current > limit )); then
      echo "profile regression: $key=${current}ms, baseline=${baseline}ms, limit=${limit}ms" >&2
      failed=1
    fi
  done
  if (( failed != 0 )); then
    exit 1
  fi
  echo "profile comparison passed: $baseline_file"
fi
