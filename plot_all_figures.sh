#!/usr/bin/env bash
# Render every results figure from its results/csv/figureN.csv (produced by ./parse_results.sh).
# LOCAL plot entry point for the conda env (needs matplotlib 3.9.2 + pandas; see requirements.txt).
# CWD-independent: always runs from the repo root so results/csv and figures/
# resolve. A figure whose CSV is absent or header-only is skipped (not a crash) by figureN.py.
set -euo pipefail
cd "$(dirname "$0")"

for n in 9 10 11 12 13 14 15 16; do
  python3 "plotting_scripts/figure${n}.py"
done

echo "figures written to $PWD/figures/"
