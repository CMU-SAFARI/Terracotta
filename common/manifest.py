"""Technique manifest loader, schema validation, and experiment enumeration.

A technique manifest (``techniques/<dir>/manifest.yaml``) is declarative data that
describes one DRAM technique's experiment matrix: its config variants, the controller
latency each variant runs with, the core setups (single/four core) it participates in,
and which comparisons feed which paper figure.

The manifest replaces the five divergent ``config.py`` files from the old per-technique
harnesses. All generic behavior lives here and in the sibling ``common`` modules; the
only per-technique code is an optional ``hook.py`` (currently PRADA only).

Controller-latency model
------------------------
Every generated config sets ``MemorySystem.Controller.controller_latency`` to
``baseline_latency + overhead``. A variant declares its overhead one of three ways:

* ``latency_overhead: <int>``            -- one experiment, no name suffix.
* ``latency_overhead: {single_core: a, four_core: b}`` -- per-core-setup overhead,
  no name suffix. (Used to reproduce quirks where a variant's latency differs
  between core counts.)
* ``latency_sweep: [<int>, ...]``        -- one experiment per point; the point value
  is appended to the experiment name (``terracotta_<workload>_<point>``).

A variant with neither key defaults to overhead 0.
"""

import importlib.util
import os
from dataclasses import dataclass, field
from typing import Optional

import yaml


@dataclass
class Variant:
    """One config variant of a technique (baseline, custom, oracle, terracotta, ...)."""

    name: str
    config: str  # config YAML filename, relative to the technique dir
    latency_overhead: object = 0  # int, or {core_setup: int}
    latency_sweep: Optional[list] = None  # list of ints, or None
    core_setups: Optional[list] = None  # restrict to these core setups (None = all)
    params: list = field(default_factory=list)  # static [{path, value}] config overrides
    sweep: Optional[str] = None  # name of a manifest-level sweep this variant runs
    sweep_bindings: list = field(default_factory=list)  # [{path, table}] filled per point


@dataclass
class CoreSetup:
    """One core count a technique runs at, plus its workload-mix file."""

    name: str
    cores: int
    channels: int
    mix: str  # mix filename, relative to the technique dir


@dataclass
class Manifest:
    technique: str  # paper-facing name, e.g. "ChargeCache"
    dir: str  # techniques/<dir>
    frontend: str  # SimpleO3 | PuMO3
    baseline_latency: int
    variants: dict  # name -> Variant
    core_setups: dict  # name -> CoreSetup
    path: str  # absolute path to the technique dir
    controller_key: str = "Controller"  # MemorySystem key holding controller_latency
    run: dict = field(default_factory=dict)  # documented full-run limits
    sweeps: dict = field(default_factory=dict)  # name -> {points, tables} parameter sweeps
    pum: dict = field(default_factory=dict)  # PRADA PuM config (consumed by hook.py)
    figures: list = field(default_factory=list)  # claims -> figure map
    has_hook: bool = False  # techniques/<dir>/hook.py present


@dataclass
class Experiment:
    """A single simulation to run: one variant x one workload x one latency point."""

    name: str  # experiment name / stem for stat, config, error files
    variant: str
    core_setup: str
    cores: int
    channels: int
    workload: str  # trace name (single core) or mix name (multi core)
    trace_names: list  # trace filenames making up this workload
    controller_latency: int
    config_src: str  # absolute path to the variant config YAML
    controller_key: str = "Controller"  # MemorySystem key holding controller_latency
    param_overrides: list = field(default_factory=list)  # [(path_list, value)] extra config edits


@dataclass
class MixEntry:
    name: str
    type: str
    traces: list


def parse_mix(path):
    """Parse a ``.mix`` file into an ordered list of :class:`MixEntry`.

    Each line is ``name,type,trace[,trace...]``. For a single-core mix the name and
    the single trace coincide; for a four-core mix the name is a label (``mix1``) and
    the traces are the four workloads.
    """
    entries = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            tokens = line.split(",")
            entries.append(MixEntry(name=tokens[0], type=tokens[1], traces=tokens[2:]))
    return entries


def _latency_points(manifest, variant, core_setup_name):
    """Yield ``(controller_latency, name_suffix)`` for a variant at a core setup."""
    base = manifest.baseline_latency
    if variant.latency_sweep is not None:
        for point in variant.latency_sweep:
            yield base + point, f"_{point}"
        return

    overhead = variant.latency_overhead
    if isinstance(overhead, dict):
        if core_setup_name not in overhead:
            raise ValueError(
                f"variant '{variant.name}' has no latency_overhead for core setup "
                f"'{core_setup_name}' (keys: {sorted(overhead)})"
            )
        overhead = overhead[core_setup_name]
    yield base + int(overhead), ""


