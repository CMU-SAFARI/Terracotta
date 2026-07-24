#!/bin/bash
# map_all.sh — Map all trigger and update kernels onto CGRA via Morpher
#
# Usage: bash scripts/map_all.sh [config]
# Default config: configs/hycube_6x6_light.yaml
#
# Prerequisites:
#   cd morpher && git submodule update --init --remote && bash build_all.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CGRA_DIR="$(dirname "$SCRIPT_DIR")"
MORPHER_DIR="$CGRA_DIR/morpher"
CONFIG="${1:-$CGRA_DIR/configs/hycube_6x6_light.yaml}"

# Kernel source path (relative to Morpher_DFG_Generator/benchmarks/) → function name
declare -a KERNELS=(
    "terracotta_triggers/chargecache_trigger_v7_2way.c:chargecache_trigger"
    "terracotta_triggers/masa_trigger_v6b_override.c:masa_trigger"
    "terracotta_triggers/mopac_trigger_v2_perbank.c:mopac_trigger"
    "terracotta_triggers/prada_trigger_v2_lut.c:prada_trigger"
    "terracotta_updates/chargecache_update.c:chargecache_update"
    "terracotta_updates/masa_update.c:masa_update"
    "terracotta_updates/mopac_update.c:mopac_update"
    "terracotta_updates/prada_update.c:prada_update"
)

echo "========================================"
echo "Terracotta CGRA Kernel Mapping"
echo "Config: $CONFIG"
echo "========================================"

# Sync kernel sources into Morpher benchmark dirs
echo ""
echo "--- Syncing kernel sources ---"
BENCH_DIR="$MORPHER_DIR/Morpher_DFG_Generator/benchmarks"
mkdir -p "$BENCH_DIR/terracotta_triggers" "$BENCH_DIR/terracotta_updates"

for tech in chargecache masa mopac prada; do
    for f in "$CGRA_DIR/kernels/$tech/"*_trigger*.c "$CGRA_DIR/kernels/$tech/"*_update*.c; do
        [ -f "$f" ] || continue
        base="$(basename "$f")"
        if [[ "$base" == *trigger* ]]; then
            cp "$f" "$BENCH_DIR/terracotta_triggers/$base"
        else
            cp "$f" "$BENCH_DIR/terracotta_updates/$base"
        fi
    done
done
echo "Synced."

# Map each kernel
printf "\n%-40s %4s %8s\n" "Kernel" "II" "Latency"
printf "%-40s %4s %8s\n" "------" "--" "-------"

FAIL=0
for entry in "${KERNELS[@]}"; do
    IFS=':' read -r src func <<< "$entry"

    cd "$MORPHER_DIR"
    output=$(python3 run_morpher.py "$src" "$func" "$CONFIG" 2>&1)

    ii=$(echo "$output" | grep -oP 'Map Success with II = \K\d+' || true)
    lat=$(echo "$output" | grep -oP '\(lat = \K\d+' || true)

    if [ -n "$ii" ] && [ -n "$lat" ]; then
        printf "%-40s %4s %8s\n" "$src" "$ii" "$lat"
    else
        printf "%-40s %4s %8s\n" "$src" "FAIL" "FAIL"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "========================================"
if [ "$FAIL" -eq 0 ]; then
    echo "All 8 kernels mapped successfully."
else
    echo "$FAIL kernel(s) failed to map."
fi
echo "========================================"
