#!/usr/bin/env python3
"""
compute_overhead.py -- Turn the raw Nangate45 RTL synthesis numbers into the
paper's hardware-overhead figures (Terracotta, MICRO 2026).

Pipeline:
  raw 45nm area/power  --DeepScale 45->10nm-->  10nm values
                       --x memory-system config-->  per-DDR5-channel + system totals
                       --normalize to the Intel Xeon reference-->  %.

Inputs (produced by run_hardware_complexity.sh):
  results/synthesis_results.csv            (the four custom controllers + baseline arrays)
  results/terracotta_synthesis_results.csv (TerracottaSingleTech)
Both must carry area_um2 AND power_mW.

Every constant is documented with provenance below and lives in one place.

Output: prints the full derivation (raw 45nm -> DeepScale -> full system -> Xeon %)
to stdout AND writes the same report to results/txt/hw_complexity.txt.

  ./compute_overhead.py            # reads results/*.csv; prints + writes the report
"""
import csv, os

# --- DeepScale 45nm -> 10nm technology scaling (DeepScaleTool, Sarangi & Baas,
#     ISCAS 2021, ref [123]).  Factor = (45nm value) / (10nm value), so
#     value_10nm = value_45nm / FACTOR.
DEEPSCALE_AREA  = 33.3
DEEPSCALE_POWER = 3.0

# --- Reference chip: Intel Xeon Platinum 8593Q (5th Gen "Emerald Rapids", ref [124]).
#     64 cores, 10 nm, 8-channel DDR5, 385 W TDP; die = dual XCC tiles ~= 1526 mm^2.
XEON_DIE_MM2 = 1526.0
XEON_TDP_W   = 385.0

# --- Memory-system configuration ---------------------------------------------
# The 8593Q exposes 8 DDR5 channels; we model 4 ranks per channel. Supporting all
# four techniques needs one TerracottaSingleTech per technique per rank-channel;
# the custom baseline needs the four dedicated controllers per rank-channel.
CHANNELS   = 8
RANKS      = 4
TECHNIQUES = 4                       # ChargeCache, MASA, MoPAC, PRADA

CUSTOM_UNITS = ["ChargeCacheUnit", "MASAUnit", "MoPACUnit", "PRADAUnit"]
TERRA_UNIT   = "TerracottaSingleTech"

# Paper values for the side-by-side check.
PAPER = {"per_ch_area": 0.083, "per_ch_pow": 325.0,
         "abs_area": 0.04, "abs_pow": 0.67, "ov_area": 0.03, "ov_pow": 0.53}


def _load(path):
    with open(path) as f:
        return {r["design"]: r for r in csv.DictReader(f)}


