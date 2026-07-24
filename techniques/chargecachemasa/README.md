# ChargeCacheMASA

ChargeCacheMASA is the composite case study, evaluated on the `SimpleO3` frontend. It compares baseline, ChargeCache, MASA, and the combined ChargeCacheMASA controller, each in a custom and a Terracotta form, plus a bus-utilization-threshold family (t020..t050) shipped as separate config YAMLs (each baking in its own `AdaptiveCC.bus_util_threshold`). The DDR5 baseline controller latency is 8; each variant adds its overhead on top.

## Config variants

- `baseline` (`config: baseline.yaml`) — Unmodified baseline controller (controller_latency 8).
- `chargecache` (`config: cc.yaml`) — Custom ChargeCache controller; +1 (controller_latency 9).
- `masa` (`config: masa.yaml`) — Custom MASA controller (controller_latency 8).
- `chargecachemasa` (`config: chargecachemasa.yaml`) — Custom combined ChargeCacheMASA controller; +1 (controller_latency 9).
- `terracotta_chargecache` (`config: terracotta_chargecache.yaml`) — ChargeCache on Terracotta (Tables), +2 (controller_latency 10).
- `terracotta_masa` (`config: terracotta_masa.yaml`) — MASA on Terracotta (Tables), +2 (controller_latency 10).
- `terracotta_chargecachemasa` (`config: terracotta_chargecachemasa.yaml`) — Combined ChargeCacheMASA on Terracotta (Tables), +2 (controller_latency 10).
- `terracotta_chargecachemasa_t020` (`config: terracotta_chargecachemasa_t020.yaml`) — Terracotta (Tables) ChargeCacheMASA at `bus_util_threshold` 0.20, four-core only (+2, controller_latency 10).
- `terracotta_chargecachemasa_t030` (`config: terracotta_chargecachemasa_t030.yaml`) — As above at threshold 0.30, four-core only.
- `terracotta_chargecachemasa_t040` (`config: terracotta_chargecachemasa_t040.yaml`) — As above at threshold 0.40, four-core only.
- `terracotta_chargecachemasa_t050` (`config: terracotta_chargecachemasa_t050.yaml`) — As above at threshold 0.50, four-core only.
- `terracotta_cgra_chargecachemasa` (`config: terracotta_cgra_chargecachemasa.yaml`) — Combined ChargeCacheMASA on Terracotta-CGRA; +8 (controller_latency 16).
- `terracotta_cgra_chargecachemasa_t020` (`config: terracotta_cgra_chargecachemasa_t020.yaml`) — Terracotta-CGRA ChargeCacheMASA at threshold 0.20 (+8, controller_latency 16).
- `terracotta_cgra_chargecachemasa_t030` (`config: terracotta_cgra_chargecachemasa_t030.yaml`) — As above at threshold 0.30.
- `terracotta_cgra_chargecachemasa_t040` (`config: terracotta_cgra_chargecachemasa_t040.yaml`) — As above at threshold 0.40.
- `terracotta_cgra_chargecachemasa_t050` (`config: terracotta_cgra_chargecachemasa_t050.yaml`) — As above at threshold 0.50.
- `terracotta_chargecachemasa_adaptive` (`config: terracotta_chargecachemasa_adaptive.yaml`) — Retained adaptive bus-util-threshold variant, four-core, +2 (controller_latency 10); sourced from the separate weighted-speedup investigation rather than the generator.

## Core setups

- `single_core` — 1 core, 1 channel, `../../common/mixes/single.mix`.
- `four_core` — 4 cores, 1 channel, `../../common/mixes/four.mix`.

## Figures

- `main_speedup` — custom vs Terracotta comparison: compares `baseline`, `chargecache`, `masa`, `chargecachemasa`, and `terracotta_chargecachemasa` (metric: speedup over baseline).
- `threshold_sweep` — four-core `bus_util_threshold` sensitivity: compares `terracotta_chargecachemasa_t020/t030/t040/t050` and `terracotta_chargecachemasa_adaptive` (metric: speedup over baseline).
- `figure16` — Terracotta-CGRA vs Terracotta-Tables vs custom: compares `chargecachemasa`, `terracotta_chargecachemasa`, and `terracotta_cgra_chargecachemasa` (metric: speedup over baseline).

The mapping from these figure ids to the paper's figure numbers is defined in the paper.
