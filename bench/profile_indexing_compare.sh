#!/usr/bin/env bash
set -euo pipefail

# Compare multi-fleet routing profile before/after RouteTable indexing.
#
# Usage:
#   bash bench/profile_indexing_compare.sh
#   INDEXING_BASE_REF=<commit> FLEET_VEHICLES=8 FLEET_GCS=9 bash bench/profile_indexing_compare.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKTREE="${INDEXING_WORKTREE:-/tmp/mavlink-indexing-old}"
BASE_REF="${INDEXING_BASE_REF:-14c4d80}"
RESULTS="$ROOT/bench/results"
VEHICLES="${FLEET_VEHICLES:-4}"
GCS="${FLEET_GCS:-5}"
BASE_PORT_BEFORE="${FLEET_BASE_PORT_BEFORE:-15800}"
BASE_PORT_AFTER="${FLEET_BASE_PORT_AFTER:-15900}"

mkdir -p "$RESULTS"

run_fleet_profile() {
  local dir="$1"
  local label="$2"
  local output="$3"
  local base_port="$4"

  echo "=== Profiling $label in $dir (vehicles=$VEHICLES gcs=$GCS port=$base_port) ==="
  cd "$dir"
  MIX_ENV=test \
    FLEET_VEHICLES="$VEHICLES" \
    FLEET_GCS="$GCS" \
    FLEET_BASE_PORT="$base_port" \
    PROFILE_LABEL="$label" \
    PROFILE_OUTPUT="$output" \
    mix run --no-start bench/profile_multi_fleet.exs
}

# Current branch (indexed RouteTable)
run_fleet_profile "$ROOT" "indexed" "$RESULTS/profile-fleet-indexed.txt" "$BASE_PORT_AFTER"

# Baseline before indexing change
if [ ! -d "$WORKTREE/.git" ]; then
  git -C "$ROOT" worktree add "$WORKTREE" "$BASE_REF"
fi

for file in bench/multi_fleet.ex bench/profile_multi_fleet.exs bench/support/gcs_counter.ex test/support/frame_fixtures.ex; do
  mkdir -p "$WORKTREE/$(dirname "$file")"
  cp "$ROOT/$file" "$WORKTREE/$file"
done
mkdir -p "$WORKTREE/bench/results"

run_fleet_profile "$WORKTREE" "tab2list" "$RESULTS/profile-fleet-tab2list.txt" "$BASE_PORT_BEFORE"

echo ""
echo "=== Summary ==="
grep -E "^(Multi-vehicle|Vehicles:|Aggregate rate:|ETS sizes:)" \
  "$RESULTS/profile-fleet-tab2list.txt" "$RESULTS/profile-fleet-indexed.txt" || true

echo ""
echo "=== RouteTable / matching cprof (tab2list baseline) ==="
sed -n '/== cprof/,/^$/p' "$RESULTS/profile-fleet-tab2list.txt" \
  | rg "RouteTable|Forwarder|tab2list|match_object|matching_" || true

echo ""
echo "=== RouteTable / matching cprof (indexed) ==="
sed -n '/== cprof/,/^$/p' "$RESULTS/profile-fleet-indexed.txt" \
  | rg "RouteTable|Forwarder|tab2list|match_object|matching_" || true