def _sweep_points(manifest, variant):
    """Yield ``(name_suffix, [(path, value), ...])`` per parameter-sweep point.

    A variant without a ``sweep`` yields a single unnamed point with no bindings.
    """
    if variant.sweep is None:
        yield "", []
        return
    if variant.sweep not in manifest.sweeps:
        raise ValueError(f"variant '{variant.name}' references unknown sweep '{variant.sweep}'")
    sweep = manifest.sweeps[variant.sweep]
    for point in sweep["points"]:
        bindings = []
        for b in variant.sweep_bindings:
            table = sweep["tables"][b["table"]]
            if point not in table:
                raise ValueError(
                    f"sweep '{variant.sweep}' table '{b['table']}' has no entry for point {point}"
                )
            bindings.append((list(b["path"]), table[point]))
        yield f"_{point}", bindings


def _static_params(variant):
    return [(list(p["path"]), p["value"]) for p in variant.params]


def iter_experiments(manifest, core_setup_name):
    """Yield the :class:`Experiment` records for a technique at one core setup.

    Runtime paths (result/trace directories) are added by the caller; this function
    is pure and shared by config generation, status tracking, and parsing so they
    always agree on the experiment set. Experiment name is
    ``<variant>_<workload>[_<sweep_point>][_<latency_point>]``.
    """
    if core_setup_name not in manifest.core_setups:
        raise ValueError(
            f"unknown core setup '{core_setup_name}' "
            f"(known: {sorted(manifest.core_setups)})"
        )
    core_setup = manifest.core_setups[core_setup_name]
    mix_path = os.path.join(manifest.path, core_setup.mix)
    entries = parse_mix(mix_path)

    for variant in manifest.variants.values():
        if variant.core_setups is not None and core_setup_name not in variant.core_setups:
            continue
        config_src = os.path.join(manifest.path, variant.config)
        static = _static_params(variant)
        for sweep_suffix, sweep_bindings in _sweep_points(manifest, variant):
            for latency, lat_suffix in _latency_points(manifest, variant, core_setup_name):
                overrides = static + sweep_bindings
                for entry in entries:
                    yield Experiment(
                        name=f"{variant.name}_{entry.name}{sweep_suffix}{lat_suffix}",
                        variant=variant.name,
                        core_setup=core_setup_name,
                        cores=core_setup.cores,
                        channels=core_setup.channels,
                        workload=entry.name,
                        trace_names=list(entry.traces),
                        controller_latency=latency,
                        config_src=config_src,
                        controller_key=manifest.controller_key,
                        param_overrides=overrides,
                    )


