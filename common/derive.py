"""Derived-metric + bucketing helpers for figure-CSV construction.

Pure functions over the tidy long-form table (``common.parse`` schema
``[technique, core_setup, exp_name, config, workload, core, metric, value]``). No stat is
recomputed in Ramulator2 terms here: IPC / speedup / energy-overhead are *derived* from the
raw per-core stats, because no such stat exists in the dumps. Only stat keys confirmed
present in real dumps are referenced:

* ``insts_recorded_core`` / ``cycles_recorded_core`` (per-core, from ``*_core_<n>``)
* ``total_energy`` (global, ``core == -1``)

Everything is unit-testable without a simulation run.
"""

import math
import os

from common.manifest import load_manifest, parse_mix

# Stat keys (post ``split_index``) this module depends on. Named once so the dependency is
# explicit and greppable; nothing else is hardcoded.
INSTS_METRIC = "insts_recorded_core"
CYCLES_METRIC = "cycles_recorded_core"
ENERGY_METRIC = "total_energy"

# Fixed bucket orders. Single-core mixes are labelled L/H directly in the .mix ``type``
# column; four-core mixes are canonicalized by H-count.
SINGLE_BUCKETS = ["L", "H"]
FOUR_BUCKETS = ["LLLL", "HLLL", "HHLL", "HHHL", "HHHH"]
GMEAN_LABEL = "GMean"

# Default variant(config) -> paper display label. Figure builders pass a per-figure sub-map
# for family-specific overrides (e.g. oracle -> "Low-Latency DRAM" in the ChargeCache fig);
# unknown names fall through unchanged.
DISPLAY_NAMES = {
    "baseline": "Baseline",
    "custom": "Custom",
    "terracotta": "Terracotta-Tables",
    "terracotta_cgra": "Terracotta-CGRA",
    "oracle": "Ideal",
    "prac": "PRAC",
}


# --------------------------------------------------------------------------- #
# Scalar helpers
# --------------------------------------------------------------------------- #

def gmean(values):
    """Geometric mean over the strictly-positive, non-NaN values; NaN if none qualify."""
    vals = [v for v in values if v is not None and not _isnan(v) and v > 0]
    if not vals:
        return float("nan")
    return math.exp(sum(math.log(v) for v in vals) / len(vals))


def _isnan(v):
    try:
        return math.isnan(v)
    except TypeError:
        return False


def stderr(values):
    """Sample standard error of the mean = stdev(values, sample) / sqrt(n); "" if n < 2.

    This is what the paper's figure error bars encode (verified against the PPT chart data,
    e.g. Fig 11 MASA single-core Terracotta L-bar = 0.0068 = sample_std 0.0366 / sqrt(29), and
    H-bar 0.0188). NOT the population/sample std-dev itself -- the bars are the standard error.
    Returns "" (not 0) for < 2 points so the plotter draws no cap.
    """
    vals = [v for v in values if v is not None and not _isnan(v)]
    n = len(vals)
    if n < 2:
        return ""
    mean = sum(vals) / n
    var = sum((v - mean) ** 2 for v in vals) / (n - 1)  # sample variance
    return math.sqrt(var) / math.sqrt(n)


def bucket(mix_type, cores):
    """single-core: return the L/H type as-is. four-core: canonicalize by H-count.

    ``mix_type`` is the raw ``.mix`` ``type`` column value (e.g. ``L``, ``H``, ``HHLL``).
    """
    if cores == 1:
        return mix_type
    n_h = mix_type.upper().count("H")
    return {0: "LLLL", 1: "HLLL", 2: "HHLL", 3: "HHHL", 4: "HHHH"}[n_h]


def point_suffix(exp_name, config, workload):
    """Recover the sweep/nRH/latency/threshold suffix, e.g. ``_2``, ``_250``, ``_250_2``.

    Mirrors ``latency.group_by_variant_sweep``: strip the ``<config>_<workload>`` prefix
    from the experiment stem. Returns ``""`` when there is no suffix.
    """
    prefix = f"{config}_{workload}"
    return exp_name[len(prefix):] if exp_name.startswith(prefix) else ""


