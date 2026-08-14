package terracotta_types_pkg;
  // Common field widths (adjust as needed)
  localparam int TC_REQ_W        = 3;
  localparam int TC_CMD_W        = 6;
  localparam int TC_BG_W         = 3;
  localparam int TC_BA_W         = 2;
  localparam int TC_SA_W         = 7;
  localparam int TC_ROW_W        = 9;
  localparam int TC_COL_W        = 10;
  localparam int TC_PRI_W        = 10;
  localparam int TC_TS_W         = 32;

  localparam int TC_TECH_W       = 2;

  // Trigger specific
  localparam int TC_METADATA_W   = 32;    // Metadata width
  // Match logic control now encodes operation and RHS source:
  // [1:0] op_sel: 2'b00=LT, 2'b01=EQ, 2'b10=NE, 2'b11=reserved
  // [3:2] rhs_sel: 2'b00=const(meta_const), 2'b01=sa_id, 2'b10=row_id, 2'b11=col_id
  localparam int TC_MATCH_LOGIC_W = 4;
  localparam int TC_CMD_FEEDBACK_W= 6;    // feedback payload width
  localparam int TC_CUSTOM_CMD_W = 6;
  // Tag composition control: fixed positions {sa,row,col} with per-field enable
  localparam int TC_TAG_USE_W = 3;        // [2]=use_sa, [1]=use_row, [0]=use_col
  
  localparam int TC_T_CFG_DEPTH    = 16;   // Trigger configuration memory depth (entries)
  // Trigger configuration entry width (bits):
  // require_meta(1) + match_logic(TC_MATCH_LOGIC_W) + match_value(TC_METADATA_W)
  // + custom_cmd_id(TC_CUSTOM_CMD_W) + cmd_feedback(TC_CMD_FEEDBACK_W)
  // + meta_const(TC_METADATA_W)
  localparam int TC_T_CFG_W        = 1 + TC_MATCH_LOGIC_W + TC_METADATA_W
                                   + TC_CUSTOM_CMD_W + TC_CMD_FEEDBACK_W
                                   + TC_METADATA_W + TC_TAG_USE_W;

  // Update specific
  localparam int TC_UPDATE_CODE_W = 8;
  localparam int TC_UPDATE_DATA_W = 32;
  // Update configuration
  // Update logic op encodes how to transform metadata_in → metadata_out
  // [1:0] update_op: 2'b00=ZERO, 2'b01=INCR(+1), 2'b10=CONST(assign), 2'b11=reserved(PASS)
  localparam int TC_UPDATE_LOGIC_W = 2;
  // Depth/width of UpdateUnit configuration table
  localparam int TC_U_CFG_DEPTH  = 8;
  // Entry layout (LSB → MSB):
  //   tag_use(TC_TAG_USE_W)
  //   update_logic(TC_UPDATE_LOGIC_W)
  //   update_const(TC_METADATA_W)
  //   timer_reload_mask(TC_TS_W)
  localparam int TC_U_CFG_W      = TC_TAG_USE_W
                                  + TC_UPDATE_LOGIC_W
                                  + TC_METADATA_W
                                  + TC_TS_W;

  // Action specific
  localparam int TC_ACTION_ID_W   = 8;
  localparam int TC_ACTION_PARAM_W= 32;
  // Action configuration & payload table
  localparam int TC_PAYLOAD_IDX_W   = 7;  // start index into payload table
  localparam int TC_PAYLOAD_RANGE_W = 7;   // number of payload entries to emit
  localparam int TC_REG_ID_W        = 4;   // destination register id (payload[12:9])
  localparam int TC_OPERAND_SEL_W   = 2;   // operand source selector
  // Action config memory depth/width
  localparam int TC_A_CFG_DEPTH     = 8;
  localparam int TC_A_CFG_W         = TC_PAYLOAD_IDX_W + TC_PAYLOAD_RANGE_W;
  // Payload table depth/entry width
  localparam int TC_A_PAYLOAD_DEPTH = 128;
  localparam int TC_A_PAYLOAD_W     = TC_REG_ID_W + TC_OPERAND_SEL_W;

  typedef struct packed {
    logic [TC_REQ_W-1:0]  req_id;
    logic [TC_CMD_W-1:0]  cmd_id;
    logic [TC_BG_W-1:0]   bg_id;
    logic [TC_BA_W-1:0]   ba_id;
    logic [TC_SA_W-1:0]   sa_id;
    logic [TC_ROW_W-1:0]  row_id;
    logic [TC_COL_W-1:0]  col_id;
    logic [TC_PRI_W-1:0]  prio;
    logic [TC_TS_W-1:0]   timestamp;
  } trigger_in_t;

  typedef struct packed {
    logic [TC_TECH_W-1:0] tech_id;
    logic [TC_CMD_W-1:0]  cmd_id;
    logic [TC_BG_W-1:0]   bg_id;
    logic [TC_BA_W-1:0]   ba_id;
    logic [TC_SA_W-1:0]   sa_id;
    logic [TC_ROW_W-1:0]  row_id;
    logic [TC_COL_W-1:0]  col_id;
    logic [TC_PRI_W-1:0]  prio;
    logic [TC_TS_W-1:0]   timestamp;
    logic [TC_CMD_FEEDBACK_W-1:0] cmd_feedback;
  } trigger_out_t;

  // UpdateUnit packet types
  typedef struct packed {
    logic [TC_TECH_W-1:0] tech_id;
    logic [TC_CMD_W-1:0]  cmd_id;
    logic [TC_BG_W-1:0]   bg_id;
    logic [TC_BA_W-1:0]   ba_id;
    logic [TC_SA_W-1:0]   sa_id;
    logic [TC_ROW_W-1:0]  row_id;
    logic [TC_COL_W-1:0]  col_id;
    logic [TC_PRI_W-1:0]  prio;
    logic [TC_TS_W-1:0]   timestamp;
  } update_in_t;

  typedef struct packed {
    logic [TC_UPDATE_CODE_W-1:0] update_code;
    logic [TC_UPDATE_DATA_W-1:0] update_data;
  } update_out_t;

  // ActionUnit packet types
  typedef struct packed {
    logic [TC_TECH_W-1:0]  tech_id;
    logic [TC_CMD_W-1:0]  cmd_id;
    logic [TC_BG_W-1:0]   bg_id;
    logic [TC_BA_W-1:0]   ba_id;
    logic [TC_SA_W-1:0]   sa_id;
    logic [TC_ROW_W-1:0]  row_id;
    logic [TC_COL_W-1:0]  col_id;
    logic [TC_PRI_W-1:0]  prio;
    logic [TC_TS_W-1:0]   timestamp;
  } action_in_t;

  // Terracotta action wave: 15 bits total
  // [14] MSB: always 1 (Terracotta identifier)
  // [13] F flag: 1 on final payload wave (header=0)
  // Header layout:
  //   [12:5] cmd (LSBs)
  //   [4:2]  bankgroup (LSBs)
  //   [1:0]  bank (LSBs)
  // Payload layout:
  //   [12:9] reg_id (LSBs)
  //   [8:0]  operand (LSBs)
  localparam int TC_WAVE_W = 15;
  typedef logic [TC_WAVE_W-1:0] action_wave_t;
endpackage
