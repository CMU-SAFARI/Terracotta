# Techniques

The DRAM techniques Terracotta hosts, evaluated by the performance & DRAM-energy sweep. Each
subdirectory is one technique (repo dir → paper name):

| Directory | Paper name |
|-----------|------------|
| `prada`           | PRADA (Processing-using-Memory) |
| `mopac`           | MoPAC-C |
| `masa`            | MASA |
| `chargecache`     | ChargeCache |
| `chargecachemasa` | ChargeCache + MASA |

Each technique is described declaratively by its `manifest.yaml`, which enumerates the config
variants (baseline, custom, Terracotta, …), the core setups, the workload mixes, and the figures
the technique feeds. The shared `common/` harness turns a manifest into per-experiment Ramulator2
configs, executes them, and parses the results. See each technique's own `README.md` for its
specifics.

## Layout of a technique directory

```
techniques/<t>/
├── manifest.yaml     # declarative experiment matrix (variants, core setups, mixes, figures)
├── *.yaml            # the config variants referenced by the manifest
│                     #   (baseline, custom, terracotta[, terracotta_cgra, oracle, …])
├── mixes/            # workload mixes referenced by the manifest
└── README.md         # what this technique evaluates
```

`prada/` additionally carries a co-located `hook.py` (PRADA has unique PuM trace-selection logic)
and a `trace/` helper for regenerating the PuM traces.

To run the sweep and regenerate the figures, see the top-level [README](../README.md).
