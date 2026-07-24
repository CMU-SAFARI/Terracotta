#!/usr/bin/env bash
#
# run_with_slurm.sh -- Terracotta MICRO 2026 artifact: BARE-METAL SLURM sweep.
#
# Thin wrapper over run.py for the NON-container path: forwards all arguments and
# adds --mode slurm --no-container, so each SLURM job runs the host-built binary
# "<ramulator-bin> -f <config>" directly on the compute node (no podman, no image
# tar). This is the R2-verified bare-metal escape hatch; the containerized SLURM
# path lives in run_with_slurm_podman.sh.
#
# An OPTIONAL leading integer sets the thread count (default = nproc) and is
# forwarded as --threads (harmless in SLURM mode -- jobs are submitted, not run
# in a local pool -- but kept for parity with run_with_personalcomputer.sh).
# Everything else is forwarded verbatim to run.py (technique selector + any extra
# flags). run.py owns ALL preflight: it validates the --ramulator-bin binary and
# traces, honors --trace-dir/--ramulator-bin/--result-dir overrides, emits the
# soft /home warning, and skips checks for --status / --generate-only.
#
# Usage:
#   ./run_with_slurm.sh [THREADS] <technique|all> [extra run.py flags...]
# Examples:
#   ./run_with_slurm.sh all
#   ./run_with_slurm.sh 16 all
#   ./run_with_slurm.sh chargecache --core-setup single_core
#   ./run_with_slurm.sh masa --generate-only     # write configs+jobfile, no submit
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

echo "[INFO] Terracotta: SLURM sweep, bare-metal (host ramulator2 binary, --no-container)."
echo "[INFO] Track with ./check_run_status.sh"
exec python3 run.py "$@" --mode slurm --no-container --threads "$THREADS"