# --------------------------------------------------------------------------- #
# Mix / bucket maps (small I/O: reads the core setup's .mix once)
# --------------------------------------------------------------------------- #

def workload_buckets(manifest, core_setup_name):
    """``{workload_name: bucket_label}`` from the core setup's ``.mix`` ``type`` column."""
    cs = manifest.core_setups[core_setup_name]
    mix = os.path.join(manifest.path, cs.mix)
    return {e.name: bucket(e.type, cs.cores) for e in parse_mix(mix)}


# --------------------------------------------------------------------------- #
# Derived-metric frames (pandas)
# --------------------------------------------------------------------------- #

def ipc(tidy):
    """Per-experiment per-core IPC = insts_recorded_core / cycles_recorded_core.

    Returns a frame ``[technique, core_setup, exp_name, config, workload, core, ipc]``.
    """
    keys = ["technique", "core_setup", "exp_name", "config", "workload", "core"]
    insts = (tidy[tidy["metric"] == INSTS_METRIC][keys + ["value"]]
             .rename(columns={"value": "insts"}))
    cycles = (tidy[tidy["metric"] == CYCLES_METRIC][keys + ["value"]]
              .rename(columns={"value": "cycles"}))
    merged = insts.merge(cycles, on=keys, how="inner")
    merged = merged[merged["cycles"] > 0].copy()
    merged["ipc"] = merged["insts"] / merged["cycles"]
    return merged[keys + ["ipc"]]


def _single_core_setups(manifest):
    return [n for n, cs in manifest.core_setups.items() if cs.cores == 1]


def _manifests_by_name():
    """{paper technique name -> manifest} for every technique dir present on disk."""
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    tdir = os.path.join(repo, "techniques")
    out = {}
    if os.path.isdir(tdir):
        for d in sorted(os.listdir(tdir)):
            mp = os.path.join(tdir, d)
            if os.path.isfile(os.path.join(mp, "manifest.yaml")):
                try:
                    m = load_manifest(mp)
                    out[m.technique] = m
                except Exception:
                    pass
    return out


def speedup_over_baseline(tidy, baseline="baseline"):
    """Per-experiment performance metric, per (technique, core setup).

    Single-core (cores == 1): speedup over baseline = ``IPC(variant, wl, 0) / IPC(baseline, wl, 0)``
    (baseline == 1.0 by construction).

    Multi-core (cores > 1): CLASSIC WEIGHTED SPEEDUP over the *alone* IPC (verified against the
    original ``run_colation.py``: ``weighted_speedup = sum_c shared_ipc_c / alone_ipc_c``), where
    ``alone_ipc(trace)`` is the *baseline* single-core IPC of that trace (same technique) and each
    mix's per-core trace comes from its ``.mix`` entry. This is an ABSOLUTE weighted speedup
    (baseline is NOT 1.0); a figure that normalizes to the baseline's weighted speedup is a
    plotting choice, confirmed per-figure against the paper.

    Returns ``[technique, core_setup, config, workload, exp_name, speedup]``.
    """
    import pandas as pd

    ip = ipc(tidy)
    rows = []
    for tech, m in _manifests_by_name().items():
        tip = ip[ip["technique"] == tech]
        if tip.empty:
            continue
        singles = _single_core_setups(m)
        # alone IPC per trace = baseline single-core IPC at core 0 (this technique).
        base_single = tip[(tip["core_setup"].isin(singles))
                          & (tip["config"] == baseline) & (tip["core"] == 0)]
        alone = dict(zip(base_single["workload"], base_single["ipc"]))

        for cs_name, cs in m.core_setups.items():
            sub = tip[tip["core_setup"] == cs_name]
            if sub.empty:
                continue
            if cs.cores == 1:
                base_cs = sub[(sub["config"] == baseline) & (sub["core"] == 0)]
                bmap = dict(zip(base_cs["workload"], base_cs["ipc"]))
                for (cfg, wl, exp), g in (sub[sub["core"] == 0]
                                          .groupby(["config", "workload", "exp_name"])):
                    b = bmap.get(wl)
                    if b and b > 0:
                        rows.append({"technique": tech, "core_setup": cs_name, "config": cfg,
                                     "workload": wl, "exp_name": exp,
                                     "speedup": g["ipc"].iloc[0] / b})
            else:
                mix_traces = {e.name: e.traces
                              for e in parse_mix(os.path.join(m.path, cs.mix))}
                for (cfg, wl, exp), g in sub.groupby(["config", "workload", "exp_name"]):
                    traces = mix_traces.get(wl)
                    if not traces:
                        continue
                    per_core = dict(zip(g["core"], g["ipc"]))
                    ws, ok = 0.0, True
                    for c, tr in enumerate(traces):
                        a, s = alone.get(tr), per_core.get(c)
                        if a and a > 0 and s is not None:
                            ws += s / a
                        else:
                            ok = False
                            break
                    if ok:
                        rows.append({"technique": tech, "core_setup": cs_name, "config": cfg,
                                     "workload": wl, "exp_name": exp, "speedup": ws})
    return pd.DataFrame(
        rows, columns=["technique", "core_setup", "config", "workload", "exp_name", "speedup"])


