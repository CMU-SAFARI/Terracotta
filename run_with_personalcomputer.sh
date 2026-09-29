#!/usr/bin/env bash
#
# run_with_personalcomputer.sh -- Terracotta MICRO 2026 artifact: local N-thread run.
#
# Thin forwarder over run.py (--mode local). Local execution CONTAINERIZES BY
# DEFAULT: each per-job ramulator2 runs inside the terracotta:latest image.
# Run ./build.sh first (creates the image in your local podman store).
#
# An OPTIONAL leading integer sets the thread count (default = nproc); everything
# else is forwarded verbatim to run.py (technique selector + any extra flags).
# run.py owns all preflight (runtime on PATH, image present, paths under repo).
#
# Passthrough: --no-container (bare-metal host --ramulator-bin) and
# --runtime {podman} flow through verbatim via "$@".
#
# Usage:
#   ./run_with_personalcomputer.sh [THREADS] <technique|all> [extra run.py flags...]
# Examples:
#   ./run_with_personalcomputer.sh 16 prada                # containerized (default)
#   ./run_with_personalcomputer.sh all                     # threads = nproc
#   ./run_with_personalcomputer.sh chargecache --core-setup single_core
#   ./run_with_personalcomputer.sh 16 prada --no-container # bare-metal host binary
#
set -euo pipefail
cd "$(dirname "$0")"

# Optional leading integer = thread count; otherwise default to nproc and leave
# the first arg (e.g. a technique or "all") for run.py.
if [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]; then
  THREADS="$1"; shift
else
  THREADS="$(nproc 2>/dev/null || echo 4)"
fi

echo "[INFO] Terracotta: local run with $THREADS threads (mode=local, container by default)."
echo "[INFO] Run ./build.sh first if you have not built the terracotta:latest image."
exec python3 run.py "$@" --mode local --threads "$THREADS"
