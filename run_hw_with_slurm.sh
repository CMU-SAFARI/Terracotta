#!/usr/bin/env bash
# run_hw_with_slurm.sh -- RTL hardware-complexity run via SLURM inside the
# terracotta-openroad container. Build first: ./build_hw.sh
# Runtime defaults to podman (rootless -> compute node needs /etc/subuid ranges);
# override with RUNTIME=docker (matches build_hw.sh).
set -euo pipefail
cd "$(dirname "$0")/RTL"   # wrapper lives at repo root; the driver lives in RTL/
RUNTIME="${RUNTIME:-podman}"
echo "[hw] SLURM run, $RUNTIME container. Build first: ./build_hw.sh"
exec ./run_hardware_complexity.sh --slurm --runtime "$RUNTIME" "$@"
