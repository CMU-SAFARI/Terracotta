"""Build ``results/csv/figureN.csv`` (plot-ready) from the concatenated tidy CSV.

Each builder emits the pinned generic schema so every ``figureN.py`` plotter stays trivial:

    panel,panel_order,x,x_order,series,series_order,value,err

Builders are keyed to the manifest figure ids (``main_speedup``, ``main_pum``,
``main_mitigation``, ``figure16``, ...) so the paper figure *number* is a one-line map away
from a renumber; only ``figure16`` is number-bound in the manifests, the rest are inferred
per the R4 spec / paper scout and noted below. Figs 13 and 14 are cross-technique derived
figures with no manifest id.

Robustness: the pipeline runs while a full sweep is still in flight, so a technique/core
setup may have zero finished rows. Every builder degrades to emitting fewer (or no) rows for
whatever data is absent -- it never raises on missing data. mopac / prada / chargecachemasa
builders are effectively no-ops until their runs land.
"""

import argparse
import csv
import glob
import os
import sys

import pandas as pd

from common import derive
from common.manifest import load_manifest

FIG_HEADER = ["panel", "panel_order", "x", "x_order",
              "series", "series_order", "value", "err"]

DEFAULT_TIDY = "results/csv/tidy.csv"
OUT_DIR = "results/csv"

# Technique dir -> manifest path. Loaded lazily; a technique whose manifest/dir is absent is
# simply skipped.
TECHNIQUE_DIRS = ("chargecache", "masa", "mopac", "chargecachemasa", "prada")


# --------------------------------------------------------------------------- #
# Manifest helpers
# --------------------------------------------------------------------------- #

def load_manifests():
    """Return ``{dir_name: Manifest}`` for every technique whose manifest loads."""
    out = {}
    for name in TECHNIQUE_DIRS:
        path = os.path.join("techniques", name)
        if os.path.isdir(path):
            try:
                out[name] = load_manifest(path)
            except Exception as exc:  # keep going; a broken manifest shouldn't kill the run
                print(f"[figure_csv] WARNING: could not load manifest {name}: {exc}")
    return out


def compares_for(manifest, fig_id):
    """Return the ``compares`` list for a manifest figure id, or ``[]`` if absent."""
    for fig in manifest.figures:
        if fig.get("id") == fig_id:
            return list(fig.get("compares", []))
    return []


def _cores(manifest, core_setup_name):
    cs = manifest.core_setups.get(core_setup_name)
    return cs.cores if cs is not None else None


def best_family_config(sp, manifest, core_setup, base_config, family_fig="threshold_sweep"):
    """Config with the highest GMean speedup among the bus-util-threshold family at this core
    setup. The paper reports the best-performing threshold config for Terracotta-
    ChargeCacheMASA (four-core = t040); the plain `terracotta_chargecachemasa` (no threshold) is
    NOT the reported bar. Falls back to base_config when no family figure exists or has no data
    here (e.g. single-core, where the family is four-core only)."""
    family = compares_for(manifest, family_fig)
    if not family:
        return base_config
    tsp = sp[(sp["technique"] == manifest.technique) & (sp["core_setup"] == core_setup)]
    best, best_g = base_config, None
    for cfg in family:
        vals = tsp[tsp["config"] == cfg]["speedup"].tolist()
        if not vals:
            continue
        g = derive.gmean(vals)
        if not derive._isnan(g) and (best_g is None or g > best_g):
            best, best_g = cfg, g
    return best


def relabel_best_family(sp, manifest, series_config, core_setup="four_core"):
    """Replace `series_config`'s rows at `core_setup` with the best threshold-family member's
    (relabeled as series_config), so a figure's Terracotta-ChargeCacheMASA series plots the best
    bus-util-threshold config (paper does; four-core t040). No-op when the best IS series_config
    or there is no family (single-core). Other techniques/series/setups are untouched."""
    best = best_family_config(sp, manifest, core_setup, series_config)
    if best == series_config:
        return sp
    mask = ((sp["technique"] == manifest.technique) & (sp["core_setup"] == core_setup))
    keep = sp[~(mask & (sp["config"] == series_config))].copy()
    repl = sp[mask & (sp["config"] == best)].copy()
    repl["config"] = series_config
    return pd.concat([keep, repl], ignore_index=True)


