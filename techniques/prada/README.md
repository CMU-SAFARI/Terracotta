# PRADA

PRADA is a Processing-using-Memory (PuM) case study, evaluated on the `PuMO3` frontend. Unlike the other techniques it does not sweep workload mixes: it sweeps a fixed set of PuM operations (`andor`, `nandnor`, `xorxnor`, `copy`, `not`), and the co-located `hook.py` selects each operation's trace by prefix and type (baseline uses the non-PuM `base_*` traces, the rest use the PuM `pum_*` traces) and sets `Frontend.operation`. The DDR5 baseline controller latency is 8.

## Config variants

- `baseline` (`config: baseline.yaml`) — Runs the non-PuM (`base_*`) traces; participates in both the 32-bank and 1-bank setups (controller_latency 8).
- `custom` (`config: prada.yaml`) — Custom PRADA running the PuM (`pum_*`) traces at both bank counts (controller_latency 8).
- `terracotta` (`config: terracotta_prada.yaml`) — PRADA on Terracotta (Tables) at both bank counts, +2 (controller_latency 10).
- `terracotta_cgra` (`config: terracotta_cgra_prada.yaml`) — PRADA on Terracotta-CGRA; +4 CGRA latency (controller_latency 12); the only PuM variant the 1-bank run exercises alongside baseline.
- `terracotta_latency` (`config: terracotta_prada.yaml`) — Isolated 32-bank single-core controller-latency-overhead sweep [4, 6, 8, 10] (point 2 reused from the main terracotta run); feeds only the latency-sensitivity figure via the PuM cycle-ratio metric.

## Core setups

- `single_core` — 1 core, 1 channel, `mixes/single.mix`; the 32-bank PuM run (traces `*_32M`), all four variants.
- `single_core_1b` — 1 core, 1 channel, `mixes/single_1b.mix`; the 1-bank PuM run (traces `*_1b`), all four variants.

## Figures

- `main_pum` — per-operation PuM speedup: compares `baseline`, `custom`, and `terracotta` (metric: `pum_speedup`, an execution-cycle ratio of baseline CPU cycles to in-DRAM PuM cycles, not an IPC ratio).
- `figure16` — Terracotta-CGRA vs Terracotta-Tables vs custom: compares `custom`, `terracotta`, and `terracotta_cgra` (metric: speedup over baseline).

The mapping from these figure ids to the paper's figure numbers is defined in the paper.
