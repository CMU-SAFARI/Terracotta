#!/usr/bin/env python3
"""Terracotta MICRO 2026 artifact run driver (thin over common/).

This is a thin orchestration layer over the ``common/`` library. For each
selected (technique, core_setup) pair it:

  1. loads the technique manifest,
  2. renders + writes every experiment config into the results tree
     (via ``common.config_gen.generate``), and
  3. dispatches execution to one of two backends:
       - ``slurm`` : write one sbatch script per experiment + a jobfile, then
                     submit throttled (build_jobfile + submit_slurm)
       - ``local`` : bounded thread pool (run_local)

Both backends containerize by default: each per-job ``ramulator2`` invocation
runs inside the ``terracotta:latest`` image (``--runtime`` podman or docker, default podman),
bind-mounting the working root at the same path so absolute config/trace paths
resolve identically host- and container-side. ``--no-container`` restores the
bare-metal path, executing the host-built ``--ramulator-bin`` directly.

With ``--status`` it instead reports done/pending/failed via common.status.
With ``--generate-only`` it writes configs (and, for the SLURM backend, the
jobfile and sim_scripts) but never executes.

Every technique is handled identically; there is NO PRADA special-casing.
The PRADA hook is auto-dispatched inside common.manifest.get_experiments.
"""
import argparse
import os
import sys

REPO_ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, REPO_ROOT)

from common.manifest import load_manifest
from common.config_gen import generate
from common.execute import (DEFAULT_RAMULATOR, SBATCH_PREFIX, build_jobfile,
                            submit_slurm, run_local)
from common.status import report

ALL_TECHNIQUES = ["chargecache", "masa", "mopac", "chargecachemasa", "prada"]

IMAGE_TAG = "terracotta:latest"
IMAGE_TAR = os.path.join(REPO_ROOT, "terracotta_artifact.tar")
WD = REPO_ROOT  # working root: bind-mounted at the SAME path inside the container
SUPPORTED_RUNTIMES = ["podman", "docker"]  # rootless podman (default) or docker


# --------------------------------------------------------------------------- #
# Path helpers (run.py owns the results-tree prefix convention)
# --------------------------------------------------------------------------- #
def set_result_dir(root, technique, core_setup):
    return os.path.join(os.path.abspath(root), technique, core_setup)


def scripts_dir_for(set_rd):
    return os.path.join(set_rd, "sim_scripts")


def jobfile_for(set_rd):
    return os.path.join(set_rd, "sim_jobfile")


def status_dir_for(set_rd):
    return os.path.join(set_rd, "status")


# --log-level=error silences podman's info/warning chatter (e.g. the NFS
# "force_mask" warning) that otherwise pollutes each job's stderr -> error file
# and makes status.py misclassify successful runs as ERROR. Only genuine
# ramulator2/podman errors then land in the error file.
def container_prefix_str(runtime):
    """SLURM: shell-string command prefix; build_jobfile appends ' -f <config>'.
    Runs the IN-IMAGE binary (``ramulator2`` on PATH); the mount carries DATA only."""
    return f"{runtime} --log-level=error run --rm -v {WD}:{WD} -w {WD} {IMAGE_TAG} ramulator2"


def container_prefix_list(runtime):
    """Local: argv-list command prefix; _run_one appends ['-f', <config>]."""
    return [runtime, "--log-level=error", "run", "--rm",
            "-v", f"{WD}:{WD}", "-w", WD, IMAGE_TAG, "ramulator2"]


def load_preamble(runtime):
    """SLURM per-job prelude: idempotently load the image tar on the compute node.
    ``-q`` + ``--log-level=error`` keep the load's progress/warnings out of the
    job's error file so status.py doesn't read them as failures."""
    return (f"{runtime} image inspect {IMAGE_TAG} >/dev/null 2>&1 "
            f"|| {runtime} --log-level=error load -q -i {IMAGE_TAR}")


# --------------------------------------------------------------------------- #
# Resolution helpers
# --------------------------------------------------------------------------- #
def resolve_techniques(sel):
    if sel == "all":
        return list(ALL_TECHNIQUES)
    return [sel]


def resolve_core_setups(manifest, requested):
    if requested is not None:
        if requested not in manifest.core_setups:
            sys.stderr.write(
                f"[ERR] unknown core setup '{requested}' for technique "
                f"'{manifest.dir}'. Available: "
                f"{', '.join(manifest.core_setups.keys())}\n")
            raise SystemExit(2)
        return [requested]
    return list(manifest.core_setups.keys())


def resolve_limits(args, manifest):
    nei = (args.num_expected_insts if args.num_expected_insts is not None
           else manifest.run.get("num_expected_insts"))
    nmc = (args.num_max_cycles if args.num_max_cycles is not None
           else manifest.run.get("num_max_cycles"))
    return nei, nmc