# --------------------------------------------------------------------------- #
# Shared row assembly for grouped-bar (bucketed) speedup figures
# --------------------------------------------------------------------------- #

def _bucketed_rows(sp, manifest, panels, series_map):
    """Assemble grouped-bar rows for a bucketed speedup figure.

    ``sp``: full ``speedup_over_baseline`` frame. ``panels``: ordered list of
    ``(panel_label, core_setup_name, mode)`` with ``mode`` in ``{"buckets","gmean_only"}``.
    ``series_map``: ordered ``{config: display_name}``; series order follows dict order.
    """
    tech_sp = sp[sp["technique"] == manifest.technique]
    rows = []
    for p_order, (panel_label, core_setup_name, mode) in enumerate(panels):
        cores = _cores(manifest, core_setup_name)
        if cores is None:
            continue
        bmap = derive.workload_buckets(manifest, core_setup_name)
        for s_order, (config, disp) in enumerate(series_map.items()):
            cfg = tech_sp[(tech_sp["core_setup"] == core_setup_name)
                          & (tech_sp["config"] == config)]
            if cfg.empty:
                continue
            agg = derive.aggregate_buckets(
                cfg[["workload", "speedup"]].rename(columns={"speedup": "value"}),
                bmap, cores, mode=mode)
            for a in agg:
                rows.append({"panel": panel_label, "panel_order": p_order,
                             "x": a["x"], "x_order": a["x_order"],
                             "series": disp, "series_order": s_order,
                             "value": a["value"], "err": a["err"]})
    return rows


# --------------------------------------------------------------------------- #
# Per-figure builders. Signature build(tidy, manifests) -> list[row dict].
# --------------------------------------------------------------------------- #

def build_figure9(tidy, m):
    """Fig 9 (paper): PRADA PuM per-operation speedup over baseline, 1 bank + 32 banks.

    Speedup is the execution-CYCLE ratio (derive.pum_speedup), NOT an IPC ratio -- PuM is not
    IPC-comparable to the CPU baseline. Panels 1bank (single_core_1b) / 32bank (single_core);
    x = PuM operation + "Average" (GMean over ops); series = the main_pum compares minus
    baseline (custom -> PRADA, terracotta -> Terracotta-PRADA).
    """
    mani = m.get("prada")
    if mani is None:
        return []
    sp = derive.pum_speedup(tidy)
    sp = sp[sp["technique"] == mani.technique]
    compares = [c for c in compares_for(mani, "main_pum") if c != "baseline"]
    disp = {"custom": "PRADA", "terracotta": "Terracotta-PRADA",
            "terracotta_cgra": "Terracotta-CGRA"}
    series_map = {c: disp.get(c, derive.DISPLAY_NAMES.get(c, c)) for c in compares}
    ops = list(mani.pum.get("operations", []))
    op_order = {op: i for i, op in enumerate(ops)}
    panels = [("1bank", "single_core_1b"), ("32bank", "single_core")]
    rows = []
    for p_order, (panel_label, core_setup_name) in enumerate(panels):
        if core_setup_name not in mani.core_setups:
            continue
        for s_order, (config, dname) in enumerate(series_map.items()):
            cfg = sp[(sp["core_setup"] == core_setup_name) & (sp["config"] == config)]
            if cfg.empty:
                continue
            for _, r in cfg.iterrows():
                op = r["workload"]
                rows.append({"panel": panel_label, "panel_order": p_order,
                             "x": op, "x_order": op_order.get(op, 99),
                             "series": dname, "series_order": s_order,
                             "value": r["speedup"], "err": ""})
            vals = [v for v in cfg["speedup"].tolist() if not derive._isnan(v)]
            if vals:
                # Paper's Fig 9 "Average" column is the ARITHMETIC mean of the per-op
                # speedups (e.g. 32-bank Terracotta-PRADA = 148.31), not a geomean.
                rows.append({"panel": panel_label, "panel_order": p_order,
                             "x": "Average", "x_order": len(ops),
                             "series": dname, "series_order": s_order,
                             "value": sum(vals) / len(vals), "err": ""})
    return rows