def pum_speedup(tidy, baseline="baseline"):
    """PRADA PuM per-operation speedup = execution-CYCLE ratio, NOT an IPC ratio.

    PuM runs are not IPC-comparable: the baseline runs each operation on the CPU (via loads/
    stores, millions of instructions) while a PuM variant runs it in-DRAM (a handful of trigger
    ops), so ``speedup_over_baseline``'s IPC ratio is meaningless here (and PuMO3 emits
    ``insts_retired_core``, not ``insts_recorded_core``, so it yields nothing anyway). The Fig 9
    / Fig 16-PRADA speedup the paper reports is baseline execution cycles / variant execution
    cycles, per operation, using ``cycles_recorded_core`` at core 0. Baseline and every variant
    share the same ``workload`` (the operation name), so they match per (core_setup, workload).
    Verified against the paper's chart data (e.g. 32-bank COPY: custom 315x, terracotta 319x).

    Returns ``[technique, core_setup, config, workload, exp_name, speedup]``.
    """
    import pandas as pd

    cyc = tidy[(tidy["metric"] == CYCLES_METRIC) & (tidy["core"] == 0)]
    cyc = cyc[["technique", "core_setup", "config", "workload", "exp_name", "value"]]
    rows = []
    for (tech, cs), grp in cyc.groupby(["technique", "core_setup"]):
        base = grp[grp["config"] == baseline]
        bmap = dict(zip(base["workload"], base["value"]))
        for _, r in grp.iterrows():
            b = bmap.get(r["workload"])
            v = r["value"]
            if b and v and v > 0:
                rows.append({"technique": tech, "core_setup": cs, "config": r["config"],
                             "workload": r["workload"], "exp_name": r["exp_name"],
                             "speedup": b / v})
    return pd.DataFrame(
        rows, columns=["technique", "core_setup", "config", "workload", "exp_name", "speedup"])


def normalize_to_baseline(sp, baseline="baseline"):
    """Normalize each config's per-(technique, core_setup, workload) speedup to the baseline
    config's speedup for that same workload, so the baseline == 1.0 by construction.

    Single-core speedup is already IPC/IPC_baseline (baseline == 1.0), so this is a no-op there.
    Four-core speedup from ``speedup_over_baseline`` is an ABSOLUTE weighted speedup (the
    baseline's own WS is ~3.0 under contention), so this divides it by the baseline's per-mix WS
    to yield the paper's "weighted speedup normalized to baseline" presentation (~1.0). Verified:
    Fig10 four-core PRAC 2.858 / baseline WS 3.058 = 0.9346 == paper.

    Returns a frame with the same columns as ``sp`` (baseline rows become 1.0).
    """
    import pandas as pd

    if sp.empty:
        return sp
    # One baseline speedup per (technique, core_setup, workload). Dedup (keep last) so a stray
    # duplicate baseline row can't fan out the left-merge and inflate downstream means -- this
    # matches the "last wins" dict(zip(...)) semantics used in pum_speedup / speedup_over_baseline.
    base = (sp[sp["config"] == baseline][["technique", "core_setup", "workload", "speedup"]]
            .drop_duplicates(["technique", "core_setup", "workload"], keep="last")
            .rename(columns={"speedup": "_bws"}))
    merged = sp.merge(base, on=["technique", "core_setup", "workload"], how="left")
    merged = merged[merged["_bws"].notna() & (merged["_bws"] > 0)].copy()
    merged["speedup"] = merged["speedup"] / merged["_bws"]
    return merged.drop(columns=["_bws"])


