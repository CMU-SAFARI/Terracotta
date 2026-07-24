#!/usr/bin/env bash
#
# build.sh -- Build the Terracotta artifact image and save it to a tar for
# shipping to SLURM compute nodes (podman save -> load-per-job; no registry).
# Idempotent (image-layer cache makes a no-op rebuild fast; the save is skipped
# when the tar is already up-to-date) and CWD-independent. Podman only.
#
set -euo pipefail
cd "$(dirname "$0")"

RUNTIME="${RUNTIME:-podman}"
IMAGE_TAG="terracotta:latest"
IMAGE_TAR="terracotta_artifact.tar"

command -v "$RUNTIME" >/dev/null 2>&1 || {
  echo "[build] ERROR: '$RUNTIME' not found on PATH." >&2; exit 1; }

echo "[build] runtime=$RUNTIME  image=$IMAGE_TAG"
echo "[build] $RUNTIME build -t $IMAGE_TAG -f Dockerfile ."
"$RUNTIME" build -t "$IMAGE_TAG" -f Dockerfile .

# Decide whether the tar needs (re)writing. Compare the image's creation time to
# the tar's mtime: re-save only if the image is newer than the tar, the tar is
# missing, or either timestamp can't be resolved. A no-op rebuild leaves the
# image's cached .Created untouched, so the existing tar stays valid and the
# multi-hundred-MB export is skipped.
save_needed=1
if [ -f "$IMAGE_TAR" ]; then
  # Use the epoch form directly: podman emits a Go time string for
  # '{{.Created}}' that GNU `date -d` cannot parse (which would silently force a
  # re-save every build). '{{.Created.Unix}}' gives a plain integer.
  image_epoch="$("$RUNTIME" image inspect -f '{{.Created.Unix}}' "$IMAGE_TAG" 2>/dev/null || echo "")"
  tar_epoch="$(stat -c %Y "$IMAGE_TAR" 2>/dev/null || echo "")"
  if [ -n "$image_epoch" ] && [ -n "$tar_epoch" ] && [ "$tar_epoch" -ge "$image_epoch" ]; then
    save_needed=0
  fi
fi

if [ "$save_needed" -eq 0 ]; then
  echo "[build] $IMAGE_TAR is up-to-date with $IMAGE_TAG; skipping save."
else
  echo "[build] $RUNTIME save -o $IMAGE_TAR $IMAGE_TAG"
  # The archive format cannot modify an existing tar, so remove any stale tar
  # before re-exporting.
  rm -f "$IMAGE_TAR"
  "$RUNTIME" save -o "$IMAGE_TAR" "$IMAGE_TAG"
fi

echo "[build] DONE"
echo "[build]   image : $IMAGE_TAG (in local $RUNTIME store)"
echo "[build]   tar   : $(pwd)/$IMAGE_TAR  (ship to compute nodes / shared FS)"