def build_figure10(tidy, m):
    """Fig 10 (assumption): MoPAC-C mitigation. manifest id ``main_mitigation``.

    Series split by nRH for the swept configs (custom, terracotta); PRAC is a single series.
    Four-core values are normalized performance (<1 = slowdown over no-mitigation). x = L/H
    (single) or LLLL..HHHH (four), plus GMean.
    """
    mani = m.get("mopac")
    if mani is None:
        return []
    sp = derive.normalize_to_baseline(derive.speedup_over_baseline(tidy))
    tech_sp = sp[sp["technique"] == mani.technique]
    compares = [c for c in compares_for(mani, "main_mitigation") if c != "baseline"]
    disp_base = {"custom": "MoPAC", "terracotta": "Terracotta", "prac": "PRAC"}
    nrh_points = list(mani.sweeps.get("nRH", {}).get("points", []))
    nrh_str = {str(p) for p in nrh_points}
    panels = [("single", "single_core", "buckets"), ("four", "four_core", "buckets")]
    rows = []
    s_order = 0
    for config in compares:
        disp = disp_base.get(config, derive.DISPLAY_NAMES.get(config, config))
        cfg_all = tech_sp[tech_sp["config"] == config]
        if cfg_all.empty:
            continue
        # Split by nRH point encoded in exp_name suffix (e.g. "_250" or "_250_2"); configs
        # with no nRH sweep (prac) collapse to a single series.
        def nrh_of(row):
            suf = derive.point_suffix(row["exp_name"], row["config"], row["workload"])
            for tok in suf.strip("_").split("_"):
                if tok in nrh_str:
                    return tok
            return None
        cfg_all = cfg_all.copy()
        cfg_all["nrh"] = cfg_all.apply(nrh_of, axis=1)
        groups = ([(n, cfg_all[cfg_all["nrh"] == n]) for n in sorted(nrh_str, key=int)]
                  if cfg_all["nrh"].notna().any()
                  else [(None, cfg_all)])
        for nrh, grp in groups:
            if grp.empty:
                continue
            series_label = f"{disp}-{nrh}" if nrh is not None else disp
            for p_order, (panel_label, core_setup_name, mode) in enumerate(panels):
                cores = _cores(mani, core_setup_name)
                if cores is None:
                    continue
                sub = grp[grp["core_setup"] == core_setup_name]
                if sub.empty:
                    continue
                bmap = derive.workload_buckets(mani, core_setup_name)
                agg = derive.aggregate_buckets(
                    sub[["workload", "speedup"]].rename(columns={"speedup": "value"}),
                    bmap, cores, mode=mode)
                for a in agg:
                    rows.append({"panel": panel_label, "panel_order": p_order,
                                 "x": a["x"], "x_order": a["x_order"],
                                 "series": series_label, "series_order": s_order,
                                 "value": a["value"], "err": a["err"]})
            s_order += 1
    return rows


def build_figure11(tidy, m):
    """Fig 11 (assumption): MASA speedup. manifest id ``main_speedup``."""
    mani = m.get("masa")
    if mani is None:
        return []
    sp = derive.normalize_to_baseline(derive.speedup_over_baseline(tidy))
    series_map = {"custom": "MASA", "terracotta": "Terracotta-MASA", "oracle": "Ideal"}
    panels = [("single", "single_core", "buckets"), ("four", "four_core", "buckets")]
    return _bucketed_rows(sp, mani, panels, series_map)


