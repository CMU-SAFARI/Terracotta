"""Experiment execution: SLURM jobfile generation + submission, and a local thread pool.

Consumes the config plan produced by :mod:`common.config_gen` (configs must already be
generated) and runs each experiment, writing the stat dump to ``<result>/stats/<name>.txt``
and stderr to ``<result>/errors/<name>.txt``. Replaces the per-technique ``run_sim.py``.

Two backends:
* ``slurm`` -- write one sbatch script per experiment + a jobfile, then submit throttled
  under a running-job cap (the cluster path we actually use).
* ``local`` -- a bounded thread pool for a personal-computer run.
"""

import argparse
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

from common.config_gen import plan
from common.manifest import load_manifest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_RAMULATOR = os.path.join(REPO_ROOT, "ramulator2", "build", "ramulator2")

CMD_HEADER = "#! /bin/bash"
SBATCH_PREFIX = "sbatch --cpus-per-task=1 --nodes=1 --ntasks=1"


# --------------------------------------------------------------------------- #
# SLURM backend
# --------------------------------------------------------------------------- #

def build_jobfile(experiments, ramulator_bin, scripts_dir, jobfile_path,
                  sbatch_prefix=SBATCH_PREFIX, preamble=None):
    """Write one sbatch script per experiment and a jobfile of sbatch commands.

    ``ramulator_bin`` is a raw shell-string command prefix (a bare binary path, or
    a full ``podman run ... ramulator2`` container invocation); this function
    appends ``-f <config>`` to it. ``preamble``, if given, is emitted verbatim
    before the run line in each script (e.g. an idempotent ``podman load``).
    """
    os.makedirs(scripts_dir, exist_ok=True)
    lines = [CMD_HEADER]
    for exp, paths in experiments:
        script_path = os.path.join(scripts_dir, f"{exp.name}.sh")
        body = [CMD_HEADER]
        if preamble:
            body.append(preamble)
        body.append(f"{ramulator_bin} -f {paths['config']}")
        with open(script_path, "w") as f:
            f.write("\n".join(body) + "\n")
        lines.append(
            f"{sbatch_prefix} --job-name={exp.name} "
            f"--output={paths['stat']} --error={paths['error']} {script_path}"
        )
    with open(jobfile_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    os.chmod(jobfile_path, 0o755)
    return jobfile_path


def _running_jobs(username):
    out = subprocess.run(f"squeue -u {username} -h | wc -l", shell=True,
                         stdout=subprocess.PIPE, text=True)
    return int(out.stdout.strip() or "0")


def submit_slurm(jobfile_path, max_jobs=700, submit_delay=0.1, retry_delay=60):
    """Submit each sbatch command in the jobfile, throttled under a running-job cap."""
    username = os.getenv("USER")
    with open(jobfile_path, "r") as f:
        cmds = [ln.strip() for ln in f if ln.strip() and not ln.startswith("#")]
    for cmd in cmds:
        while _running_jobs(username) >= max_jobs:
            print(f"[execute] job cap ({max_jobs}) reached; retrying in {retry_delay}s")
            time.sleep(retry_delay)
        os.system(cmd)
        time.sleep(submit_delay)
    print(f"[execute] submitted {len(cmds)} jobs")


# --------------------------------------------------------------------------- #
# Local backend
# --------------------------------------------------------------------------- #

def _run_one(cmd_prefix, exp, paths):
    with open(paths["stat"], "w") as out, open(paths["error"], "w") as err:
        rc = subprocess.run(cmd_prefix + ["-f", paths["config"]],
                            stdout=out, stderr=err).returncode
    return exp.name, rc


def run_local(experiments, cmd_prefix, threads):
    """Run every experiment in a bounded thread pool. Returns list of failed names.

    ``cmd_prefix`` is an argv list: ``[<host-bin>]`` for a bare-metal run, or the
    full ``['podman', 'run', ..., 'terracotta:latest', 'ramulator2']`` container
    prefix. ``['-f', <config>]`` is appended per experiment.
    """
    failed = []
    with ThreadPoolExecutor(max_workers=threads) as pool:
        futures = [pool.submit(_run_one, cmd_prefix, exp, paths)
                   for exp, paths in experiments]
        for i, fut in enumerate(as_completed(futures), 1):
            name, rc = fut.result()
            status = "ok" if rc == 0 else f"FAIL({rc})"
            print(f"[execute] ({i}/{len(futures)}) {name}: {status}")
            if rc != 0:
                failed.append(name)
    if failed:
        print(f"[execute] {len(failed)} experiments failed: {', '.join(failed)}")
    return failed


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #

def main():
    parser = argparse.ArgumentParser(description="Run a technique's experiments.")
    parser.add_argument("-t", "--technique", required=True, help="techniques/<dir>")
    parser.add_argument("-c", "--core-setup", required=True)
    parser.add_argument("-rd", "--result-dir", required=True)
    parser.add_argument("-b", "--backend", choices=["slurm", "local"], default="local")
    parser.add_argument("--threads", type=int, default=os.cpu_count() or 4)
    parser.add_argument("--ramulator", default=DEFAULT_RAMULATOR)
    parser.add_argument("--max-jobs", type=int, default=700)
    parser.add_argument("--scripts-dir", default=None,
                        help="SLURM per-job script dir (default: <result-dir>/sim_scripts).")
    parser.add_argument("--jobfile", default=None,
                        help="SLURM jobfile path (default: <result-dir>/sim_jobfile).")
    parser.add_argument("--no-submit", action="store_true",
                        help="SLURM: build the jobfile but do not submit it.")
    args = parser.parse_args()

    manifest = load_manifest(args.technique)
    experiments = plan(manifest, args.core_setup, args.result_dir)

    if args.backend == "local":
        # Bare-metal only; run.py is the container-aware entry point. run_local now
        # takes an argv-list command prefix, so wrap the host binary in a list.
        failed = run_local(experiments, [args.ramulator], args.threads)
        return 1 if failed else 0

    scripts_dir = args.scripts_dir or os.path.join(args.result_dir, "sim_scripts")
    jobfile = args.jobfile or os.path.join(args.result_dir, "sim_jobfile")
    build_jobfile(experiments, args.ramulator, scripts_dir, jobfile)
    print(f"[execute] jobfile: {jobfile}")
    if not args.no_submit:
        submit_slurm(jobfile, max_jobs=args.max_jobs)
    return 0


if __name__ == "__main__":
    sys.exit(main())
