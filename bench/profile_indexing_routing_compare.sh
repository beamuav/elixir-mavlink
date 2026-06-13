#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKTREE="${INDEXING_WORKTREE:-/tmp/mavlink-indexing-old}"
BASE_REF="${INDEXING_BASE_REF:-14c4d80}"
RESULTS="$ROOT/bench/results"
SUBS="${ROUTING_SUBSCRIBERS:-100}"
FRAMES="${ROUTING_FRAMES:-200000}"

mkdir -p "$RESULTS"

run_routing_bench() {
  local dir="$1"
  local label="$2"
  local output="$3"

  echo "=== Routing microbench $label (subscribers=$SUBS) ==="
  cd "$dir"
  mix deps.get >/dev/null
  MIX_ENV=test \
    ROUTING_LABEL="$label" \
    ROUTING_OUTPUT="$output" \
    ROUTING_SUBSCRIBERS="$SUBS" \
    ROUTING_FRAMES="$FRAMES" \
    mix run --no-start bench/routing_microbench.exs
}

run_routing_bench "$ROOT" "indexed" "$RESULTS/routing-indexed.txt"

if [ ! -d "$WORKTREE/.git" ]; then
  git -C "$ROOT" worktree add "$WORKTREE" "$BASE_REF" 2>/dev/null || true
fi

for file in bench/routing_microbench.ex bench/routing_microbench.exs test/support/frame_fixtures.ex test/support/dialect_fixture.ex; do
  mkdir -p "$WORKTREE/$(dirname "$file")"
  cp "$ROOT/$file" "$WORKTREE/$file"
done

run_routing_bench "$WORKTREE" "tab2list" "$RESULTS/routing-tab2list.txt"

echo ""
echo "=== Routing lookup rate ==="
grep -E "^(Routing microbench|Subscribers:|Rate:)" \
  "$RESULTS/routing-tab2list.txt" "$RESULTS/routing-indexed.txt" || true
