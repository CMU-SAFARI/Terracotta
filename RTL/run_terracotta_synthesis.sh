#!/usr/bin/env bash
# run_terracotta_synthesis.sh — Run ORFS synthesis for the TerracottaSingleTech design
# Collects area, power, and timing into a summary CSV.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORFS_FLOW="${SCRIPT_DIR}/OpenROAD-flow-scripts/flow"

# ── Design configs ─────────────────────────────
declare -A DESIGNS
DESIGNS["TerracottaSingleTech"]="${SCRIPT_DIR}/design_terracotta/nangate45/TerracottaSingleTech/config.mk"

OUT_CSV="${SCRIPT_DIR}/terracotta_synthesis_results.csv"
echo "design,area_um2,power_mW,wns_ns,tns_ns" > "$OUT_CSV"

for DESIGN in TerracottaSingleTech; do
    CFG="${DESIGNS[$DESIGN]}"
    echo "══════════════════════════════════════════════════"
    echo "  Synthesizing: $DESIGN"
    echo "  Config:       $CFG"
    echo "══════════════════════════════════════════════════"

    # Run synthesis
    if [ ! -f "$CFG" ]; then
        echo "Error: Config file not found: $CFG"
        exit 1
    fi

    echo "Running make -C \"$ORFS_FLOW\" DESIGN_CONFIG=\"$CFG\" synth"
    make -C "$ORFS_FLOW" DESIGN_CONFIG="$CFG" synth 2>&1 | tee "${SCRIPT_DIR}/${DESIGN}_synth.log"

    # ── Extract area / power / timing via OpenROAD on the synthesized DB ──
    # Uniform, macro-aware extraction (report_design_area counts std cells AND
    # SRAM macros from their LEF footprints, so no hardcoded macro-area constant
    # is needed), matching run_synthesis.sh.
    PLATFORM="nangate45"
    DESIGN_HOME="$(dirname "$CFG")"
    RPT_DIR="${DESIGN_HOME}/results/${PLATFORM}/${DESIGN}/base"
    PLAT_LIB="${ORFS_FLOW}/platforms/${PLATFORM}/lib"
    OPENROAD="${SCRIPT_DIR}/OpenROAD-flow-scripts/tools/install/OpenROAD/bin/openroad"
    [ -x "$OPENROAD" ] || OPENROAD="openroad"

    AREA="N/A"; POWER="N/A"; WNS="N/A"; TNS="N/A"
    ODB="${RPT_DIR}/1_synth.odb"
    if [[ -f "$ODB" ]]; then
        TCL="$(mktemp)"
        {
            echo "read_liberty ${PLAT_LIB}/NangateOpenCellLibrary_typical.lib"
            for l in "${PLAT_LIB}"/fakeram45_*.lib; do [ -f "$l" ] && echo "read_liberty $l"; done
            echo "read_db ${ODB}"
            [[ -f "${RPT_DIR}/1_synth.sdc" ]] && echo "read_sdc ${RPT_DIR}/1_synth.sdc"
            echo "estimate_parasitics -placement"
            echo "report_design_area"
            echo "report_power"
            echo "report_worst_slack -max"
        } > "$TCL"
        OUT="$("$OPENROAD" -no_init -exit "$TCL" 2>/dev/null || true)"
        rm -f "$TCL"
        AREA=$(echo "$OUT" | awk '/Design area/{print $3; exit}'); [[ -z "$AREA" ]] && AREA="N/A"
        PWR_W=$(echo "$OUT" | awk '/^Total/{print $5; exit}')
        [[ -n "$PWR_W" ]] && POWER=$(python3 -c "print(round($PWR_W*1000, 4))" 2>/dev/null || echo "N/A")
        WNS=$(echo "$OUT" | awk '/worst slack/{print $NF; exit}'); [[ -z "$WNS" ]] && WNS="N/A"
    fi

    echo "${DESIGN},${AREA},${POWER},${WNS},${TNS}" >> "$OUT_CSV"
    echo "  → ${DESIGN}: area=${AREA} um², power=${POWER} mW, WNS=${WNS} ns, TNS=${TNS} ns"
    echo ""
done

echo ""
echo "══════════════════════════════════════════════════"
echo "  Summary written to: $OUT_CSV"
echo "══════════════════════════════════════════════════"
column -t -s',' "$OUT_CSV"
