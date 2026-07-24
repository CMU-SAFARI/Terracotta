#!/usr/bin/env bash
# run_hw_with_personalcomputer.sh -- RTL hardware-complexity run on your own
# machine in a container. Build first: ./build_hw.sh
# Runtime defaults to podman; override with RUNTIME=docker (matches build_hw.sh).
# Extra flags forward to the driver (e.g. --batch terracotta).
set -euo pipefail
cd "$(dirname "$0")/RTL"   # wrapper lives at repo root; the driver lives in RTL/
RUNTIME="${RUNTIME:-podman}"
echo "[hw] personal-computer run ($RUNTIME container). Build first: ./build_hw.sh"
exec ./run_hardware_complexity.sh --runtime "$RUNTIME" "$@"
