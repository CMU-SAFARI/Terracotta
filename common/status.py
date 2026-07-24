"""Simulation status tracking.

Classifies each experiment of a technique/core-setup as DONE / RUNNING / ERROR / MISSING
by inspecting its stat and error files, writes the four lists under a status dir, and
prints a summary. Replaces the per-technique ``common/status.py`` + ``run_status.py``.
"""

import argparse
import os
import sys

from common.config_gen import plan
from common.manifest import load_manifest

# A finished run always emits the MemorySystem summary block; its ``memory_system_cycles``
# key marks completion. We deliberately do NOT key on per-controller counters like
# ``num_read_reqs_``: MoPAC's BHDRAMController (MoPACDRAMController) never emits those, so
# keying on them would leave every completed MoPAC run stuck reporting as RUNNING forever.
# This matches the finished-run signal used by ``common/parse.py`` so status and parsing agree.
DONE_TOKEN = "memory_system_cycles"


def get_status(stat_filename, error_filename):
    """Return DONE / ERROR / RUNNING / MISSING for one experiment."""
    if not os.path.exists(stat_filename) or not os.path.exists(error_filename):
        return "MISSING"

    with open(error_filename, "r") as f:
        if len(f.readlines()) > 0:
            return "ERROR"

    with open(stat_filename, "r") as f:
        for line in f:
            if DONE_TOKEN in line:
                return "DONE"

    return "RUNNING"


def report(manifest, core_setup_name, result_dir, status_dir):
    """Classify every experiment and write running/error/done/missing lists."""
    buckets = {"RUNNING": [], "ERROR": [], "DONE": [], "MISSING": []}
    for exp, paths in plan(manifest, core_setup_name, result_dir):
        buckets[get_status(paths["stat"], paths["error"])].append(exp.name)

    print(f"Running: {len(buckets['RUNNING'])}, Error: {len(buckets['ERROR'])}, "
          f"Done: {len(buckets['DONE'])}, Missing: {len(buckets['MISSING'])}")

    os.makedirs(status_dir, exist_ok=True)
    for status, fname in (("RUNNING", "running.txt"), ("ERROR", "error.txt"),
                          ("DONE", "done.txt"), ("MISSING", "missing.txt")):
        with open(os.path.join(status_dir, fname), "w") as f:
            for name in buckets[status]:
                f.write(f"{name}\n")

    if buckets["RUNNING"] or buckets["MISSING"]:
        print(f"Experiments still pending; see {os.path.join(status_dir, 'running.txt')} "
              f"and {os.path.join(status_dir, 'missing.txt')}.")
    if buckets["ERROR"]:
        print(f"Experiments with errors; see {os.path.join(status_dir, 'error.txt')}.")
    return buckets


def main():
    parser = argparse.ArgumentParser(description="Report simulation status for a technique.")
    parser.add_argument("-t", "--technique", required=True, help="techniques/<dir>")
    parser.add_argument("-c", "--core-setup", required=True)
    parser.add_argument("-rd", "--result-dir", required=True)
    parser.add_argument("-sd", "--status-dir", required=True)
    args = parser.parse_args()

    manifest = load_manifest(args.technique)
    buckets = report(manifest, args.core_setup, args.result_dir, args.status_dir)
    # Non-zero exit if anything is not DONE, so callers can gate on completion.
    incomplete = sum(len(v) for k, v in buckets.items() if k != "DONE")
    return 1 if incomplete else 0


if __name__ == "__main__":
    sys.exit(main())
