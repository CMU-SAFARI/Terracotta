#!/usr/bin/env bash
#
# parse_results.sh -- Terracotta parse pipeline (the PARSE half of R4).
#
# Drives the shared Python parser over the raw results tree and emits the (regenerable,
# uncommitted) CSVs:
#   1. results/csv/tidy/<technique>_<core_setup>.csv  -- per-(technique,setup) tidy long form
#   2. results/csv/tidy.csv                           -- concatenation of the above
#   3. results/csv/figureN.csv                        -- plot-ready, normalized/aggregated
#
# Raw layout consumed: results/<technique>/<core_setup>/stats/<exp>.txt (config_gen layout).
# CWD-independent: cd's to the script's own directory so it can be invoked from anywhere.
# Fails loudly (set -euo pipefail); skips technique/core-setup pairs whose stats/ is absent
# and skips unfinished/missing individual dumps inside common.parse (a full sweep may still
# be running).

set -euo pipefail
cd "$(dirname "$0")"

echo "[parse_results] repo root: $PWD"
mkdir -p results/csv/tidy

# (technique_dir : core_setup) pairs to collate. Extend as more results land.
PAIRS="chargecache:single_core chargecache:four_core \
       masa:single_core masa:four_core \
       mopac:single_core mopac:four_core \
       chargecachemasa:single_core chargecachemasa:four_core \
       prada:single_core prada:single_core_1b"

collated=0
for pair in $PAIRS; do
  t="${pair%%:*}"
  c="${pair##*:}"
  rd="results/${t}/${c}"
  if [ ! -d "$rd/stats" ]; then
    echo "[parse_results] skip ${t}/${c}: no ${rd}/stats yet"
    continue
  fi
  echo "[parse_results] collating ${t}/${c} ..."
  python3 -m common.parse \
      -t "techniques/${t}" \
      -c "$c" \
      -rd "$rd" \
      -o "results/csv/tidy/${t}_${c}.csv"
  collated=$((collated + 1))
done

if [ "$collated" -eq 0 ]; then
  echo "[parse_results] ERROR: no results found under results/<technique>/<core_setup>/stats" >&2
  exit 1
fi

# Concatenate the per-(technique,setup) tidy files into one tidy.csv (header written once).
echo "[parse_results] concatenating ${collated} tidy file(s) -> results/csv/tidy.csv"
python3 - <<'PY'
import glob
import pandas as pd

files = sorted(glob.glob("results/csv/tidy/*.csv"))
frames = [pd.read_csv(f) for f in files]
frames = [df for df in frames if not df.empty]
if not frames:
    raise SystemExit("[parse_results] ERROR: every tidy file is empty (no finished dumps)")
combined = pd.concat(frames, ignore_index=True)
combined.to_csv("results/csv/tidy.csv", index=False)
print(f"[parse_results] tidy.csv: {len(combined)} rows from {len(files)} file(s)")
PY

# Build every per-figure CSV from the concatenated tidy CSV.
echo "[parse_results] building per-figure CSVs ..."
python3 -m common.figure_csv --tidy results/csv/tidy.csv --out-dir results/csv --figures all

# Terracotta-vs-custom 99th-percentile latency comparison (per-technique tail latency + a
# proposed paper sentence). Reads the latency/ dumps directly; non-fatal, since those dumps may
# be absent while a sweep is still in flight.
echo "[parse_results] building latency comparison ..."
python3 -m common.latency_comparison -o results/txt/latency_comparison.txt \
  || echo "[parse_results] WARNING: latency comparison skipped (no latency dumps yet)"

echo "[parse_results] done. CSVs under results/csv/, text reports under results/txt/"
