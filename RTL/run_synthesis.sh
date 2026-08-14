#!/usr/bin/env bash
# run_synthesis.sh — Run ORFS synthesis for the baseline building-block arrays
# (TriggerArray/UpdateArray/ActionArray) and the four custom per-technique
# controllers (ChargeCache, MASA, MoPAC, PRADA).
# Collects area, power, and timing into a summary CSV.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORFS_FLOW="${SCRIPT_DIR}/OpenROAD-flow-scripts/flow"

# ── Design configs (relative to ORFS flow/) ─────────────────────────────
declare -A DESIGNS
DESIGNS["TriggerArray"]="${SCRIPT_DIR}/design/nangate45/TriggerArray/config.mk"
DESIGNS["UpdateArray"]="${SCRIPT_DIR}/design/nangate45/UpdateArray/config.mk"
DESIGNS["ActionArray"]="${SCRIPT_DIR}/design/nangate45/ActionArray/config.mk"
DESIGNS["ChargeCacheUnit"]="${SCRIPT_DIR}/design_chargecache/nangate45/ChargeCacheUnit/config.mk"
DESIGNS["MASAUnit"]="${SCRIPT_DIR}/design_masa/nangate45/MASAUnit/config.mk"
DESIGNS["MoPACUnit"]="${SCRIPT_DIR}/design_mopac/nangate45/MoPACUnit/config.mk"
DESIGNS["PRADAUnit"]="${SCRIPT_DIR}/design_prada/nangate45/PRADAUnit/config.mk"

OUT_CSV="${SCRIPT_DIR}/synthesis_results.csv"
echo "design,area_um2,power_mW,wns_ns,tns_ns" > "$OUT_CSV"

for DESIGN in TriggerArray UpdateArray ActionArray ChargeCacheUnit MASAUnit MoPACUnit PRADAUnit; do
    CFG="${DESIGNS[$DESIGN]}"
    echo "══════════════════════════════════════════════════"
    echo "  Synthesizing: $DESIGN"
    echo "  Config:       $CFG"
    echo "══════════════════════════════════════════════════"

    # Run synthesis
    make -C "$ORFS_FLOW" DESIGN_CONFIG="$CFG" synth 2>&1 | tee "${SCRIPT_DIR}/${DESIGN}_synth.log"

    # ── Extract area / power / timing via OpenROAD on the synthesized DB ──
    # The configs set WORK_HOME = DESIGN_DIR, so ORFS writes results/logs under
    # each design's directory (not under flow/). OpenROAD report_design_area
    # counts standard cells AND SRAM macros (from their LEF footprints), so no
    # per-design macro add-back is needed.
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
        # Design area <um2> <util>% utilization.
        AREA=$(echo "$OUT" | awk '/Design area/{print $3; exit}'); [[ -z "$AREA" ]] && AREA="N/A"
        # report_power "Total" row: internal switching leakage TOTAL(W) 100.0%
        PWR_W=$(echo "$OUT" | awk '/^Total/{print $5; exit}')
        [[ -n "$PWR_W" ]] && POWER=$(python3 -c "print(round($PWR_W*1000, 4))" 2>/dev/null || echo "N/A")
        # worst slack (ns); WNS = min(0, slack)
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
echo ""

# ── Aggregate of the four custom controllers (the paper's comparison baseline) ──
echo "── Custom-controller aggregate (ChargeCache + MASA + MoPAC + PRADA) ──"
awk -F',' '
  NR>1 && ($1=="ChargeCacheUnit" || $1=="MASAUnit" || $1=="MoPACUnit" || $1=="PRADAUnit") {
    if ($2 != "N/A") sum_area += $2
    if ($3 != "N/A") sum_pow  += $3
  }
  END { printf "  Total area: %.2f um²   Total power: %.3f mW\n", sum_area, sum_pow }
' "$OUT_CSV"