def build_figure12(tidy, m):
    """Fig 12 (assumption): ChargeCache speedup. manifest id ``main_speedup``.

    oracle -> "Low-Latency DRAM" (per-figure override). NOTE (MEMORY.md): the oracle
    single-core re-run (controller latency 9->8) is still pending; this series will shift
    once regenerated, but the pipeline is unaffected.
    """
    mani = m.get("chargecache")
    if mani is None:
        return []
    sp = derive.normalize_to_baseline(derive.speedup_over_baseline(tidy))
    series_map = {"custom": "ChargeCache", "terracotta": "Terracotta-ChargeCache",
                  "oracle": "Low-Latency DRAM"}
    panels = [("single", "single_core", "buckets"), ("four", "four_core", "buckets")]
    return _bucketed_rows(sp, mani, panels, series_map)


def build_figure13(tidy, m):
    """Fig 13 (assumption): DRAM energy overhead % of Terracotta over the custom controller.

    Cross-technique derived (no manifest id). One panel per technique; x = core-setup label;
    single series "Terracotta". overhead % = GMean(total_energy ratio) - 1, in %.
    """
    # (dir, panel_label, panel_order, num_config, den_config, {core_setup: x_label})
    specs = [
        ("prada", "PRADA", 0, "terracotta", "custom",
         {"single_core_1b": "1bank", "single_core": "32bank"}),
        ("mopac", "MoPAC-C", 1, "terracotta", "custom",
         {"single_core": "single", "four_core": "four"}),
        ("masa", "MASA", 2, "terracotta", "custom",
         {"single_core": "single", "four_core": "four"}),
        ("chargecache", "ChargeCache", 3, "terracotta", "custom",
         {"single_core": "single", "four_core": "four"}),
    ]
    rows = []
    for dir_name, panel, p_order, num, den, x_labels in specs:
        mani = m.get(dir_name)
        if mani is None:
            continue
        tech_tidy = tidy[tidy["technique"] == mani.technique]
        ov = derive.energy_overhead_pct(tech_tidy, num=num, den=den)
        for x_order, (core_setup_name, x_label) in enumerate(x_labels.items()):
            sub = ov[ov["core_setup"] == core_setup_name]
            if sub.empty:
                continue
            e = sub["err"].iloc[0]
            e = float(e) if isinstance(e, (int, float)) and not derive._isnan(e) else ""
            rows.append({"panel": panel, "panel_order": p_order,
                         "x": x_label, "x_order": x_order,
                         "series": "Terracotta", "series_order": 0,
                         "value": float(sub["overhead_pct"].iloc[0]), "err": e})
    return rows


def build_figure14(tidy, m):
    """Fig 14: Terracotta performance sensitivity to controller-latency overhead.

    Matches the paper's chart19-22 (verified): PRADA is single-core PuM speedup (GMean over
    operations); MoPAC-C / MASA / ChargeCache are the FOUR-CORE weighted speedup normalized to
    baseline (GMean over mixes; MoPAC at nRH=250). x = latency-overhead point: point 2 is the
    MAIN terracotta config (already run for the other figures -- reused, not re-run); 4/6/8/10
    come from the isolated four-core ``terracotta_latency`` sweep variant.
    """
    # (dir, panel, order, core_setup, is_pum)
    specs = [("prada", "PRADA", 0, "single_core", True),
             ("mopac", "MoPAC-C", 1, "four_core", False),
             ("masa", "MASA", 2, "four_core", False),
             ("chargecache", "ChargeCache", 3, "four_core", False)]
    MOPAC_NRH = "250"   # MoPAC's latency line is at the primary RowHammer threshold
    rows = []
    for dir_name, panel, p_order, cs_name, is_pum in specs:
        mani = m.get(dir_name)
        if mani is None:
            continue
        sp = (derive.pum_speedup(tidy) if is_pum
              else derive.normalize_to_baseline(derive.speedup_over_baseline(tidy)))
        tech = sp[(sp["technique"] == mani.technique) & (sp["core_setup"] == cs_name)]

        def toks_of(row):
            suf = derive.point_suffix(row["exp_name"], row["config"], row["workload"])
            return [t for t in suf.strip("_").split("_") if t.isdigit()]

        pts = {}  # latency overhead (int) -> per-workload/-mix speedups
        # Overhead 2 = the MAIN terracotta config (reused, not re-run). MoPAC: nRH=250 only.
        for _, r in tech[tech["config"] == "terracotta"].iterrows():
            t = toks_of(r)
            if not t or t[-1] != "2":
                continue
            if dir_name == "mopac" and (len(t) < 2 or t[0] != MOPAC_NRH):
                continue
            pts.setdefault(2, []).append(r["speedup"])
        # Overheads 4/6/8/10 = the isolated four-core terracotta_latency sweep variant.
        for _, r in tech[tech["config"] == "terracotta_latency"].iterrows():
            t = toks_of(r)
            if t:
                pts.setdefault(int(t[-1]), []).append(r["speedup"])

        for x_order, lat in enumerate(sorted(pts)):
            v = derive.gmean(pts[lat])   # GMean for all panels (incl. PRADA, per chart20)
            if derive._isnan(v):
                continue
            rows.append({"panel": panel, "panel_order": p_order,
                         "x": str(lat), "x_order": x_order,
                         "series": "Terracotta", "series_order": 0,
                         "value": v, "err": ""})
    return rows


