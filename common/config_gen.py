"""Per-workload Ramulator2 config generation.

For each experiment (variant x workload x latency point) this loads the variant's
config YAML and applies exactly the runtime overrides the old per-technique
``setup_sim.py`` applied:

* ``Frontend.traces``                        -- absolute trace paths for the workload
* ``MemorySystem.DRAM.org.channel``          -- channel count for the core setup
* ``Frontend.lat_dump_path``                 -- per-experiment latency dump path
* ``MemorySystem.Controller.controller_latency`` -- baseline_latency + variant overhead

Optionally (``--num-expected-insts`` / ``--num-max-cycles``, or the equivalent
keyword arguments) it also overrides the frontend run limits; by default the limits
are left exactly as the variant YAML declares them, so default output is equivalent to
the old scripts.

This module replaces both ``setup_sim.py`` and ``cgra_setup_sim.py`` for every
technique: the CGRA variant is just another entry in the manifest's ``variants`` map.
"""

import argparse
import copy
import os

import yaml

from common.manifest import Experiment, get_experiments, load_manifest


def _result_paths(result_dir, name):
    result_dir = os.path.abspath(result_dir)
    return {
        "stat": os.path.join(result_dir, "stats", f"{name}.txt"),
        "error": os.path.join(result_dir, "errors", f"{name}.txt"),
        "config": os.path.join(result_dir, "configs", f"{name}.yaml"),
        "latency": os.path.join(result_dir, "latency", name),
    }


def _make_result_dirs(result_dir):
    result_dir = os.path.abspath(result_dir)
    for sub in ("stats", "errors", "configs", "latency"):
        os.makedirs(os.path.join(result_dir, sub), exist_ok=True)


def set_nested(config, path, value):
    """Set ``config[path[0]][path[1]]...`` = value. Path elements may be dict keys or
    list indices (ints), so sweep params can reach e.g. plugins[0].ControllerPlugin.x."""
    node = config
    for key in path[:-1]:
        node = node[key]
    node[path[-1]] = value


def render_config(experiment, trace_dir, result_dir,
                  num_expected_insts=None, num_max_cycles=None):
    """Return the config dict for one experiment (variant YAML + runtime overrides)."""
    with open(experiment.config_src, "r") as f:
        config = yaml.safe_load(f)

    trace_dir = os.path.abspath(trace_dir)
    paths = _result_paths(result_dir, experiment.name)

    config["Frontend"]["traces"] = [
        os.path.join(trace_dir, t) for t in experiment.trace_names
    ]
    config["MemorySystem"]["DRAM"]["org"]["channel"] = experiment.channels
    config["Frontend"]["lat_dump_path"] = paths["latency"]
    config["MemorySystem"][experiment.controller_key]["controller_latency"] = \
        experiment.controller_latency

    # Sweep / static parameter overrides (e.g. MoPAC's abo_threshold, update_probability).
    for path, value in experiment.param_overrides:
        set_nested(config, path, value)

    if num_expected_insts is not None:
        config["Frontend"]["num_expected_insts"] = int(num_expected_insts)
    if num_max_cycles is not None:
        config["Frontend"]["num_max_cycles"] = int(num_max_cycles)

    return config


def plan(manifest, core_setup_name, result_dir):
    """Enumerate experiments and their result paths WITHOUT writing anything.

    Shared by execute.py and status.py so every consumer agrees on the experiment set
    and where each experiment's config/stat/error/latency files live.
    """
    return [
        (exp, _result_paths(result_dir, exp.name))
        for exp in get_experiments(manifest, core_setup_name)
    ]


def generate(manifest, core_setup_name, trace_dir, result_dir,
             num_expected_insts=None, num_max_cycles=None):
    """Generate every config for a technique at one core setup.

    Writes ``<result_dir>/configs/<name>.yaml`` for each experiment and returns the
    list of ``(experiment, paths)`` pairs.
    """
    _make_result_dirs(result_dir)
    out = plan(manifest, core_setup_name, result_dir)
    for exp, paths in out:
        config = render_config(
            exp, trace_dir, result_dir,
            num_expected_insts=num_expected_insts, num_max_cycles=num_max_cycles,
        )
        with open(paths["config"], "w") as f:
            yaml.dump(config, f, default_flow_style=False, sort_keys=False)
    return out


def main():
    parser = argparse.ArgumentParser(
        description="Generate Ramulator2 configs for a technique at one core setup.",
    )
    parser.add_argument("-t", "--technique", required=True,
                        help="Path to the technique directory (techniques/<dir>).")
    parser.add_argument("-c", "--core-setup", required=True,
                        help="Core setup name from the manifest (e.g. single_core, four_core).")
    parser.add_argument("-td", "--trace-dir", required=True,
                        help="Directory containing the trace files.")
    parser.add_argument("-rd", "--result-dir", required=True,
                        help="Directory to write configs/stats/errors/latency under.")
    parser.add_argument("--num-expected-insts", type=int, default=None,
                        help="Override Frontend.num_expected_insts (default: leave YAML value).")
    parser.add_argument("--num-max-cycles", type=int, default=None,
                        help="Override Frontend.num_max_cycles (default: leave YAML value).")
    args = parser.parse_args()

    manifest = load_manifest(args.technique)
    generated = generate(
        manifest, args.core_setup, args.trace_dir, args.result_dir,
        num_expected_insts=args.num_expected_insts, num_max_cycles=args.num_max_cycles,
    )
    print(f"[config_gen] {manifest.technique} / {args.core_setup}: "
          f"generated {len(generated)} configs under {os.path.abspath(args.result_dir)}/configs")


if __name__ == "__main__":
    main()
