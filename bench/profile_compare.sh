#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKTREE="${PROFILE_WORKTREE:-/tmp/mavlink-profile-old}"
OLD_REF="a36a711"
RESULTS="$ROOT/bench/results"

mkdir -p "$RESULTS"

run_profile() {
  local dir="$1"
  local label="$2"
  local output="$3"
  local port="$4"

  echo "=== Profiling $label in $dir (port $port) ==="
  cd "$dir"
  MIX_ENV=test PROFILE_LABEL="$label" PROFILE_OUTPUT="$output" mix run --no-start -e "
    Mix.Task.run(\"compile\")
    Code.require_file(\"bench/profile_throughput.ex\", File.cwd!())
    MAVLink.Bench.ProfileThroughput.run(
      label: \"$label\",
      output_file: \"$output\",
      port: $port
    )
  "
}

# Current branch (Phase 5)
run_profile "$ROOT" "phase5" "$RESULTS/profile-phase5.txt" 15761

# Old baseline at Phase 0 commit (central Router, same benchmark harness)
if [ ! -d "$WORKTREE/.git" ]; then
  git -C "$ROOT" worktree add "$WORKTREE" "$OLD_REF"
fi

cp "$ROOT/bench/profile_throughput.ex" "$WORKTREE/bench/profile_throughput.ex"
mkdir -p "$WORKTREE/bench/results"

run_profile "$WORKTREE" "baseline" "$RESULTS/profile-baseline.txt" 15762

echo ""
echo "=== Summary ==="
grep -E "^(TCP throughput profile|Architecture:|Rate:)" "$RESULTS/profile-baseline.txt" "$RESULTS/profile-phase5.txt" || true

echo ""
echo "=== Top cprof (baseline) ==="
sed -n '/== cprof/,/^$/p' "$RESULTS/profile-baseline.txt" | head -25

echo ""
echo "=== Top cprof (phase5) ==="
sed -n '/== cprof/,/^$/p' "$RESULTS/profile-phase5.txt" | head -25