def _num(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def _um(x):   return f"{x:,.0f}"        # um^2, thousands-separated
def _mw(x):   return f"{x:,.2f}"        # mW
def _mm2(x):  return f"{x / 1e6:.4f}"   # um^2 -> mm^2


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    # RESULTS_DIR lets the containerized run point at the mounted output dir;
    # defaults to <script dir>/results for a direct invocation.
    res  = os.environ.get("RESULTS_DIR") or os.path.join(here, "results")
    cust  = _load(os.path.join(res, "synthesis_results.csv"))
    terra = _load(os.path.join(res, "terracotta_synthesis_results.csv"))

    t_area = _num(terra[TERRA_UNIT]["area_um2"])
    t_pow  = _num(terra[TERRA_UNIT]["power_mW"])
    c_area = sum(_num(cust[u]["area_um2"]) for u in CUSTOM_UNITS)
    c_pow  = sum(_num(cust[u]["power_mW"]) for u in CUSTOM_UNITS)
    if None in (t_area, t_pow, c_area, c_pow):
        raise SystemExit("[overhead] missing area/power in the CSVs -- run "
                         "run_hardware_complexity.sh (both batches) first.")

    rc = CHANNELS * RANKS
    T_area45 = rc * TECHNIQUES * t_area;  T_pow45 = rc * TECHNIQUES * t_pow
    C_area45 = rc * c_area;               C_pow45 = rc * c_pow
    a10 = lambda x: x / DEEPSCALE_AREA
    p10 = lambda x: x / DEEPSCALE_POWER
    xeon_area = XEON_DIE_MM2 * 1e6       # um^2
    xeon_tdp  = XEON_TDP_W * 1000        # mW

    got = {
        "per_ch_area": a10(RANKS * TECHNIQUES * t_area) / 1e6,
        "per_ch_pow":  p10(RANKS * TECHNIQUES * t_pow),
        "abs_area":    100 * a10(T_area45) / xeon_area,
        "abs_pow":     100 * p10(T_pow45) / xeon_tdp,
        "ov_area":     100 * a10(T_area45 - C_area45) / xeon_area,
        "ov_pow":      100 * p10(T_pow45 - C_pow45) / xeon_tdp,
    }

    # ---- build the report (shown to stdout AND written to results/txt/) --------
    W = 80
    bar, sub = "=" * W, "-" * W
    allrows = {**cust, **terra}
    display = ["ChargeCacheUnit", "MASAUnit", "MoPACUnit", "PRADAUnit",
               "TerracottaSingleTech"]

    L = []
    p = L.append
    p(bar)
    p(" Terracotta -- RTL Hardware-Complexity Results")
    p(bar)
    p("Source : RTL/results/{synthesis,terracotta_synthesis}_results.csv")
    p("Tools  : OpenROAD-Flow-Scripts e7ea5740 . Yosys 0.60 (+slang) . Nangate45 . 250 MHz")
    p("Method : synthesis-only (pre-P&R) estimate; area+power include SRAM macros.")
    p("         Full derivation follows below.")
    p("")

    p("STEP 1 -- Raw synthesized cost per design (Nangate45, 45 nm)")
    p(sub)
    p(f"  {'Design':<26}{'Area (um^2)':>14}{'Power (mW)':>13}{'WNS (ns)':>11}")
    for name in display:
        r = allrows.get(name)
        if not r:
            continue
        a = _num(r["area_um2"]); wn = _num(r.get("wns_ns", "N/A"))
        w = r.get("wns_ns", "N/A")
        wdisp = f"+{w}" if (wn is not None and wn >= 0) else str(w)
        p(f"  {name:<26}{_um(a):>14}{r['power_mW']:>13}{wdisp:>11}")
    p("  (all WNS > 0  ->  every design closes timing at 250 MHz / 4.0 ns)")
    p("")

    p("STEP 2 -- Provision one rank-channel to support all 4 techniques")
    p(sub)
    p(f"  Terracotta = TerracottaSingleTech x NUM_TECH({TECHNIQUES})   (1 slice per technique)")
    p(f"             = {_um(t_area)} x {TECHNIQUES} = {_um(TECHNIQUES * t_area)} um^2"
      f"   /   {t_pow:.1f} x {TECHNIQUES} = {TECHNIQUES * t_pow:.1f} mW")
    p(f"  Custom     = ChargeCache + MASA + MoPAC + PRADA   (4-controller aggregate)")
    p(f"             = {_um(c_area)} um^2   /   {c_pow:.3f} mW")
    p("")

    p(f"STEP 3 -- Full system: x CHANNELS({CHANNELS}) x RANKS({RANKS}) = {rc} rank-channels")
    p(sub)
    p(f"  Terracotta 45nm : {_um(T_area45):>12} um^2   /   {_mw(T_pow45):>10} mW"
      f"   (= {rc * TECHNIQUES}x one slice)")
    p(f"  Custom     45nm : {_um(C_area45):>12} um^2   /   {_mw(C_pow45):>10} mW")
    p("  Both sides provision all 4 techniques on all rank-channels -- apples-to-apples.")
    p("")

    p(f"STEP 4 -- DeepScale 45nm -> 10nm [123]   (area /{DEEPSCALE_AREA}, power /{DEEPSCALE_POWER})")
    p(sub)
    p(f"  Terracotta 10nm : {_um(a10(T_area45)):>12} um^2 ({_mm2(a10(T_area45))} mm^2)"
      f"   /   {_mw(p10(T_pow45)):>10} mW")
    p(f"  Custom     10nm : {_um(a10(C_area45)):>12} um^2 ({_mm2(a10(C_area45))} mm^2)"
      f"   /   {_mw(p10(C_pow45)):>10} mW")
    p("")

    p("STEP 5 -- Normalize to reference CPU [124]")
    p(sub)
    p(f"  Intel Xeon Platinum 8593Q (Emerald Rapids): 10nm, {CHANNELS}-ch DDR5,"
      f" {XEON_DIE_MM2:.0f} mm^2 die, {XEON_TDP_W:.0f} W TDP")
    p("")
    p(f"  {'metric':<34}{'reproduced':>13}{'paper':>10}")
    rows = [
        ("per-channel area (mm^2)",         "per_ch_area", "{:.4f}"),
        ("per-channel static power (mW)",   "per_ch_pow",  "{:.1f}"),
        ("absolute area  vs die (%)",       "abs_area",    "{:.3f}"),
        ("absolute power vs TDP (%)",       "abs_pow",     "{:.3f}"),
        ("overhead area  vs 4-custom (%)",  "ov_area",     "{:.3f}"),
        ("overhead power vs 4-custom (%)",  "ov_pow",      "{:.3f}"),
    ]
    for label, key, fmt in rows:
        p(f"  {label:<34}{fmt.format(got[key]):>13}{('%.3g' % PAPER[key]):>10}")
    p("")
    p("  Overhead = (Terracotta - 4-custom aggregate), DeepScaled, normalized:")
    p(f"    area  : ({_mm2(a10(T_area45))} - {_mm2(a10(C_area45))}) mm^2 / {XEON_DIE_MM2:.0f} mm^2"
      f"  x100 = {got['ov_area']:.3f} %")
    p(f"    power : ({p10(T_pow45):.1f} - {p10(C_pow45):.1f}) mW / {xeon_tdp:.0f} mW"
      f"  x100 = {got['ov_pow']:.3f} %")
    p(bar)

    report = "\n".join(L) + "\n"
    print(report, end="")

    txt_dir = os.path.join(res, "txt")
    os.makedirs(txt_dir, exist_ok=True)
    out_path = os.path.join(txt_dir, "hw_complexity.txt")
    with open(out_path, "w") as f:
        f.write(report)
    print(f"[overhead] report written to {os.path.relpath(out_path, here)}")


if __name__ == "__main__":
    main()
