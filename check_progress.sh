#!/usr/bin/env bash
#
# check_progress.sh -- aggregate progress viewer for the Terracotta sweep.
#
# One snapshot, or a live view with --watch. Read-only (safe to run anytime,
# including while a sweep is in progress or after you reconnect to the cluster).
#
# Usage:
#   ./check_progress.sh                 # one snapshot
#   ./check_progress.sh --watch         # refresh every 30s (Ctrl-C to stop)
#   ./check_progress.sh --watch 60      # refresh every 60s
#   ./check_progress.sh --result-dir DIR [--watch [SECS]]
#
set -euo pipefail
cd "$(dirname "$0")"

WATCH=0
INTERVAL=30
PYARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --watch) WATCH=1; shift
             if [[ "${1:-}" =~ ^[0-9]+$ ]]; then INTERVAL="$1"; shift; fi ;;
    *)       PYARGS+=("$1"); shift ;;
  esac
done

snapshot() {
  echo "Terracotta sweep progress  --  $(date)"
  python3 progress.py "${PYARGS[@]}"
  # Also show live SLURM queue depth for context (jobs still queued/running).
  echo "SLURM queue (this user): $(squeue -u "$USER" -h 2>/dev/null | wc -l) job(s)"
}

if [ "$WATCH" -eq 1 ]; then
  while true; do clear; snapshot; sleep "$INTERVAL"; done
else
  snapshot
fi
