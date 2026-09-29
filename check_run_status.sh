#!/usr/bin/env bash
#
# check_run_status.sh -- Terracotta MICRO 2026 artifact: report run status.
#
# Thin wrapper over `run.py --status`. Status mode reads the results tree ONLY:
# run.py skips ALL preflight in --status mode, so this needs no container runtime,
# no terracotta:latest image (or its tar), no host ramulator2 binary, and no
# traces -- it works the same whether the sweep ran containerized (the new
# default) or bare-metal (--no-container). All flags are forwarded verbatim, so
# run.py owns everything; this wrapper just cd's to the repo and calls it.
#
# Prints a done/pending/failed summary per (technique, core_setup) and exits
# nonzero unless every selected set is fully DONE, so evaluators can gate on
# completion, e.g.:
#
#     if ./check_run_status.sh chargecache; then echo "all done"; fi
#
# Usage:
#   ./check_run_status.sh <technique|all> [extra run.py flags...]
# Examples:
#   ./check_run_status.sh all
#   ./check_run_status.sh chargecache --core-setup single_core
#   ./check_run_status.sh masa --result-dir ./results
#
set -euo pipefail
cd "$(dirname "$0")"

echo "[INFO] Terracotta: reporting run status (run.py --status; reads results tree only)." >&2
exec python3 run.py "$@" --status
