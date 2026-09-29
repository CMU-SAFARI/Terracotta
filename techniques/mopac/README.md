# MoPAC-C

MoPAC-C is a PRAC-based RowHammer mitigation, evaluated on the `BHO3` frontend; its controller lives under `MemorySystem.BHDRAMController`. The mitigation is tuned per RowHammer threshold `nRH` (points 250, 500, 1000): each point sets the plugin's activation-budget threshold (`abo_threshold`) and probabilistic update rate (`update_probability`). The DDR5 baseline controller latency is 8.

## Config variants

- `baseline` (`config: baseline.yaml`) — Unmodified baseline controller (controller_latency 8).
- `prac` (`config: prac.yaml`) — PRAC-only mitigation baseline; `abo_threshold` fixed at 219 (the nRH=250 point) and not swept, controller_latency 8.
- `custom` (`config: mitigation.yaml`) — Custom MoPAC-C controller (paper's "MoPAC-C"), swept over `nRH` with `abo_threshold`/`update_probability` bound to the nRH tables, controller_latency 8.
- `terracotta` (`config: terracotta_mitigation.yaml`) — MoPAC-C on Terracotta (Tables): the `nRH` sweep crossed with the +2 latency point, controller_latency 10.
- `terracotta_cgra` (`config: terracotta_cgra_mitigation.yaml`) — MoPAC-C on Terracotta-CGRA: baseline + CGRA trigger/update latency (+6), controller_latency 14; swept over `nRH`.
- `terracotta_latency` (`config: terracotta_mitigation.yaml`) — Isolated four-core-only controller-latency-overhead sweep [4, 6, 8, 10] at fixed nRH=250 (`abo_threshold` 80, `update_probability` 0.25); feeds only the latency-sensitivity figure.

## Core setups

- `single_core` — 1 core, 1 channel, `../../common/mixes/single.mix`.
- `four_core` — 4 cores, 1 channel, `../../common/mixes/four.mix`.

## Figures

- `main_mitigation` (paper Fig. 10) — main MoPAC-C comparison across `nRH`: compares `baseline`, `prac`, `custom`, and `terracotta` (metric: speedup over baseline).
- `figure16` (paper Fig. 16) — Terracotta-CGRA vs Terracotta-Tables vs custom: compares `custom`, `terracotta`, and `terracotta_cgra` (metric: speedup over baseline).
