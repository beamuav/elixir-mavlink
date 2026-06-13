#!/usr/bin/env bash
set -euo pipefail

# Throughput-only before/after indexing comparison (no profiler overhead).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKTREE="${INDEXING_WORKTREE:-/tmp/mavlink-indexing-old}"
BASE_REF="${INDEXING_BASE_REF:-14c4d80}"
RESULTS="$ROOT/bench/results"
VEHICLES="${FLEET_VEHICLES:-4}"
GCS="${FLEET_GCS:-5}"

mkdir -p "$RESULTS"

run_throughput() {
  local dir="$1"
  local label="$2"
  local output="$3"
  local base_port="$4"

  echo "=== Throughput $label in $dir (vehicles=$VEHICLES gcs=$GCS port=$base_port) ==="
  cd "$dir"
  mix deps.get >/dev/null
  MIX_ENV=test \
    FLEET_VEHICLES="$VEHICLES" \
    FLEET_GCS="$GCS" \
    FLEET_BASE_PORT="$base_port" \
    FLEET_LABEL="$label" \
    FLEET_OUTPUT="$output" \
    mix run --no-start bench/multi_fleet_throughput.exs
}

run_throughput "$ROOT" "indexed" "$RESULTS/fleet-indexed.txt" 15900

if [ ! -d "$WORKTREE/.git" ]; then
  git -C "$ROOT" worktree add "$WORKTREE" "$BASE_REF" 2>/dev/null || true
fi

for file in bench/multi_fleet.ex bench/multi_fleet_throughput.exs bench/support/gcs_counter.ex test/support/frame_fixtures.ex lib/mavlink/tcp_out_connection.ex; do
  mkdir -p "$WORKTREE/$(dirname "$file")"
  cp "$ROOT/$file" "$WORKTREE/$file"
done
mkdir -p "$WORKTREE/bench/results"

run_throughput "$WORKTREE" "tab2list" "$RESULTS/fleet-tab2list.txt" 15800

echo ""
echo "=== Summary ==="
grep -E "^(Multi-vehicle|Aggregate rate:|Delivery balance:|  per-vehicle GCS with zero|  per-vehicle min/max)" \
  "$RESULTS/fleet-tab2list.txt" "$RESULTS/fleet-indexed.txt" || true
