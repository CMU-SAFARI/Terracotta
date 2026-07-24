#!/usr/bin/env bash
#
# Regenerate all PRADA Processing-using-Memory (PuM) microbenchmark traces.
#
# Produces the 8 trace files the PRADA case study consumes (see
# techniques/prada/mixes/single.mix and single_1b.mix):
#   32-bank case (all banks, 32 MB set):  base_1ip_32M base_2ip_32M pum_1ip_32M pum_2ip_32M
#   1-bank case  (single bank, 1 MB set): base_1ip_1M  base_2ip_1M  pum_1ip_1M_1b pum_2ip_1M_1b
#
# Usage: ./generate_pum_traces.sh [OUTPUT_DIR]   (default: current directory)
set -euo pipefail

OUT="${1:-.}"
cd "$(dirname "$0")"
mkdir -p "$OUT"

gen() { python3 trace_generator.py "$@"; }

echo "[*] generating 32-bank PuM traces (set size 32 MB) into $OUT"
gen --trace-type base_1ip --set-size 32 --banks full   --trace-file "$OUT/base_1ip_32M"
gen --trace-type base_2ip --set-size 32 --banks full   --trace-file "$OUT/base_2ip_32M"
gen --trace-type pum_1ip  --set-size 32 --banks full   --trace-file "$OUT/pum_1ip_32M"
gen --trace-type pum_2ip  --set-size 32 --banks full   --trace-file "$OUT/pum_2ip_32M"

echo "[*] generating 1-bank PuM traces (set size 1 MB) into $OUT"
gen --trace-type base_1ip --set-size 1  --banks single --trace-file "$OUT/base_1ip_1M"
gen --trace-type base_2ip --set-size 1  --banks single --trace-file "$OUT/base_2ip_1M"
gen --trace-type pum_1ip  --set-size 1  --banks single --trace-file "$OUT/pum_1ip_1M_1b"
gen --trace-type pum_2ip  --set-size 1  --banks single --trace-file "$OUT/pum_2ip_1M_1b"

echo "[*] done: 8 PuM traces written to $OUT"
