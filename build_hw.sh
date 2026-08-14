#!/usr/bin/env bash
#
# build_hw.sh -- Build the Terracotta RTL/synthesis image (OpenROAD-
# Flow-Scripts compiled from the pinned commit + the Terracotta designs) and save
# it to a tar for shipping to SLURM compute nodes (podman load-per-job; no
# registry).
#
# Podman only. Builds the native image from the shared Dockerfile and saves it to
# a tar for shipping to SLURM compute nodes.
#
# Idempotent (image-layer cache makes a no-op rebuild fast; the save is skipped
# when the tar is already up-to-date) and CWD-independent.
#
set -euo pipefail
cd "$(dirname "$0")/RTL"   # wrapper lives at repo root; the build context is RTL/

RUNTIME="${RUNTIME:-podman}"
THREADS="${THREADS:-$(nproc)}"
IMAGE_TAG="terracotta-openroad:latest"
IMAGE_TAR="terracotta-openroad_${RUNTIME}.tar"

command -v "$RUNTIME" >/dev/null 2>&1 || {
  echo "[build-rtl] ERROR: '$RUNTIME' not found on PATH." >&2; exit 1; }

# The image bakes in the pinned ORFS *sources* (COPY OpenROAD-flow-scripts), so
# the submodule must be populated recursively before building.
if [ ! -f OpenROAD-flow-scripts/build_openroad.sh ] \
   || [ ! -d OpenROAD-flow-scripts/tools/yosys-slang ] \
   || [ -z "$(ls -A OpenROAD-flow-scripts/tools/yosys-slang 2>/dev/null)" ]; then
  echo "[build-rtl] ERROR: OpenROAD-flow-scripts submodule is not fully populated." >&2
  echo "[build-rtl] Run this from the repository root first:" >&2
  echo "[build-rtl]     git submodule update --init --recursive RTL/OpenROAD-flow-scripts" >&2
  exit 1
fi

echo "[build-rtl] runtime=$RUNTIME  threads=$THREADS  image=$IMAGE_TAG"
echo "[build-rtl] compiling OpenROAD + yosys + yosys-slang from the pinned commit"
echo "[build-rtl] (first build takes ~20-40 min; cached rebuilds are fast)"
echo "[build-rtl] $RUNTIME build -t $IMAGE_TAG --build-arg THREADS=$THREADS -f Dockerfile ."
"$RUNTIME" build -t "$IMAGE_TAG" --build-arg THREADS="$THREADS" -f Dockerfile .

# Re-save the tar only if the image is newer than the tar (or the tar is missing).
save_needed=1
if [ -f "$IMAGE_TAR" ]; then
  image_epoch="$("$RUNTIME" image inspect -f '{{.Created.Unix}}' "$IMAGE_TAG" 2>/dev/null || echo "")"
  tar_epoch="$(stat -c %Y "$IMAGE_TAR" 2>/dev/null || echo "")"
  if [ -n "$image_epoch" ] && [ -n "$tar_epoch" ] && [ "$tar_epoch" -ge "$image_epoch" ]; then
    save_needed=0
  fi
fi

if [ "$save_needed" -eq 0 ]; then
  echo "[build-rtl] $IMAGE_TAR is up-to-date with $IMAGE_TAG; skipping save."
else
  echo "[build-rtl] $RUNTIME save -o $IMAGE_TAR $IMAGE_TAG"
  rm -f "$IMAGE_TAR"
  "$RUNTIME" save -o "$IMAGE_TAR" "$IMAGE_TAG"
fi

echo "[build-rtl] DONE"
echo "[build-rtl]   image : $IMAGE_TAG (in local $RUNTIME store)"
echo "[build-rtl]   tar   : $(pwd)/$IMAGE_TAR"
