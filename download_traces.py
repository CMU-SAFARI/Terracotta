#!/usr/bin/env python3
"""Download the Terracotta workload traces into ./traces.

Fetches the trace archive from Zenodo, verifies its sha256, and extracts it into the
repository's ``traces/`` directory (gitignored). The archive is self-contained: it holds
every CPU and Processing-using-Memory (PuM) trace the experiments read, so a single download
is all an evaluator needs before running.

The PuM traces are shipped ready-made for convenience; they can also be regenerated exactly
with ``techniques/prada/trace/generate_pum_traces.sh`` (documented in the appendix).

Usage:
    python3 download_traces.py            # download + verify + extract into ./traces
    python3 download_traces.py --force    # re-download even if ./traces already exists
    python3 download_traces.py --keep-archive
"""

import argparse
import hashlib
import os
import sys
import tarfile
import urllib.request

# Zenodo deposit of the trace archive: standalone traces record (concept DOI
# 10.5281/zenodo.21541650), served from version record 21541651. TRACES_SHA256 is the sha256 of
# terracotta_traces.tar.gz (57 CPU + 8 PuM traces); Zenodo lists the matching md5 a9a5...7125e.
TRACES_URL = "https://zenodo.org/records/21541651/files/terracotta_traces.tar.gz?download=1"
TRACES_SHA256 = "7c9f0b33e686cb453995ed106c10c4e12234fc44221c52ef18ca803b982b0edf"
ARCHIVE_NAME = "terracotta_traces.tar.gz"

REPO_ROOT = os.path.dirname(os.path.abspath(__file__))
TRACE_DIR = os.path.join(REPO_ROOT, "traces")


def _sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _progress(block_num, block_size, total_size):
    if total_size <= 0:
        return
    done = min(block_num * block_size, total_size)
    sys.stdout.write(f"\r  {ARCHIVE_NAME}: {100.0 * done / total_size:5.1f}% "
                     f"({done >> 20} / {total_size >> 20} MiB)")
    sys.stdout.flush()
    if done >= total_size:
        sys.stdout.write("\n")


def download(dest):
    if not TRACES_URL:
        sys.exit(
            "[error] TRACES_URL is not set yet -- the trace archive has not been published.\n"
            "        Set TRACES_URL at the top of download_traces.py once the Zenodo record\n"
            "        exists (see CLAUDE.md).")
    print(f"[*] downloading traces from {TRACES_URL}")
    try:
        urllib.request.urlretrieve(TRACES_URL, dest, reporthook=_progress)
    except Exception as exc:  # report any network/URL failure plainly
        sys.exit(f"[error] download failed: {exc}")

    print("[*] verifying archive checksum ...")
    actual = _sha256(dest)
    if actual != TRACES_SHA256:
        os.remove(dest)
        sys.exit(f"[error] checksum mismatch for {ARCHIVE_NAME}\n"
                 f"        expected {TRACES_SHA256}\n        got      {actual}")
    print("    checksum OK")


def extract(archive):
    print(f"[*] extracting {ARCHIVE_NAME} into {REPO_ROOT}")
    base = os.path.abspath(REPO_ROOT)
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():  # guard against path traversal
            target = os.path.abspath(os.path.join(REPO_ROOT, member.name))
            if not (target == base or target.startswith(base + os.sep)):
                sys.exit(f"[error] unsafe path in archive: {member.name}")
        tar.extractall(REPO_ROOT)


def _has_traces():
    return os.path.isdir(TRACE_DIR) and any(
        os.path.isfile(os.path.join(TRACE_DIR, f)) for f in os.listdir(TRACE_DIR))


def main():
    ap = argparse.ArgumentParser(description="Download the Terracotta workload traces.")
    ap.add_argument("--force", action="store_true",
                    help="re-download even if ./traces already exists")
    ap.add_argument("--keep-archive", action="store_true",
                    help="keep the downloaded archive after extraction")
    args = ap.parse_args()

    if _has_traces() and not args.force:
        n = sum(1 for f in os.listdir(TRACE_DIR)
                if os.path.isfile(os.path.join(TRACE_DIR, f)))
        print(f"[*] traces already present in {TRACE_DIR} ({n} files) -- nothing to do "
              "(use --force to re-download)")
        return

    archive = os.path.join(REPO_ROOT, ARCHIVE_NAME)
    download(archive)
    extract(archive)
    if not args.keep_archive:
        os.remove(archive)

    n = sum(1 for f in os.listdir(TRACE_DIR)
            if os.path.isfile(os.path.join(TRACE_DIR, f))) if os.path.isdir(TRACE_DIR) else 0
    print(f"[*] done: {n} trace files in {TRACE_DIR}")


if __name__ == "__main__":
    main()
