"""Shared request-latency CDF + percentile analysis.

Consolidates the old per-technique latency scripts (chargecache/masa/mopac/prada each
shipped a near-identical ``parse_latency.py``; chargecache also had ``report_latency.py``)
into one manifest-driven module. Every real per-technique difference the old scripts encoded
by hand -- the variant->filename-prefix map, the results subdir, MoPAC's nRH-sweep splitting
-- is already carried by the manifest (variant names, core setups, sweeps) and materialized by
:func:`common.config_gen.plan`, so grouping keys off the enumerated experiments directly.
That also removes the old ``startswith`` prefix hack, which under the new variant names would
wrongly fold ``terracotta_cgra_*`` into ``terracotta_*``: here grouping is by the exact
``experiment.variant`` (optionally plus sweep/workload), never a string prefix.

Input: when a simulation runs, Ramulator2 appends ``.core<N>`` to ``Frontend.lat_dump_path``
(which config_gen sets to ``<result_dir>/latency/<experiment_name>``) and writes a bucketed
latency histogram there -- one ``bucket, count`` line per bucket. This module aggregates those
histograms per group, drops sub-``CACHE_HIT_THRESHOLD`` buckets (LLC hits, not DRAM latency),
and builds a CDF; percentiles are linearly interpolated on the CDF.
"""

import argparse
import bisect
import csv
import glob
import os
import sys
from collections import defaultdict

from common.config_gen import plan
from common.manifest import load_manifest

# Latency (in memory cycles) at/below which a request is an LLC hit, not a DRAM access.
# Uniform across all five old parse_latency.py / report_latency.py scripts.
CACHE_HIT_THRESHOLD = 45


# --------------------------------------------------------------------------- #
# Grouping: which experiments' dumps are aggregated into one CDF.
# --------------------------------------------------------------------------- #

def group_by_variant(exp):
    """One CDF per variant, aggregated over all workloads (old default for CC/MASA/PRADA)."""
    return exp.variant


def group_by_variant_workload(exp):
    """One CDF per (variant, workload) -- e.g. PRADA per PuM operation."""
    return f"{exp.variant}::{exp.workload}"


def group_by_variant_sweep(exp):
    """One CDF per (variant, sweep/latency point), aggregated over workloads -- e.g. MoPAC
    per nRH. Derives the point suffix from the experiment name (name minus the
    ``<variant>_<workload>`` prefix), so custom_mix1_250 -> 'custom_250'."""
    remainder = exp.name[len(exp.variant) + 1:]  # "<workload>[_<sweep>][_<lat>]"
    if remainder.startswith(exp.workload):
        remainder = remainder[len(exp.workload):]  # "[_<sweep>][_<lat>]"
    return f"{exp.variant}{remainder}"


GROUPERS = {
    "variant": group_by_variant,
    "variant_workload": group_by_variant_workload,
    "variant_sweep": group_by_variant_sweep,
}


# --------------------------------------------------------------------------- #
# Histogram / CDF / percentiles
# --------------------------------------------------------------------------- #

def parse_histogram(path):
    """Parse one ``bucket, count`` latency histogram into {latency: count}."""
    hist = defaultdict(int)
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            if len(parts) < 2:
                continue
            hist[int(parts[0].strip())] += int(parts[1].strip())
    return hist


def collect(manifest, core_setup_name, result_dir, group_fn=group_by_variant):
    """Aggregate every experiment's per-core latency dumps into {group: {latency: count}}.

    Reads ``<result_dir>/latency/<experiment_name>.core*`` for each enumerated experiment.
    Missing dumps (experiment not yet run) are skipped and reported.
    """
    groups = defaultdict(lambda: defaultdict(int))
    seen, missing = 0, 0
    for exp, paths in plan(manifest, core_setup_name, result_dir):
        dumps = sorted(glob.glob(paths["latency"] + ".core*"))
        if not dumps:
            missing += 1
            continue
        seen += 1
        g = group_fn(exp)
        for dump in dumps:
            for lat, count in parse_histogram(dump).items():
                groups[g][lat] += count
    return groups, seen, missing


