#!/usr/bin/env bash
#
# run_hardware_complexity.sh -- shared DRIVER for the RTL hardware-complexity run
# (analogous to the simulator's run.py). Prefer the friendly wrappers:
#   build_hw.sh                     build the image (once)
#   run_hw_with_personalcomputer.sh your machine, podman container
#   run_hw_with_slurm.sh            SLURM, podman container
#
# CONTAINER-ONLY: everything runs inside the container -- synthesis, metric
# extraction, and compute_overhead.py (the overhead figures). The only
# requirement is a container runtime + the pre-built image;
# there is no bare-metal path. Build is SEPARATE (build_hw.sh); this driver never
# builds and fails loudly if the image is absent.
#
#   --runtime {podman|docker}         container runtime                        [podman]
#   --slurm                           submit to SLURM (run the container on a compute node)
#   --batch {all|custom|terracotta}   which designs                            [all]
#   --partition NAME                  SLURM partition for --slurm              [cpu_part]
#   --result-dir DIR                  where CSVs + the report are written      [./results]
#
set -euo pipefail
cd "$(dirname "$0")"
SELF="$PWD/$(basename "$0")"

RUNTIME="${RUNTIME:-podman}"
USE_SLURM=0
BATCH="${BATCH:-all}"
IMAGE_TAG="terracotta-openroad:latest"
OUT_DIR="$PWD/results"
SLURM_PARTITION="${SLURM_PARTITION:-cpu_part}"

while [ $# -gt 0 ]; do
  case "$1" in
    --runtime)   RUNTIME="$2"; shift 2;;
    --slurm)     USE_SLURM=1;  shift;;
    --batch)     BATCH="$2";   shift 2;;
    --partition) SLURM_PARTITION="$2"; shift 2;;
    --result-dir) OUT_DIR="$2"; shift 2;;
    -h|--help) sed -n '2,/^set -euo/p' "$SELF" | sed 's/^# \{0,1\}//; s/^set -euo.*//'; exit 0;;
    *) echo "[hw] unknown arg: $1" >&2; exit 2;;
  esac
done
case "$RUNTIME" in podman|docker) ;; *) echo "[hw] bad --runtime: $RUNTIME (podman or docker)" >&2; exit 2;; esac
case "$BATCH"   in all|custom|terracotta) ;; *) echo "[hw] bad --batch: $BATCH" >&2; exit 2;; esac
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"   # absolute — needed for the container -v mount and sbatch --output

# Everything below runs INSIDE the container: synthesize the requested designs,
# copy the summary CSVs to $OUT, then reproduce the paper's overhead figures.
BATCH_CMDS='
set -e
if [ "$BATCH" = all ] || [ "$BATCH" = custom ]; then ./run_synthesis.sh; fi
if [ "$BATCH" = all ] || [ "$BATCH" = terracotta ]; then ./run_terracotta_synthesis.sh; fi
cp -f ./*.csv "$OUT" 2>/dev/null || true
if [ "$BATCH" = all ] \
   && [ -f "$OUT/synthesis_results.csv" ] \
   && [ -f "$OUT/terracotta_synthesis_results.csv" ]; then
  echo "[hw] reproducing paper overhead figures (compute_overhead.py):"
  RESULTS_DIR="$OUT" python3 /work/RTL/compute_overhead.py || true
fi
'

# Container runtime requires the pre-built image (build is a separate step).
ensure_image() {
  local rt="$1"
  "$rt" image inspect "$IMAGE_TAG" >/dev/null 2>&1 && return 0
  local tar="terracotta-openroad_${rt}.tar"
  [ -f "$tar" ] || tar="$(ls terracotta-openroad_*.tar 2>/dev/null | head -1 || true)"
  if [ -n "${tar:-}" ] && [ -f "$tar" ]; then
    echo "[hw] loading image from $tar"; "$rt" load -i "$tar"; return 0
  fi
  echo "[hw] ERROR: image '$IMAGE_TAG' not found (no image, no tar)." >&2
  echo "[hw]        Build it first (from the repo root):  RUNTIME=$rt ./build_hw.sh" >&2
  exit 1
}

# Run the synthesis batch inside the container (podman). The toolchain and
# designs are baked into the image; the live run scripts + compute_overhead.py are
# mounted over the baked copies so edits take effect without a rebuild.
run_in_container() {
  command -v "$RUNTIME" >/dev/null 2>&1 || { echo "[hw] ERROR: $RUNTIME not found." >&2; exit 1; }
  ensure_image "$RUNTIME"
  "$RUNTIME" run --rm \
    -v "$PWD/run_synthesis.sh":/work/RTL/run_synthesis.sh:ro \
    -v "$PWD/run_terracotta_synthesis.sh":/work/RTL/run_terracotta_synthesis.sh:ro \
    -v "$PWD/compute_overhead.py":/work/RTL/compute_overhead.py:ro \
    -v "$OUT_DIR":/work/RTL/_out \
    -e BATCH="$BATCH" -e OUT="/work/RTL/_out" \
    "$IMAGE_TAG" bash -lc '
      source /work/RTL/OpenROAD-flow-scripts/env.sh >/dev/null 2>&1
      cd /work/RTL
      '"$BATCH_CMDS"'
    '
}

# ── SLURM: submit the container run to a compute node, wait, show the log ──
if [ "$USE_SLURM" = 1 ]; then
  command -v sbatch >/dev/null 2>&1 || { echo "[hw] ERROR: sbatch not found." >&2; exit 1; }
  SB="$OUT_DIR/hw_${RUNTIME}.sbatch"
  cat > "$SB" <<EOF
#!/bin/bash
#SBATCH --job-name=tc_hw_${RUNTIME}
#SBATCH --partition=${SLURM_PARTITION}
#SBATCH --time=02:00:00
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --output=${OUT_DIR}/hw_${RUNTIME}_slurm.log
set -e
echo "[job] node=\$(hostname) runtime=${RUNTIME}"
# rootless podman needs /etc/subuid ranges; docker (rootful daemon) does not.
[ "${RUNTIME}" != podman ] || [ "\$(podman unshare cat /proc/self/uid_map 2>/dev/null | wc -l)" -ge 2 ] \\
  || { echo "[job] ERROR: no subuid ranges on \$(hostname)."; exit 3; }
RUNTIME=${RUNTIME} bash "${SELF}" --runtime ${RUNTIME} --batch ${BATCH}
EOF
  echo "[hw] SLURM submit: runtime=$RUNTIME partition=$SLURM_PARTITION (waiting for completion)"
  sbatch --wait "$SB"
  echo "[hw] SLURM job finished; log tail:"
  tail -25 "${OUT_DIR}/hw_${RUNTIME}_slurm.log" 2>/dev/null | sed 's/^/  /'
  exit 0
fi

# ── Run the container on the current machine ──
echo "[hw] runtime=$RUNTIME  batch=$BATCH  -> $OUT_DIR"
run_in_container

echo "[hw] DONE. CSVs in $OUT_DIR:"
ls -1 "$OUT_DIR"/*.csv 2>/dev/null | sed 's/^/  /' || echo "  (none produced)"
