# MASA

MASA is a subarray-level DRAM technique; its oracle (`DDR5IMASA`) models a perfect subarray-selection predictor. This case study runs on the `SimpleO3` frontend and compares an unmodified baseline controller, the custom MASA controller, the ideal MASA oracle, and Terracotta-based forms. The DDR5 baseline controller latency is 8; each variant adds its overhead on top.

## Config variants

- `baseline` (`config: baseline.yaml`) — Unmodified baseline controller (controller_latency 8).
- `custom` (`config: masa.yaml`) — Custom MASA controller (paper's "MASA"); no added latency, controller_latency 8.
- `oracle` (`config: oracle.yaml`) — Ideal MASA (`DDR5IMASA`): perfect subarray-selection oracle, controller_latency 8.
- `terracotta` (`config: terracotta_masa.yaml`) — MASA on Terracotta (Tables interface) at the +2 latency point, controller_latency 10.
- `terracotta_cgra` (`config: terracotta_cgra_masa.yaml`) — MASA on Terracotta-CGRA: baseline + CGRA trigger/update latency (+7), controller_latency 15.
- `terracotta_latency` (`config: terracotta_masa.yaml`) — Isolated four-core-only controller-latency-overhead sweep [4, 6, 8, 10] (point 2 reused from the main terracotta four-core run); feeds only the latency-sensitivity figure.

## Core setups

- `single_core` — 1 core, 1 channel, `../../common/mixes/single.mix`.
- `four_core` — 4 cores, 1 channel, `../../common/mixes/four.mix`.

## Figures

- `main_speedup` — main MASA speedup comparison across `baseline`, `custom`, `oracle`, and `terracotta` (metric: speedup over baseline).
- `figure16` — Terracotta-CGRA vs Terracotta-Tables vs custom: compares `custom`, `terracotta`, and `terracotta_cgra` (metric: speedup over baseline).

The mapping from these figure ids to the paper's figure numbers is defined in the paper.
