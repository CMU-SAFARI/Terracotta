Synthesizable skeletons for decoupled triggers, updates, and actions.

Modules
- common/ConfigTable.sv: Parameterized key→value config table, combinational read, synchronous write.
- triggers/TriggerUnit.sv: Single-cycle config + predicate using metadata, emits packet with tech_id.
- triggers/TriggerArray.sv: Wrapper to instantiate NUM_TECH TriggerUnit instances.
- updates/UpdateUnit.sv: Single-cycle config + update intent (micro-op) generator.
- actions/ActionUnit.sv: Single-cycle config + action command generator.

Packet fields (parameterized widths)
- req_id, cmd_id, address: bg_id, ba_id, sa_id, row_id, col_id, priority, timestamp.
- UpdateUnit includes tech_id input; TriggerUnit outputs tech_id from its instance parameter.

Config keys
- TriggerUnit: key = {req_id, cmd_id}.
- UpdateUnit: key = cmd_id.
- ActionUnit: key = cmd_id.

Timing
- 1 cycle from in_valid to out_valid; combinational config read and logic with registered outputs.

Usage
- Instantiate modules standalone; drive cfg_wr_en/cfg_wr_key/cfg_wr_value to program tables.
- For TriggerUnit, provide metadata_valid/metadata_in; tables for metadata are external.