def energy_overhead_pct(tidy, num, den):
    """DRAM energy overhead % of config ``num`` over config ``den``, per (technique, setup).

    Uses the global ``total_energy`` (``core == -1``), matches num/den by
    (technique, core_setup, workload), then reports
    ``100 * (GMean_wl(total_energy[num]/total_energy[den]) - 1)``.

    Returns ``[technique, core_setup, ratio_gmean, overhead_pct]``.
    """
    import pandas as pd

    te = tidy[(tidy["metric"] == ENERGY_METRIC) & (tidy["core"] == -1)]
    te = te[["technique", "core_setup", "config", "workload", "value"]]
    numf = (te[te["config"] == num]
            .groupby(["technique", "core_setup", "workload"], as_index=False)["value"]
            .mean().rename(columns={"value": "num"}))
    denf = (te[te["config"] == den]
            .groupby(["technique", "core_setup", "workload"], as_index=False)["value"]
            .mean().rename(columns={"value": "den"}))
    merged = numf.merge(denf, on=["technique", "core_setup", "workload"], how="inner")
    merged = merged[merged["den"] > 0].copy()
    if merged.empty:
        return pd.DataFrame(
            columns=["technique", "core_setup", "ratio_gmean", "overhead_pct", "err"])
    merged["ratio"] = merged["num"] / merged["den"]
    out = []
    for (tech, cs), grp in merged.groupby(["technique", "core_setup"]):
        ratios = grp["ratio"].tolist()
        g = gmean(ratios)
        overheads = [100.0 * (r - 1.0) for r in ratios]  # per-workload overhead %
        out.append({"technique": tech, "core_setup": cs,
                    "ratio_gmean": g, "overhead_pct": 100.0 * (g - 1.0),
                    "err": stderr(overheads)})
    return pd.DataFrame(out)


# --------------------------------------------------------------------------- #
# Bucket aggregation for grouped-bar figures
# --------------------------------------------------------------------------- #

def aggregate_buckets(df, bucket_map, cores, mode="buckets"):
    """Aggregate per-workload values into bucket bars + a GMean bar.

    ``df``: a frame with columns ``workload`` and ``value``. ``bucket_map``: workload->bucket
    label. ``mode``: ``"buckets"`` emits one arithmetic-mean bar per non-empty bucket (in
    fixed order) followed by a GMean bar (geomean over all workloads); ``"gmean_only"`` emits
    just the GMean bar.

    Returns an ordered list of ``{"x", "x_order", "value", "err"}`` dicts.
    """
    order = SINGLE_BUCKETS if cores == 1 else FOUR_BUCKETS
    work = df.copy()
    work["bucket"] = work["workload"].map(bucket_map)
    rows = []
    if mode == "buckets":
        for i, b in enumerate(order):
            vals = work[work["bucket"] == b]["value"].tolist()
            if not vals:
                continue
            # Per-bucket bar: arithmetic mean +/- standard error over its workloads (the
            # paper puts error bars on these bucket bars).
            rows.append({"x": b, "x_order": i,
                         "value": sum(vals) / len(vals), "err": stderr(vals)})
        gmean_order = len(order)
        gmean_err = ""  # policy: error bars go on per-bucket bars, never on GMean bars
    else:
        # gmean_only: the bar IS a GMean summary -> no error bar (same policy).
        gmean_order = 0
        gmean_err = ""
    g = gmean(work["value"].tolist())
    if not _isnan(g):
        rows.append({"x": GMEAN_LABEL, "x_order": gmean_order, "value": g, "err": gmean_err})
    return rows
