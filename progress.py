#!/usr/bin/env python3
"""Aggregate progress viewer for the Terracotta experiment sweep.

Read-only: for every technique x core-setup it classifies each experiment
(DONE / RUNNING / ERROR / MISSING) from the results tree and prints a per-set
table plus a grand-total line with a percent-complete bar. Writes nothing.

Usage:
    python3 progress.py                 # snapshot over ./results
    python3 progress.py --result-dir DIR
Prefer ``./check_progress.sh`` (adds an optional --watch loop).
"""
import argparse
import os
import sys

REPO_ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, REPO_ROOT)

from common.config_gen import plan
from common.manifest import load_manifest
from common.status import get_status

ALL_TECHNIQUES = ["chargecache", "masa", "mopac", "chargecachemasa", "prada"]
ORDER = ["DONE", "RUNNING", "MISSING", "ERROR"]


def tally_set(manifest, core_setup, set_rd):
    counts = {"DONE": 0, "RUNNING": 0, "ERROR": 0, "MISSING": 0}
    for _exp, paths in plan(manifest, core_setup, set_rd):
        counts[get_status(paths["stat"], paths["error"])] += 1
    return counts


def bar(frac, width=32):
    filled = int(round(frac * width))
    return "[" + "#" * filled + "." * (width - filled) + "]"


def main():
    ap = argparse.ArgumentParser(description="Terracotta sweep progress viewer.")
    ap.add_argument("--result-dir", default=os.path.join(REPO_ROOT, "results"))
    args = ap.parse_args()
    result_root = os.path.abspath(args.result_dir)

    total = {"DONE": 0, "RUNNING": 0, "ERROR": 0, "MISSING": 0}
    rows = []
    for technique in ALL_TECHNIQUES:
        tdir = os.path.join(REPO_ROOT, "techniques", technique)
        if not os.path.isdir(tdir):
            continue
        manifest = load_manifest(tdir)
        for cs in manifest.core_setups:
            set_rd = os.path.join(result_root, technique, cs)
            c = tally_set(manifest, cs, set_rd)
            for k in total:
                total[k] += c[k]
            rows.append((f"{technique}/{cs}", c))

    label_w = max((len(r[0]) for r in rows), default=20)
    hdr = f"{'technique/core-setup':<{label_w}}  {'done':>6} {'run':>6} {'pend':>6} {'err':>6} {'total':>7}"
    print(hdr)
    print("-" * len(hdr))
    for label, c in rows:
        t = sum(c.values())
        print(f"{label:<{label_w}}  {c['DONE']:>6} {c['RUNNING']:>6} "
              f"{c['MISSING']:>6} {c['ERROR']:>6} {t:>7}")
    print("-" * len(hdr))

    grand = sum(total.values())
    done = total["DONE"]
    frac = (done / grand) if grand else 0.0
    print(f"{'TOTAL':<{label_w}}  {done:>6} {total['RUNNING']:>6} "
          f"{total['MISSING']:>6} {total['ERROR']:>6} {grand:>7}")
    print(f"\n{bar(frac)} {100 * frac:5.1f}%   "
          f"done {done}/{grand} | running {total['RUNNING']} | "
          f"pending {total['MISSING']} | error {total['ERROR']}")
    if total["ERROR"]:
        print(f"[warn] {total['ERROR']} experiment(s) errored — "
              f"see results/<technique>/<core-setup>/status/error.txt "
              f"(run ./check_run_status.sh <technique> to refresh).")


if __name__ == "__main__":
    main()
