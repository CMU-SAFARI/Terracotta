"""PRADA technique hook: PuM operation / trace-selection logic.

PRADA is the one technique whose experiment enumeration is genuinely unique rather than
declarative data, so it gets a hook (the interface the shared common/ harness looks for).
Instead of sweeping workload mixes, PRADA sweeps a fixed set of PuM operations; for each
operation it selects a trace by prefix + type and sets ``Frontend.operation``.

This reproduces the old prada/validation/setup_sim.py + cgra_setup_sim.py enumeration:
  * operations from manifest.pum.operations
  * baseline variants (manifest.pum.base_variants) use the base_* (type B) traces chosen by
    base_trace_prefix[op]; every other variant uses the pum_* (type P) traces chosen by
    trace_prefix[op]
  * experiment name = <variant>_<op>[_<latency_point>]
  * Frontend.operation is applied as a param override (config_gen writes it verbatim)
"""

import os

from common.manifest import Experiment, _latency_points


def _parse_pum_mix(path):
    """Parse the PuM mix into an ordered list of (trace_name, type), preserving file order
    (the old get_trace_lists used a dict; insertion order == file order)."""
    entries = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            tokens = line.split(",")
            entries.append((tokens[2], tokens[1]))
    return entries


def _select_trace(entries, prefix, wanted_type):
    for name, ttype in entries:
        if name.startswith(prefix) and ttype == wanted_type:
            return name
    raise ValueError(f"no trace with prefix '{prefix}' and type '{wanted_type}' in the mix")


def generate_experiments(manifest, core_setup_name):
    core_setup = manifest.core_setups[core_setup_name]
    entries = _parse_pum_mix(os.path.join(manifest.path, core_setup.mix))

    pum = manifest.pum
    operations = pum["operations"]
    pum_prefix = pum["trace_prefix"]
    base_prefix = pum["base_trace_prefix"]
    base_variants = set(pum.get("base_variants", []))

    experiments = []
    for variant in manifest.variants.values():
        if variant.core_setups is not None and core_setup_name not in variant.core_setups:
            continue
        config_src = os.path.join(manifest.path, variant.config)
        use_base = variant.name in base_variants
        for op in operations:
            prefix = base_prefix[op] if use_base else pum_prefix[op]
            wanted_type = "B" if use_base else "P"
            trace = _select_trace(entries, prefix, wanted_type)
            for latency, lat_suffix in _latency_points(manifest, variant, core_setup_name):
                experiments.append(Experiment(
                    name=f"{variant.name}_{op}{lat_suffix}",
                    variant=variant.name,
                    core_setup=core_setup_name,
                    cores=core_setup.cores,
                    channels=core_setup.channels,
                    workload=op,
                    trace_names=[trace],
                    controller_latency=latency,
                    config_src=config_src,
                    controller_key=manifest.controller_key,
                    param_overrides=[(["Frontend", "operation"], op)],
                ))
    return experiments