def build_figure15(tidy, m):
    """Fig 15 (assumption): ChargeCacheMASA composition. manifest id ``main_speedup``.

    Single-core: L/H + GMean; four-core: GMean only.
    """
    mani = m.get("chargecachemasa")
    if mani is None:
        return []
    sp = derive.normalize_to_baseline(derive.speedup_over_baseline(tidy))
    # Terracotta-ChargeCacheMASA reports the best bus-util-threshold config (four-core t040),
    # not the plain no-threshold variant -- matching the paper.
    sp = relabel_best_family(sp, mani, "terracotta_chargecachemasa")
    series_map = {
        "chargecache": "ChargeCache", "terracotta_chargecache": "Terracotta-ChargeCache",
        "masa": "MASA", "terracotta_masa": "Terracotta-MASA",
        "chargecachemasa": "ChargeCacheMASA",
        "terracotta_chargecachemasa": "Terracotta-ChargeCacheMASA",
    }
    panels = [("single", "single_core", "buckets"), ("four", "four_core", "gmean_only")]
    return _bucketed_rows(sp, mani, panels, series_map)


def build_figure16(tidy, m):
    """Fig 16 (paper §8.7, confirmed): Terracotta-CGRA vs Terracotta-Tables vs custom.

    manifest id ``figure16`` (the only number-bound figure). One panel per technique;
    configs come from each manifest's ``figure16`` compares (so ChargeCacheMASA's differently
    named configs are handled automatically). Series display: custom-form -> "Custom",
    Tables form -> "Terracotta-Tables", CGRA form -> "Terracotta-CGRA".
    """
    def series_map_of(mani):
        c = compares_for(mani, "figure16")  # [custom-form, tables-form, cgra-form]
        if len(c) < 3:
            return None
        return {c[0]: "Custom", c[1]: "Terracotta-Tables", c[2]: "Terracotta-CGRA"}

    rows = []

    # PRADA panel: PuM cycle-ratio speedup (derive.pum_speedup), GMean over ops. ONE panel with
    # two clusters -- 1 Bank + 32 Banks -- matching the paper's single PRADA panel (req #9).
    psp = derive.pum_speedup(tidy)
    mani = m.get("prada")
    if mani is not None:
        series_map = series_map_of(mani)
        if series_map is not None:
            for x_label, x_ord, core_setup_name in [("1 Bank", 0, "single_core_1b"),
                                                    ("32 Banks", 1, "single_core")]:
                if core_setup_name not in mani.core_setups:
                    continue
                tech = psp[(psp["technique"] == mani.technique)
                           & (psp["core_setup"] == core_setup_name)]
                for s_order, (config, disp) in enumerate(series_map.items()):
                    cfg = tech[tech["config"] == config]
                    if cfg.empty:
                        continue
                    g = derive.gmean(cfg["speedup"].tolist())
                    if derive._isnan(g):
                        continue
                    # Fig 16 carries NO error bars (user decision) -> err left empty.
                    rows.append({"panel": "PRADA", "panel_order": 0,
                                 "x": x_label, "x_order": x_ord,
                                 "series": disp, "series_order": s_order,
                                 "value": g, "err": ""})

    # CPU-technique panels (four-core): weighted speedup normalized to baseline, GMean-only
    # bar per series (matching the paper's single 4-core bar per technique).
    sp = derive.normalize_to_baseline(derive.speedup_over_baseline(tidy))
    # Terracotta-ChargeCacheMASA (Tables) reports the best threshold config (four-core t040).
    ccm = m.get("chargecachemasa")
    if ccm is not None:
        sp = relabel_best_family(sp, ccm, "terracotta_chargecachemasa")
    for dir_name, panel, p_order, core_setup_name in [
            ("masa", "MASA", 1, "four_core"),
            ("chargecache", "ChargeCache", 2, "four_core"),
            ("chargecachemasa", "ChargeCacheMASA", 3, "four_core")]:
        mani = m.get(dir_name)
        if mani is None or core_setup_name not in mani.core_setups:
            continue
        series_map = series_map_of(mani)
        if series_map is None:
            continue
        cores = _cores(mani, core_setup_name)
        bmap = derive.workload_buckets(mani, core_setup_name)
        tech_sp = sp[(sp["technique"] == mani.technique)
                     & (sp["core_setup"] == core_setup_name)]
        for s_order, (config, disp) in enumerate(series_map.items()):
            cfg = tech_sp[tech_sp["config"] == config]
            if cfg.empty:
                continue
            agg = derive.aggregate_buckets(
                cfg[["workload", "speedup"]].rename(columns={"speedup": "value"}),
                bmap, cores, mode="gmean_only")
            for a in agg:
                rows.append({"panel": panel, "panel_order": p_order,
                             "x": a["x"], "x_order": a["x_order"],
                             "series": disp, "series_order": s_order,
                             "value": a["value"], "err": a["err"]})
    return rows


