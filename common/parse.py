"""Shared raw Ramulator2 stats parser + tidy long-form emitter.

The Ramulator2 stat dump format is identical across all techniques (indented
``key: value`` lines, e.g. ``row_hits_0``, ``avg_read_latency_0``, ``total_energy``),
so raw parsing is technique-independent and lives here once. Per-figure selection and
aggregation (normalization, GMean, speedup) is a figure concern handled downstream.

``collate`` walks a technique/core-setup's stat dumps and emits a tidy long-form table
``[technique, core_setup, exp_name, config, workload, core, metric, value]`` where
``config`` is the bare variant name, ``core`` is the trailing stat index (-1 for a global
metric; for per-controller metrics the channel index, for ``*_core_<n>`` metrics the core
index), and ``exp_name`` is the full experiment stem. ``exp_name`` un-collapses the
sweep/nRH/latency/threshold suffix that ``config``/``workload`` discard (e.g.
``terracotta_401.bzip2_2`` -> config ``terracotta``, workload ``401.bzip2``, but the sweep
point ``_2`` survives only in ``exp_name``); those suffixes are the x-axes of the latency /
nRH / threshold figures. The original 6-column schema ``[technique, config, workload, core,
metric, value]`` remains a strict subset.

An unfinished run (a stat dump with only frontend heartbeats and no ``MemorySystem`` block,
i.e. the simulation was still running or was killed) carries no ``memory_system_cycles`` key.
Such dumps are reported in the unfinished-warning list and their rows are dropped -- never
emitted as zeros -- so the pipeline still produces CSVs from the finished subset while a
full sweep is in flight.
"""

import argparse
import csv
import os
import re
import sys

from common.config_gen import plan
from common.manifest import load_manifest

_INDEX_RE = re.compile(r"^(.*?)_(\d+)$")


def _to_number(text):
    text = text.strip()
    if text == ".nan":
        return float("nan")
    try:
        return int(text)
    except ValueError:
        pass
    try:
        return float(text)
    except ValueError:
        return None


def parse_stat_file(path):
    """Parse a stat dump into ``{stat_key: number}`` for every numeric line."""
    stats = {}
    with open(path, "r") as f:
        for line in f:
            line = line.split("#", 1)[0].rstrip()
            if ":" not in line:
                continue
            key, _, value = line.partition(":")
            key = key.strip()
            if not key or " " in key:
                continue
            number = _to_number(value)
            if number is not None:
                stats[key] = number
    return stats


def split_index(stat_key):
    """Split ``row_hits_0`` -> (``row_hits``, 0); a global key -> (key, -1)."""
    m = _INDEX_RE.match(stat_key)
    if m:
        return m.group(1), int(m.group(2))
    return stat_key, -1


def long_form_rows(technique, core_setup, exp_name, config, workload, stats):
    """Yield ``(technique, core_setup, exp_name, config, workload, core, metric, value)``."""
    for key, value in stats.items():
        metric, index = split_index(key)
        yield (technique, core_setup, exp_name, config, workload, index, metric, value)


TIDY_HEADER = [
    "technique", "core_setup", "exp_name",
    "config", "workload", "core", "metric", "value",
]

# A finished simulation always emits the MemorySystem block; its presence is detected by
# this global key. A heartbeat-only dump (still running / killed) lacks it. This is the one
# completeness signal every SimpleO3/BHO3/PuMO3 dump shares, confirmed present in real
# finished dumps -- no other stat key is assumed.
_FINISHED_KEY = "memory_system_cycles"


def is_finished(stats):
    """True iff the dump carries MemorySystem stats (heartbeat-only dump => unfinished)."""
    return _FINISHED_KEY in stats


def collate(manifest, core_setup_name, result_dir, out_csv):
    """Parse every finished stat dump for a technique/core-setup into one long-form CSV.

    Missing dumps (experiment not run) and unfinished dumps (no DONE/MemorySystem block) are
    skipped and reported; the CSV is written from whatever finished dumps exist.
    """
    rows = []
    missing = []
    unfinished = []
    for exp, paths in plan(manifest, core_setup_name, result_dir):
        if not os.path.exists(paths["stat"]):
            missing.append(exp.name)
            continue
        stats = parse_stat_file(paths["stat"])
        if not is_finished(stats):
            unfinished.append(exp.name)
            continue
        rows.extend(long_form_rows(
            manifest.technique, core_setup_name, exp.name,
            exp.variant, exp.workload, stats,
        ))

    os.makedirs(os.path.dirname(os.path.abspath(out_csv)), exist_ok=True)
    with open(out_csv, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(TIDY_HEADER)
        writer.writerows(rows)

    print(f"[parse] {manifest.technique}/{core_setup_name}: {len(rows)} rows -> {out_csv}")
    if missing:
        print(f"[parse] WARNING: {len(missing)} stat files missing (e.g. {missing[:3]})")
    if unfinished:
        print(f"[parse] WARNING: {len(unfinished)} unfinished dumps skipped "
              f"(e.g. {unfinished[:3]})")
    return rows


def main():
    parser = argparse.ArgumentParser(description="Collate raw stats into long-form CSV.")
    parser.add_argument("-t", "--technique", required=True, help="techniques/<dir>")
    parser.add_argument("-c", "--core-setup", required=True)
    parser.add_argument("-rd", "--result-dir", required=True)
    parser.add_argument("-o", "--out-csv", required=True)
    args = parser.parse_args()

    manifest = load_manifest(args.technique)
    collate(manifest, args.core_setup, args.result_dir, args.out_csv)
    return 0


if __name__ == "__main__":
    sys.exit(main())
