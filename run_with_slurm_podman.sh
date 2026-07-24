#!/usr/bin/env bash
#
# run_with_slurm_podman.sh -- Terracotta MICRO 2026 artifact: full sweep via SLURM,
# each job running ramulator2 inside the terracotta:latest container (podman).
#
# Bare-metal is the DEFAULT execution substrate for the simulations (run_with_slurm.sh,
# the host-built ramulator2 binary). This wrapper is the container alternative: a thin
# forwarder to run.py with `--mode slurm` (which defaults to `--runtime podman`,
# containerized). The image is self-contained -- it builds ramulator2 in-image and exposes it on
# PATH as `ramulator2` -- so run ./build.sh FIRST to produce terracotta_artifact.tar,
# which each compute-node job idempotently loads before running.
#
# run.py owns all preflight: container runtime on PATH, --result-dir/--trace-dir
# under the repo (only REPO_ROOT is bind-mounted), image tar present, and a soft
# /home warning for SLURM. Any extra flags (e.g. --no-container, --runtime,
# --generate-only, --core-setup) pass through verbatim via "$@".
#
# Usage:
#   ./run_with_slurm_podman.sh <technique|all> [extra run.py flags...]
# Examples:
#   ./build.sh                                    # build image + tar (once)
#   ./run_with_slurm_podman.sh all
#   ./run_with_slurm_podman.sh chargecache --core-setup single_core
#
set -euo pipefail
cd "$(dirname "$0")"
echo "[INFO] Terracotta: SLURM sweep, each job in the terracotta:latest container."
echo "[INFO] Run ./build.sh first (creates terracotta_artifact.tar for compute nodes)."
exec python3 run.py "$@" --mode slurm