def load_hook(manifest):
    """Import ``techniques/<dir>/hook.py`` if present, else return ``None``.

    A hook is the one place a technique may override generic behavior. It implements
    a fixed interface: ``generate_experiments(manifest, core_setup_name)`` and
    ``extra_stats()``. Only PRADA (PuM traces/operations) currently ships one.
    """
    if not manifest.has_hook:
        return None
    hook_path = os.path.join(manifest.path, "hook.py")
    spec = importlib.util.spec_from_file_location(f"technique_hook_{manifest.dir}", hook_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def get_experiments(manifest, core_setup_name):
    """Return the experiment list, dispatching to the technique hook when present."""
    hook = load_hook(manifest)
    if hook is not None and hasattr(hook, "generate_experiments"):
        return list(hook.generate_experiments(manifest, core_setup_name))
    return list(iter_experiments(manifest, core_setup_name))


# --------------------------------------------------------------------------- #
# Loading and validation
# --------------------------------------------------------------------------- #

_VALID_FRONTENDS = {"SimpleO3", "PuMO3", "BHO3"}


def _require(cond, msg):
    if not cond:
        raise ValueError(f"invalid manifest: {msg}")


def load_manifest(technique_dir):
    """Load and validate ``techniques/<dir>/manifest.yaml``.

    ``technique_dir`` may be the directory or the manifest file itself.
    """
    if os.path.isdir(technique_dir):
        manifest_path = os.path.join(technique_dir, "manifest.yaml")
        base_dir = technique_dir
    else:
        manifest_path = technique_dir
        base_dir = os.path.dirname(technique_dir)
    base_dir = os.path.abspath(base_dir)

    with open(manifest_path, "r") as f:
        raw = yaml.safe_load(f)

    _require(isinstance(raw, dict), "top level must be a mapping")
    for key in ("technique", "dir", "frontend", "baseline_latency", "variants", "core_setups"):
        _require(key in raw, f"missing required field '{key}'")
    _require(
        raw["frontend"] in _VALID_FRONTENDS,
        f"frontend must be one of {sorted(_VALID_FRONTENDS)}, got '{raw['frontend']}'",
    )
    _require(isinstance(raw["baseline_latency"], int), "baseline_latency must be an int")

    variants = {}
    _require(isinstance(raw["variants"], dict) and raw["variants"], "variants must be a non-empty mapping")
    for name, spec in raw["variants"].items():
        _require(isinstance(spec, dict), f"variant '{name}' must be a mapping")
        _require("config" in spec, f"variant '{name}' missing 'config'")
        has_sweep = "latency_sweep" in spec
        has_overhead = "latency_overhead" in spec
        _require(
            not (has_sweep and has_overhead),
            f"variant '{name}' declares both latency_sweep and latency_overhead",
        )
        if has_sweep:
            _require(
                isinstance(spec["latency_sweep"], list) and spec["latency_sweep"],
                f"variant '{name}' latency_sweep must be a non-empty list",
            )
        overhead = spec.get("latency_overhead", 0)
        if isinstance(overhead, dict):
            for cs, val in overhead.items():
                _require(isinstance(val, int), f"variant '{name}' latency_overhead[{cs}] must be an int")
        else:
            _require(isinstance(overhead, int), f"variant '{name}' latency_overhead must be an int or mapping")
        params = spec.get("params", []) or []
        for p in params:
            _require(isinstance(p, dict) and "path" in p and "value" in p,
                     f"variant '{name}' params entries need 'path' and 'value'")
        bindings = spec.get("sweep_bindings", []) or []
        for b in bindings:
            _require(isinstance(b, dict) and "path" in b and "table" in b,
                     f"variant '{name}' sweep_bindings entries need 'path' and 'table'")
        _require(not bindings or spec.get("sweep"),
                 f"variant '{name}' has sweep_bindings but no 'sweep'")
        variants[name] = Variant(
            name=name,
            config=spec["config"],
            latency_overhead=overhead,
            latency_sweep=spec.get("latency_sweep"),
            core_setups=spec.get("core_setups"),
            params=params,
            sweep=spec.get("sweep"),
            sweep_bindings=bindings,
        )

    core_setups = {}
    _require(
        isinstance(raw["core_setups"], dict) and raw["core_setups"],
        "core_setups must be a non-empty mapping",
    )
    for name, spec in raw["core_setups"].items():
        _require(isinstance(spec, dict), f"core setup '{name}' must be a mapping")
        for key in ("cores", "mix"):
            _require(key in spec, f"core setup '{name}' missing '{key}'")
        core_setups[name] = CoreSetup(
            name=name,
            cores=int(spec["cores"]),
            channels=int(spec.get("channels", 1)),
            mix=spec["mix"],
        )

    sweeps = raw.get("sweeps", {}) or {}
    _require(isinstance(sweeps, dict), "sweeps must be a mapping")
    for sname, sspec in sweeps.items():
        _require(isinstance(sspec, dict) and "points" in sspec and "tables" in sspec,
                 f"sweep '{sname}' needs 'points' and 'tables'")
        _require(isinstance(sspec["points"], list) and sspec["points"],
                 f"sweep '{sname}' points must be a non-empty list")
        _require(isinstance(sspec["tables"], dict), f"sweep '{sname}' tables must be a mapping")

    # Cross-reference checks against real core setups / sweeps.
    for variant in variants.values():
        if isinstance(variant.latency_overhead, dict):
            for cs in variant.latency_overhead:
                _require(cs in core_setups,
                         f"variant '{variant.name}' latency_overhead references unknown core setup '{cs}'")
        if variant.core_setups is not None:
            for cs in variant.core_setups:
                _require(cs in core_setups,
                         f"variant '{variant.name}' core_setups references unknown core setup '{cs}'")
        if variant.sweep is not None:
            _require(variant.sweep in sweeps,
                     f"variant '{variant.name}' references unknown sweep '{variant.sweep}'")
            for b in variant.sweep_bindings:
                _require(b["table"] in sweeps[variant.sweep]["tables"],
                         f"variant '{variant.name}' binds unknown table '{b['table']}' of sweep '{variant.sweep}'")

    manifest = Manifest(
        technique=raw["technique"],
        dir=raw["dir"],
        frontend=raw["frontend"],
        baseline_latency=raw["baseline_latency"],
        variants=variants,
        core_setups=core_setups,
        path=base_dir,
        controller_key=raw.get("controller_key", "Controller"),
        run=raw.get("run", {}) or {},
        sweeps=sweeps,
        pum=raw.get("pum", {}) or {},
        figures=raw.get("figures", []) or [],
        has_hook=os.path.exists(os.path.join(base_dir, "hook.py")),
    )

    # Referenced files must exist.
    for variant in variants.values():
        cfg = os.path.join(base_dir, variant.config)
        _require(os.path.exists(cfg), f"variant '{variant.name}' config not found: {variant.config}")
    for cs in core_setups.values():
        mix = os.path.join(base_dir, cs.mix)
        _require(os.path.exists(mix), f"core setup '{cs.name}' mix not found: {cs.mix}")

    return manifest
