# ChargeCache

ChargeCache uses a predictor of highly-charged DRAM rows to accelerate their access. This case study runs on the `SimpleO3` frontend and compares an unmodified baseline controller, the custom ChargeCache controller, an oracle (perfect highly-charged-row predictor), and Terracotta-based forms. The DDR5 baseline controller latency is 8; each variant adds its overhead on top.

## Config variants

- `baseline` (`config: baseline.yaml`) — Unmodified baseline controller (controller_latency 8).
- `custom` (`config: chargecache.yaml`) — Custom ChargeCache controller (paper's "ChargeCache"); +1-cycle lookup overhead, controller_latency 9.
- `oracle` (`config: oracle.yaml`) — Oracle ChargeCache with a perfect highly-charged-row predictor; an ideal/free predictor adds no lookup overhead, so controller_latency 8 for both core setups.
- `terracotta` (`config: terracotta_chargecache.yaml`) — ChargeCache on Terracotta (Tables interface) at the +2 latency point, controller_latency 10.
- `terracotta_cgra` (`config: terracotta_cgra_chargecache.yaml`) — ChargeCache on Terracotta-CGRA: baseline + CGRA trigger/update latency (+8), controller_latency 16.
- `terracotta_latency` (`config: terracotta_chargecache.yaml`) — Isolated four-core-only controller-latency-overhead sweep [4, 6, 8, 10] (point 2 reused from the main terracotta four-core run); feeds only the latency-sensitivity figure.

## Core setups

- `single_core` — 1 core, 1 channel, `../../common/mixes/single.mix`.
- `four_core` — 4 cores, 1 channel, `../../common/mixes/four.mix`.

## Figures

- `main_speedup` — main ChargeCache speedup comparison across `baseline`, `custom`, `oracle`, and `terracotta` (metric: speedup over baseline).
- `figure16` — Terracotta-CGRA vs Terracotta-Tables vs custom: compares `custom`, `terracotta`, and `terracotta_cgra` (metric: speedup over baseline).

The mapping from these figure ids to the paper's figure numbers is defined in the paper.
