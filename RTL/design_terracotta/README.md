# MemoryController design with ORFS

Config: use this directory's `config.mk` with ORFS's `flow/Makefile`.
Top: `MemoryController` on platform `nangate45`.

Quick usage

- Print key vars

```bash
make -C RTL/OpenROAD-flow-scripts/flow DESIGN_CONFIG=../../design/nangate45/MemoryController/config.mk \
  print-DESIGN_NAME print-VERILOG_FILES print-SDC_FILE
```

- Run synthesis only (example)

```bash
make -C RTL/OpenROAD-flow-scripts/flow DESIGN_CONFIG=../../design/nangate45/MemoryController/config.mk synth
```

- Full flow to GDS (example)

```bash
make -C RTL/OpenROAD-flow-scripts/flow DESIGN_CONFIG=../../design/nangate45/MemoryController/config.mk finish
```

Notes

- `constraints/constraints.sdc` defines `create_clock` and sets the top design name.
- You can override variables on the command line, e.g. `CORE_UTILIZATION=60`.