def to_cdf(hist, cache_hit_threshold=CACHE_HIT_THRESHOLD):
    """Build a CDF from a {latency: count} histogram, dropping LLC-hit buckets.

    Returns (latencies, cdf) as parallel sorted lists; cdf is cumulative fraction of DRAM
    requests with latency <= that bucket. Returns ([], []) if there are no DRAM requests.
    """
    items = sorted((lat, c) for lat, c in hist.items() if lat > cache_hit_threshold)
    total = sum(c for _, c in items)
    if total == 0:
        return [], []
    lats, cdf, cum = [], [], 0
    for lat, c in items:
        cum += c
        lats.append(lat)
        cdf.append(cum / total)
    return lats, cdf


def percentile(lats, cdf, p):
    """Latency at the p-th percentile (p in [0,100]) via linear interpolation on the CDF."""
    if not lats:
        return float("nan")
    target = p / 100.0
    i = bisect.bisect_left(cdf, target)
    if i == 0:
        return float(lats[0])
    if i >= len(cdf):
        return float(lats[-1])
    lo_c, hi_c = cdf[i - 1], cdf[i]
    lo_l, hi_l = lats[i - 1], lats[i]
    if hi_c == lo_c:
        return float(hi_l)
    return lo_l + (hi_l - lo_l) * (target - lo_c) / (hi_c - lo_c)


# --------------------------------------------------------------------------- #
# Outputs
# --------------------------------------------------------------------------- #

def write_cdfs(groups, out_dir, cache_hit_threshold=CACHE_HIT_THRESHOLD):
    """Write one ``<group>.csv`` (header latency,cdf) per group. Returns count written."""
    os.makedirs(out_dir, exist_ok=True)
    n = 0
    for group, hist in sorted(groups.items()):
        lats, cdf = to_cdf(hist, cache_hit_threshold)
        if not lats:
            continue
        safe = group.replace("::", "__").replace("/", "_")
        with open(os.path.join(out_dir, f"{safe}.csv"), "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["latency", "cdf"])
            for lat, frac in zip(lats, cdf):
                w.writerow([lat, f"{frac:.10f}"])
        n += 1
    return n


def percentile_table(groups, ps=(90, 95, 99), cache_hit_threshold=CACHE_HIT_THRESHOLD):
    """Return {group: {p: latency}} for the requested percentiles."""
    table = {}
    for group, hist in groups.items():
        lats, cdf = to_cdf(hist, cache_hit_threshold)
        table[group] = {p: percentile(lats, cdf, p) for p in ps}
    return table


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #

def main():
    parser = argparse.ArgumentParser(description="Latency CDF + percentile analysis.")
    parser.add_argument("-t", "--technique", required=True, help="techniques/<dir>")
    parser.add_argument("-c", "--core-setup", required=True)
    parser.add_argument("-rd", "--result-dir", required=True)
    parser.add_argument("-o", "--out-dir", required=True, help="dir for per-group CDF CSVs")
    parser.add_argument("--group-by", choices=sorted(GROUPERS), default="variant")
    parser.add_argument("--threshold", type=int, default=CACHE_HIT_THRESHOLD)
    parser.add_argument("--percentiles", default="90,95,99")
    args = parser.parse_args()

    manifest = load_manifest(args.technique)
    groups, seen, missing = collect(
        manifest, args.core_setup, args.result_dir, GROUPERS[args.group_by])
    n = write_cdfs(groups, args.out_dir, args.threshold)
    print(f"[latency] {manifest.technique}/{args.core_setup}: {seen} experiments, "
          f"{n} CDFs -> {args.out_dir}" + (f" ({missing} missing dumps)" if missing else ""))

    ps = [int(x) for x in args.percentiles.split(",") if x.strip()]
    table = percentile_table(groups, ps, args.threshold)
    for group in sorted(table):
        cells = "  ".join(f"P{p}={table[group][p]:.1f}" for p in ps)
        print(f"  {group:40s} {cells}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
