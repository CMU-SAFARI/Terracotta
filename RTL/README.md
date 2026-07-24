# RTL — Hardware-complexity synthesis

OpenROAD synthesis of the Terracotta memory-controller logic and the custom per-technique
controllers it is compared against, on the open-source Nangate45 PDK. This is the source of the paper's
hardware-complexity overhead numbers (area / power).

This directory holds the internals of the RTL evaluation. The top-level scripts drive the evaluation. The hardware complexity evaluation is container-only (podman). See the top-level
[README](../README.md) for the full flow.

## Designs

| Directory | Top module(s) | Role |
|-----------|---------------|------|
| `design/`             | `TriggerArray`, `UpdateArray`, `ActionArray` | baseline building blocks |
| `design_chargecache/` | `ChargeCacheUnit` | ChargeCache custom controller |
| `design_masa/`        | `MASAUnit`        | MASA custom controller |
| `design_mopac/`       | `MoPACUnit`       | MoPAC-C custom controller |
| `design_prada/`       | `PRADAUnit`       | PRADA custom controller |
| `design_terracotta/`  | `TerracottaSingleTech` (+ optional `TerracottaUnit`) | Terracotta single-technique slice (×NUM_TECH = full cost) |

The overhead computation uses the four custom controllers plus `TerracottaSingleTech`.

## Internals

- `run_hardware_complexity.sh` — the driver (analogous to the simulator's `run.py`): runs the
  synthesis batch inside the container, collects the CSVs, and invokes the overhead computation.
- `run_synthesis.sh` — synthesizes the baseline arrays + the four custom controllers →
  `results/synthesis_results.csv`.
- `run_terracotta_synthesis.sh` — synthesizes `TerracottaSingleTech` →
  `results/terracotta_synthesis_results.csv`.
- `compute_overhead.py` — scales the raw 45 nm numbers to 10 nm (DeepScale) and normalizes to an
  Intel Xeon reference → `results/txt/hw_complexity.txt`.
- `Dockerfile` — builds the `terracotta-openroad:latest` image (pinned OpenROAD + Yosys).
- `OpenROAD-flow-scripts/` — the pinned ORFS toolchain (git submodule; BSD-3-Clause).