# --------------------------------------------------------------------------- #
# Preflight validation (fail loudly, actionable)
# --------------------------------------------------------------------------- #
def check_ramulator_bin(args):
    """Bare-metal only: the host binary must exist (--no-container path)."""
    if not os.path.isfile(args.ramulator_bin):
        sys.stderr.write(
            f"[ERR] ramulator2 binary not found at {args.ramulator_bin}. "
            f"Build it: ramulator2/build_ramulator2_release.sh, or drop "
            f"--no-container to run the in-image binary.\n")
        raise SystemExit(1)


def check_runtime_available(runtime):
    import shutil
    if shutil.which(runtime) is None:
        sys.stderr.write(f"[ERR] container runtime '{runtime}' not on PATH.\n")
        raise SystemExit(1)


def check_image_local(runtime):
    """Local container mode: image must be in this host's store (run build.sh)."""
    import subprocess
    # `image inspect` (not podman-only `image exists`) so the check works on docker too.
    if subprocess.run([runtime, "image", "inspect", IMAGE_TAG],
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
        sys.stderr.write(
            f"[ERR] image '{IMAGE_TAG}' not found in local {runtime} store. "
            f"Build it: ./build.sh\n")
        raise SystemExit(1)


def check_image_tar(runtime):
    """SLURM container mode: the tar shipped to compute nodes must exist."""
    if not os.path.isfile(IMAGE_TAR):
        sys.stderr.write(
            f"[ERR] image tar '{IMAGE_TAR}' missing (compute nodes load from it). "
            f"Build it: ./build.sh\n")
        raise SystemExit(1)


def check_paths_under_wd(result_dir, trace_dir):
    """Container modes bind-mount only WD, so configs (result_dir) and traces
    (trace_dir) must live under WD to resolve inside the container."""
    base = os.path.abspath(WD)
    for label, path in (("--result-dir", result_dir), ("--trace-dir", trace_dir)):
        p = os.path.abspath(path)
        if not (p == base or p.startswith(base + os.sep)):
            sys.stderr.write(
                f"[ERR] container modes bind-mount only {base}, but {label} is {p} "
                f"(outside it). Keep it under the repo, or use --no-container.\n")
            raise SystemExit(1)


def warn_home_paths(result_dir, trace_dir):
    """Soft, non-blocking: SLURM compute nodes usually can't see /home."""
    for label, path in (("working dir", WD), ("--result-dir", result_dir),
                        ("--trace-dir", trace_dir)):
        if os.path.abspath(path).startswith("/home/"):
            sys.stderr.write(
                f"[WARN] {label} {os.path.abspath(path)} is under /home; SLURM "
                f"compute nodes may not see it. Prefer a shared path (e.g. /mnt/...).\n")


def check_trace_dir(trace_dir):
    if not os.path.isdir(trace_dir) or not os.listdir(trace_dir):
        sys.stderr.write(
            f"[ERR] traces/ missing or empty at {trace_dir}. "
            f"Run: python3 download_traces.py (or pass --trace-dir DIR)\n")
        raise SystemExit(1)


def check_technique_dir(technique):
    tdir = os.path.join(REPO_ROOT, "techniques", technique)
    if not os.path.isdir(tdir):
        sys.stderr.write(
            f"[ERR] unknown technique '{technique}': no directory at {tdir}\n")
        raise SystemExit(1)
    return tdir


# --------------------------------------------------------------------------- #
# Per-set drivers
# --------------------------------------------------------------------------- #
def run_one(args, technique, core_setup, trace_dir, result_dir):
    tdir = check_technique_dir(technique)
    manifest = load_manifest(tdir)
    set_rd = set_result_dir(result_dir, technique, core_setup)
    nei, nmc = resolve_limits(args, manifest)

    experiments = generate(manifest, core_setup, trace_dir, set_rd,
                           num_expected_insts=nei, num_max_cycles=nmc)
    container = not args.no_container
    print(f"[INFO] {technique}/{core_setup}: {len(experiments)} experiments "
          f"(mode={args.mode}, "
          f"{'container:' + args.runtime if container else 'no-container'})")

    if args.mode == "local":
        if container:
            cmd_prefix = container_prefix_list(args.runtime)
        else:
            cmd_prefix = [args.ramulator_bin]
        if args.generate_only:
            print(f"[INFO] {technique}/{core_setup}: --generate-only, "
                  f"configs written to {set_rd}; not executing.")
            return 0
        failed = run_local(experiments, cmd_prefix, args.threads)
        return 1 if failed else 0

    # SLURM backend.
    if container:
        ramulator_bin = container_prefix_str(args.runtime)
        preamble = load_preamble(args.runtime)
    else:
        ramulator_bin = args.ramulator_bin
        preamble = None

    sbatch_prefix = SBATCH_PREFIX
    if args.partition:
        sbatch_prefix += f" --partition={args.partition}"
    if args.qos:
        sbatch_prefix += f" --qos={args.qos}"
    build_jobfile(experiments, ramulator_bin,
                  scripts_dir_for(set_rd), jobfile_for(set_rd),
                  sbatch_prefix=sbatch_prefix, preamble=preamble)
    if args.generate_only:
        print(f"[INFO] {technique}/{core_setup}: --generate-only, jobfile at "
              f"{jobfile_for(set_rd)}; not submitting.")
        return 0
    submit_slurm(jobfile_for(set_rd), max_jobs=args.max_jobs)
    return 0


def status_one(args, technique, core_setup, result_dir):
    tdir = check_technique_dir(technique)
    manifest = load_manifest(tdir)
    set_rd = set_result_dir(result_dir, technique, core_setup)
    print(f"[INFO] {technique}/{core_setup}: status")
    buckets = report(manifest, core_setup, set_rd, status_dir_for(set_rd))
    pending = len(buckets["RUNNING"]) + len(buckets["MISSING"])
    failed = len(buckets["ERROR"])
    return 1 if (pending or failed) else 0


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def build_parser():
    p = argparse.ArgumentParser(
        prog="run.py",
        description="Terracotta MICRO 2026 artifact run driver (thin over common/).")
    p.add_argument("technique",
        choices=["chargecache", "masa", "mopac", "chargecachemasa", "prada", "all"],
        help="Technique to run, or 'all'.")
    p.add_argument("--mode", choices=["slurm", "local"], default="local",
        help="Execution backend (default: local). Both containerize by default.")
    p.add_argument("--runtime", choices=SUPPORTED_RUNTIMES, default="podman",
        help="Container runtime: podman (default) or docker.")
    p.add_argument("--no-container", action="store_true",
        help="Bare-metal: run the host-built --ramulator-bin instead of the image.")
    p.add_argument("--core-setup", default=None,
        help="Single core setup name; default = all core setups of the technique.")
    p.add_argument("--threads", type=int, default=(os.cpu_count() or 4),
        help="Local worker threads (mode=local).")
    p.add_argument("--trace-dir", default="./traces", help="Directory of trace files.")
    p.add_argument("--result-dir", default="./results", help="Root of the results tree.")
    p.add_argument("--ramulator-bin", default=DEFAULT_RAMULATOR,
        help="Host ramulator2 binary (default: %(default)s). Used ONLY with "
             "--no-container.")
    p.add_argument("--max-jobs", type=int, default=700,
        help="SLURM in-flight job cap (submit throttling).")
    p.add_argument("--partition", default=None,
        help="SLURM partition (sbatch --partition). Default: cluster default (cpu_part here).")
    p.add_argument("--qos", default=None,
        help="SLURM QOS (sbatch --qos). Default: none; this cluster does not enforce QOS. "
             "Set it on clusters that require a QOS.")
    p.add_argument("--generate-only", action="store_true",
        help="Write configs (+jobfile for the SLURM backend) but DO NOT execute.")
    p.add_argument("--status", action="store_true",
        help="Report done/pending/failed instead of running.")
    p.add_argument("--num-expected-insts", type=int, default=None,
        help="Override Frontend.num_expected_insts (else manifest.run value / YAML).")
    p.add_argument("--num-max-cycles", type=int, default=None,
        help="Override Frontend.num_max_cycles (else manifest.run value / YAML).")
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    trace_dir = os.path.abspath(args.trace_dir)
    result_dir = os.path.abspath(args.result_dir)

    # Preflight: technique dirs exist for everything we intend to touch.
    techniques = resolve_techniques(args.technique)
    for technique in techniques:
        check_technique_dir(technique)

    # Status mode needs neither an image/binary nor the traces. Config
    # generation (--generate-only) needs the traces but no built artifact.
    container = not args.no_container
    if not args.status:
        check_trace_dir(trace_dir)
        if container:
            check_paths_under_wd(result_dir, trace_dir)     # WD is the only bind mount
        if args.mode == "slurm":
            warn_home_paths(result_dir, trace_dir)          # soft, non-blocking
        if not args.generate_only:
            if container:
                if args.mode == "local":
                    # podman is invoked on THIS host only for a local run.
                    check_runtime_available(args.runtime)
                    check_image_local(args.runtime)         # image in host store
                else:
                    # SLURM: podman runs on the compute nodes (each job loads the
                    # tar); the submit host needs only the tar present, not podman.
                    check_image_tar(args.runtime)           # tar for compute nodes
            else:
                check_ramulator_bin(args)                    # bare-metal host binary

    rc = 0
    for technique in techniques:
        tdir = check_technique_dir(technique)
        manifest = load_manifest(tdir)
        for cs in resolve_core_setups(manifest, args.core_setup):
            if args.status:
                rc |= status_one(args, technique, cs, result_dir)
            else:
                rc |= run_one(args, technique, cs, trace_dir, result_dir)
    return rc


if __name__ == "__main__":
    sys.exit(main())