BUILDERS = {
    9: build_figure9, 10: build_figure10, 11: build_figure11, 12: build_figure12,
    13: build_figure13, 14: build_figure14, 15: build_figure15, 16: build_figure16,
}


# --------------------------------------------------------------------------- #
# Output + CLI
# --------------------------------------------------------------------------- #

def write_figure_csv(fig_id, rows, out_dir=OUT_DIR):
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"figure{fig_id}.csv")
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIG_HEADER)
        w.writeheader()
        w.writerows(rows)
    print(f"[figure_csv] figure{fig_id}.csv: {len(rows)} rows -> {path}")
    return path


def main():
    ap = argparse.ArgumentParser(description="Build per-figure CSVs from the tidy CSV.")
    ap.add_argument("--tidy", default=DEFAULT_TIDY)
    ap.add_argument("--out-dir", default=OUT_DIR)
    ap.add_argument("--figures", default="all", help='"all" or e.g. "11,12,16"')
    args = ap.parse_args()

    if not os.path.exists(args.tidy):
        print(f"[figure_csv] ERROR: tidy CSV not found: {args.tidy}", file=sys.stderr)
        return 1
    tidy = pd.read_csv(args.tidy)
    manifests = load_manifests()

    if args.figures == "all":
        ids = sorted(BUILDERS)
    else:
        ids = [int(x) for x in args.figures.split(",") if x.strip()]

    for fid in ids:
        builder = BUILDERS.get(fid)
        if builder is None:
            print(f"[figure_csv] WARNING: no builder for figure {fid}, skipping")
            continue
        try:
            rows = builder(tidy, manifests)
        except Exception as exc:
            print(f"[figure_csv] WARNING: figure{fid} builder failed: {exc}")
            rows = []
        write_figure_csv(fid, rows, args.out_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
