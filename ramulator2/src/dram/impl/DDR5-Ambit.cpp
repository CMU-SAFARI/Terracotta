#include "dram/dram.h"
#include "dram/lambdas.h"

namespace Ramulator {

class DDR5Ambit : public IDRAM, public Implementation {
  RAMULATOR_REGISTER_IMPLEMENTATION(IDRAM, DDR5Ambit, "DDR5Ambit", "DDR5 Ambit Device Model")
  private:
    int m_RH_radius = -1;


  public:
    inline static const std::map<std::string, Organization> org_presets = {
      //   name               density   DQ   Ch Ra Bg Ba   Ro     Co
      {"DDR5_8Gb_x4",         {8<<10,   4,  {1, 1, 8, 2, 1<<16, 1<<11}}},
      {"DDR5_8Gb_x8",         {8<<10,   8,  {1, 1, 8, 2, 1<<16, 1<<10}}},
      {"DDR5_8Gb_x16",        {8<<10,   16, {1, 1, 4, 2, 1<<16, 1<<10}}},
      {"DDR5_16Gb_x4",        {16<<10,  4,  {1, 1, 8, 4, 1<<16, 1<<11}}},
      {"DDR5_16Gb_x8",        {16<<10,  8,  {1, 1, 8, 4, 1<<16, 1<<10}}},
      {"DDR5_16Gb_x16",       {16<<10,  16, {1, 1, 4, 4, 1<<16, 1<<10}}},
      {"DDR5_32Gb_x4",        {32<<10,  4,  {1, 1, 8, 4, 1<<17, 1<<11}}},
      {"DDR5_32Gb_x8",        {32<<10,  8,  {1, 1, 8, 4, 1<<17, 1<<10}}},
      {"DDR5_32Gb_x16",       {32<<10,  16, {1, 1, 4, 4, 1<<17, 1<<10}}},
      // {"DDR5_64Gb_x4",  {64<<10,  4,  {1, 1, 8, 4, 1<<18, 1<<11}}},
      // {"DDR5_64Gb_x8",  {64<<10,  8,  {1, 1, 8, 4, 1<<18, 1<<10}}},
      // {"DDR5_64Gb_x16", {64<<10,  16, {1, 1, 4, 4, 1<<18, 1<<10}}},
    };

    inline static const std::map<std::string, std::vector<int>> timing_presets = {
      //   name         rate   nBL  nCL nRCD   nRP  nRAS   nRC   nWR  nRTP nCWL nPPD nCCDS nCCDS_WR nCCDS_WTR nCCDL nCCDL_WR nCCDL_WTR nRRDS nRRDL nFAW nRFC1 nRFC2 nRFCsb nREFI nREFSBRD nRFM1 nRFM2 nRFMsb nDRFMab nDRFMsb nCS, tCK_ps
      {"DDR5_3200AN",  {3200,   8,  24,  24,   24,   52,   75,   48,   12,  22,  2,    8,     8,     22+8+4,    8,     16,    22+8+16,   8,   -1,   -1,  -1,   -1,   -1,    -1,     30,    -1,   -1,   -1,     -1,     -1,    2,   625}},
      {"DDR5_3200BN",  {3200,   8,  26,  26,   26,   52,   77,   48,   12,  24,  2,    8,     8,     24+8+4,    8,     16,    24+8+16,   8,   -1,   -1,  -1,   -1,   -1,    -1,     30,    -1,   -1,   -1,     -1,     -1,    2,   625}},
      {"DDR5_3200C",   {3200,   8,  28,  28,   28,   52,   79,   48,   12,  26,  2,    8,     8,     26+8+4,    8,     16,    26+8+16,   8,   -1,   -1,  -1,   -1,   -1,    -1,     30,    -1,   -1,   -1,     -1,     -1,    2,   625}},
    };

    inline static const std::map<std::string, std::vector<double>> voltage_presets = {
      //   name          VDD      VPP
      {"Default",       {1.1,     1.8}},
    };

    inline static const std::map<std::string, std::vector<double>> current_presets = {
      // name           IDD0  IDD2N   IDD3N   IDD4R   IDD4W   IDD5B   IPP0  IPP2N  IPP3N  IPP4R  IPP4W  IPP5B
      {"Default",       {60,   50,     55,     145,    145,    362,     3,    3,     3,     3,     3,     48}},
    };
  /************************************************
   *                Organization
   ***********************************************/   
    const int m_internal_prefetch_size = 16;

    inline static constexpr ImplDef m_levels = {
      "channel", "rank", "bankgroup", "bank", "row", "column",    
    };


  /************************************************
   *             Requests & Commands
   ***********************************************/
    inline static constexpr ImplDef m_commands = {
      "ACT", 
      "PRE", "PREA", "PREsb",
      "RD",  "WR",  "RDA",  "WRA",
      "REFab",  "REFsb", "REFab_end", "REFsb_end",
      "RFMab",  "RFMsb", "RFMab_end", "RFMsb_end",
      "DRFMab", "DRFMsb", "DRFMab_end", "DRFMsb_end",
    };

    inline static const ImplLUT m_command_scopes = LUT (
      m_commands, m_levels, {
        {"ACT",   "row"},
        {"PRE",   "bank"},   {"PREA",   "rank"},   {"PREsb", "bank"},
        {"RD",    "column"}, {"WR",     "column"}, {"RDA",   "column"}, {"WRA",   "column"},
        {"REFab",  "rank"},  {"REFsb",  "bank"}, {"REFab_end",  "rank"},  {"REFsb_end",  "bank"},
        {"RFMab",  "rank"},  {"RFMsb",  "bank"}, {"RFMab_end",  "rank"},  {"RFMsb_end",  "bank"},
        {"DRFMab", "rank"},  {"DRFMsb", "bank"}, {"DRFMab_end", "rank"},  {"DRFMsb_end", "bank"},
      }
    );

    inline static const ImplLUT m_command_meta = LUT<DRAMCommandMeta> (
      m_commands, {
                      // open?   close?   access?  refresh?
        {"ACT",         {true,   false,   false,   false}},
        {"PRE",         {false,  true,    false,   false}},
        {"PREA",        {false,  true,    false,   false}},
        {"PREsb",       {false,  true,    false,   false}},
        {"RD",          {false,  false,   true,    false}},
        {"WR",          {false,  false,   true,    false}},
        {"RDA",         {false,  true,    true,    false}},
        {"WRA",         {false,  true,    true,    false}},
        {"REFab",       {false,  false,   false,   true }},
        {"REFsb",       {false,  false,   false,   true }},
        {"REFab_end",   {false,  true,    false,   false}},
        {"REFsb_end",   {false,  true,    false,   false}},
        {"RFMab",       {false,  false,   false,   true }},
        {"RFMsb",       {false,  false,   false,   true }},
        {"RFMab_end",   {false,  true,    false,   false}},
        {"RFMsb_end",   {false,  true,    false,   false}},
        {"DRFMab",      {false,  false,   false,   true }},
        {"DRFMsb",      {false,  false,   false,   true }},
        {"DRFMab_end",  {false,  true,    false,   false}},
        {"DRFMsb_end",  {false,  true,    false,   false}},
      }
    );

    inline static constexpr ImplDef m_requests = {
      "read", "write", 
      "all-bank-refresh", "same-bank-refresh", 
      "rfm", "same-bank-rfm",
      "directed-rfm", "same-bank-directed-rfm",
      "open-row", "close-row", 
      "rowclone", "not", "andor", "xorxnor", "nandnor", 
    };

    inline static const ImplLUT m_request_translations = LUT (
      m_requests, m_commands, {
        {"read", "RD"}, {"write", "WR"}, 
        {"all-bank-refresh", "REFab"}, {"same-bank-refresh", "REFsb"}, 
        {"rfm", "RFMab"}, {"same-bank-rfm", "RFMsb"}, 
        {"directed-rfm", "DRFMab"}, {"same-bank-directed-rfm", "DRFMsb"}, 
        {"open-row", "ACT"}, {"close-row", "PRE"},
        {"rowclone", "PRE"}, {"not", "PRE"}, {"andor", "PRE"}, {"xorxnor", "PRE"}, {"nandnor", "PRE"},
      }
    );

  /************************************************
   *                   Timing
   ***********************************************/
    inline static constexpr ImplDef m_timings = {
      "rate", 
      "nBL", "nCL", "nRCD", "nRP", "nRAS", "nRC", "nWR", "nRTP", "nCWL",
      "nPPD",
      "nCCDS", "nCCDS_WR", "nCCDS_WTR", 
      "nCCDL", "nCCDL_WR", "nCCDL_WTR", 
      "nRRDS", "nRRDL",
      "nFAW",
      "nRFC1", "nRFC2", "nRFCsb", "nREFI", "nREFSBRD",
      "nRFM1", "nRFM2", "nRFMsb", 
      "nDRFMab", "nDRFMsb", 
      "nCS",
      "tCK_ps"
    };
   
  /************************************************
   *                   Power
   ***********************************************/
    inline static constexpr ImplDef m_voltages = {
      "VDD", "VPP"
    };
    
    inline static constexpr ImplDef m_currents = {
      "IDD0", "IDD2N", "IDD3N", "IDD4R", "IDD4W", "IDD5B",
      "IPP0", "IPP2N", "IPP3N", "IPP4R", "IPP4W", "IPP5B"
    };

    inline static constexpr ImplDef m_cmds_counted = {
      "ACT", "PRE", "RD", "WR", "REF", "RFM"
    };

    inline static constexpr ImplDef m_reqs_counted = {
      "rowclone", "not", "andor", "xorxnor", "nandnor",
    };

  /************************************************
   *                 Node States
   ***********************************************/
    inline static constexpr ImplDef m_states = {
       "Opened", "Closed", "PowerUp", "N/A", "Refreshing",
       "Multi-Opened",
    };

    inline static const ImplLUT m_init_states = LUT (
      m_levels, m_states, {
        {"channel",   "N/A"}, 
        {"rank",      "PowerUp"},
        {"bankgroup", "N/A"},
        {"bank",      "Closed"},
        {"row",       "Closed"},
        {"column",    "N/A"},
      }
    );

  public:
    struct Node : public DRAMNodeBase<DDR5Ambit> {
      Node(DDR5Ambit* dram, Node* parent, int level, int id) : DRAMNodeBase<DDR5Ambit>(dram, parent, level, id) {};

      // timing update for Ambit requests
      void update_timing_ambit(int command, const AddrVec_t& addr_vec, Clk_t clk) {
        /************************************************
         *         Update Sibling Node Timing
         ***********************************************/
        // m_ambit_timing_cons contains an entry at m_level, command, choose that else choose it from m_spec->m_timing_cons
        auto* dram = static_cast<DDR5Ambit*>(m_spec);
        const auto& timing_cons = dram->m_ambit_timing_cons[m_level][command].size() ? dram->m_ambit_timing_cons[m_level][command] : dram->m_timing_cons[m_level][command];

        if (m_node_id != addr_vec[m_level] && addr_vec[m_level] != -1) {
          for (const auto& t : timing_cons) {
            if (!t.sibling) {
              // not sibling timing parameter
              continue; 
            }

            // update earliest schedulable time of every command
            Clk_t future = clk + t.val;
            m_cmd_ready_clk[t.cmd] = std::max(m_cmd_ready_clk[t.cmd], future); 
          }
          // stop recursion
          return;
        }

        /************************************************
         *          Update Target Node Timing
         ***********************************************/
        // Update history
        if (m_cmd_history[command].size()) {
          m_cmd_history[command].pop_back();
          m_cmd_history[command].push_front(clk); 
        }

        for (const auto& t : timing_cons) {
          if (t.sibling) {
            continue; 
          }

          // Get the oldest history
          Clk_t past = m_cmd_history[command][t.window-1];
          if (past < 0) {
            // not enough history
            continue; 
          }

          // update earliest schedulable time of every command
          Clk_t future = past + t.val;
          m_cmd_ready_clk[t.cmd] = std::max(m_cmd_ready_clk[t.cmd], future);
        }

        if (!m_child_nodes.size()) {
          // stop recursion: updated all levels
          return; 
        }

        // recursively update all of my children
        for (auto child : m_child_nodes) {
          child->update_timing_ambit(command, addr_vec, clk);
        }
      };

      // state update for Rowclone requests
      void update_states_ambit(ReqBuffer::iterator req_it, Clk_t clk) {
        int child_id = req_it->addr_vec[m_level + 1];

        FuncMatrix<RActionFunc_t> m_req_actions;

        if (req_it->type_id == Request::Type::RowClone) {
          m_req_actions = m_spec->m_rowclone_actions;
        } else if (req_it->type_id == Request::Type::NOT) {
          m_req_actions = m_spec->m_not_actions;
        } else if (req_it->type_id == Request::Type::AND_OR) {
          m_req_actions = m_spec->m_andor_actions;
        } else if (req_it->type_id == Request::Type::XOR_XNOR) {
          m_req_actions = m_spec->m_xorxnor_actions;
        } else if (req_it->type_id == Request::Type::NAND_NOR) {
          m_req_actions = m_spec->m_nandnor_actions;
        } else {
          assert(false && "Invalid request type for state update");
        }

        if (m_req_actions[m_level][req_it->command]) {
          // update the state machine at this level
          m_req_actions[m_level][req_it->command](this, req_it, clk);
        }

        if (m_level == m_spec->m_command_scopes[req_it->command] || !m_child_nodes.size()) {
          // stop recursion: updated all levels
          return; 
        }

        // recursively update child nodes (we do not need to change this because the row address is all that is different)
        if (child_id == -1) {
          for (auto child : m_child_nodes) {
            child->update_states_ambit(req_it, clk);
          }
        } else {
          m_child_nodes[child_id]->update_states_ambit(req_it, clk);
        }
      };

      void update_powers_ambit(ReqBuffer::iterator req_it, Clk_t clk) {
        if (!m_spec->m_drampower_enable)
          return;

        int child_id = req_it->addr_vec[m_level + 1];

        int request_type = req_it->type_id;

        if (m_spec->m_ambit_powers[m_level][request_type]) {
          // update the power model at this level
          m_spec->m_ambit_powers[m_level][request_type](static_cast<NodeType*>(this), req_it, clk);
        }
        if (!m_child_nodes.size()) {
          // stop recursion: updated all levels
          return; 
        }
        // recursively update child nodes
        if (child_id == -1) {
          for (auto child : m_child_nodes) {
            child->update_powers_ambit(req_it, clk);
          }
        } else {
          m_child_nodes[child_id]->update_powers_ambit(req_it, clk);
        }
      };

      int get_ambit_preq_command(ReqBuffer::iterator req_it, Clk_t clk)
      {
        int child_id = req_it->addr_vec[m_level + 1];

        FuncMatrix<RPreqFunc_t> m_req_preqs;

        if (req_it->type_id == Request::Type::RowClone) {
          m_req_preqs = m_spec->m_rowclone_preqs;
        } else if (req_it->type_id == Request::Type::NOT) {
          m_req_preqs = m_spec->m_not_preqs;
        } else if (req_it->type_id == Request::Type::AND_OR) {
          m_req_preqs = m_spec->m_andor_preqs;
        } else if (req_it->type_id == Request::Type::XOR_XNOR) {
          m_req_preqs = m_spec->m_xorxnor_preqs;
        } else if (req_it->type_id == Request::Type::NAND_NOR) {
          m_req_preqs = m_spec->m_nandnor_preqs;
        } else {
          assert(false && "Invalid request type for state update");
        }

        if (m_req_preqs[m_level][req_it->final_command])
        {
          int preq_cmd = m_req_preqs[m_level][req_it->final_command](this, req_it, clk);
          if (preq_cmd != -1)
          {
            // stop recursion: there is a prerequisite at this level
            return preq_cmd;
          }
        }

        if (!m_child_nodes.size())
        {
          // stop recursion: there were no prerequisites at any level
          return req_it->final_command;
        }

        // recursively check child nodes
        return m_child_nodes[child_id]->get_ambit_preq_command(req_it, clk);
      }
    };
    std::vector<Node*> m_channels;
    
    FuncMatrix<ActionFunc_t<Node>>  m_actions;
    FuncMatrix<PreqFunc_t<Node>>    m_preqs;
    FuncMatrix<RowhitFunc_t<Node>>  m_rowhits;
    FuncMatrix<RowopenFunc_t<Node>> m_rowopens;
    FuncMatrix<PowerFunc_t<Node>>   m_powers;

    using AmbitPowerFunc_t = std::function<void (Node* node, ReqBuffer::iterator req_it, Clk_t clk)>;
    FuncMatrix<AmbitPowerFunc_t>   m_ambit_powers;

    double s_total_rfm_energy = 0.0;

    std::vector<size_t> s_total_rfm_cycles;

    using RPreqFunc_t = std::function<int (Node* node, ReqBuffer::iterator req_it, Clk_t clk)>;
    FuncMatrix<RPreqFunc_t> m_rowclone_preqs;
    FuncMatrix<RPreqFunc_t> m_not_preqs;
    FuncMatrix<RPreqFunc_t> m_andor_preqs;
    FuncMatrix<RPreqFunc_t> m_xorxnor_preqs;
    FuncMatrix<RPreqFunc_t> m_nandnor_preqs;

    using RActionFunc_t = std::function<void (Node* node, ReqBuffer::iterator req_it, Clk_t clk)>;
    FuncMatrix<RActionFunc_t> m_rowclone_actions;
    FuncMatrix<RActionFunc_t> m_not_actions;
    FuncMatrix<RActionFunc_t> m_andor_actions;
    FuncMatrix<RActionFunc_t> m_xorxnor_actions;
    FuncMatrix<RActionFunc_t> m_nandnor_actions;

  /************************************************
   *                 RFM Related
   ***********************************************/
  public:
    int m_BRC = 2;

    TimingCons m_rowclone_timing_cons;
    TimingCons m_not_timing_cons;
    TimingCons m_ambit_timing_cons;

  public:
    void tick() override {
      m_clk++;

      // Check if there is any future action at this cycle
      for (int i = m_future_actions.size() - 1; i >= 0; i--) {
        auto& future_action = m_future_actions[i];
        if (future_action.clk == m_clk) {
          handle_future_action(future_action.cmd, future_action.addr_vec);
          m_future_actions.erase(m_future_actions.begin() + i);
        }
      }
    };

    void init() override {
      RAMULATOR_DECLARE_SPECS();
      set_organization();
      set_timing_vals();

      set_actions();
      set_preqs();
      set_rowhits();
      set_rowopens();
      set_powers();
      
      create_nodes();
    };

    void issue_command(int command, const AddrVec_t& addr_vec) override {
      int channel_id = addr_vec[m_levels["channel"]];
      m_channels[channel_id]->update_timing(command, addr_vec, m_clk);
      m_channels[channel_id]->update_powers(command, addr_vec, m_clk);
      m_channels[channel_id]->update_states(command, addr_vec, m_clk);
    
      // Check if the command requires future action
      check_future_action(command, addr_vec);
    };

    void issue_command(ReqBuffer::iterator& req_it) override {
      int channel_id = req_it->addr_vec[m_levels["channel"]];
      int command = req_it->command;
      AddrVec_t& addr_vec = req_it->addr_vec;

      if (req_it->type_id == Request::Type::RowClone || 
          req_it->type_id == Request::Type::NOT || 
          req_it->type_id == Request::Type::AND_OR || 
          req_it->type_id == Request::Type::XOR_XNOR || 
          req_it->type_id == Request::Type::NAND_NOR) {
        m_channels[channel_id]->update_timing_ambit(command, addr_vec, m_clk);
        m_channels[channel_id]->update_states_ambit(req_it, m_clk);
        if (req_it->type_id == Request::Type::RowClone && command == req_it->final_command)
          req_it->is_done = true;
        else if (req_it->type_id == Request::Type::NOT && req_it->step_id == 2)
          req_it->is_done = true;
        else if (req_it->type_id == Request::Type::AND_OR && req_it->step_id == 4)
          req_it->is_done = true;
        else if (req_it->type_id == Request::Type::XOR_XNOR && req_it->step_id == 7)
          req_it->is_done = true;
        else if (req_it->type_id == Request::Type::NAND_NOR && req_it->step_id == 5)
          req_it->is_done = true;

        if (req_it->is_done)
          m_channels[channel_id]->update_powers_ambit(req_it, m_clk);

      } else {
        m_channels[channel_id]->update_timing(command, addr_vec, m_clk);
        m_channels[channel_id]->update_states(command, addr_vec, m_clk);
        if (command == req_it->final_command)
          req_it->is_done = true;
      }

      m_channels[channel_id]->update_powers(command, addr_vec, m_clk);

      // Check if the command requires future action
      check_future_action(command, addr_vec);
    }

    void check_future_action(int command, const AddrVec_t& addr_vec) {
      switch (command) {
        case m_commands("REFab"):
          m_future_actions.push_back({command, addr_vec, m_clk + m_timing_vals("nRFC1") - 1});
          break;
        case m_commands("REFsb"):
          m_future_actions.push_back({command, addr_vec, m_clk + m_timing_vals("nRFCsb") - 1});
          break;
        case m_commands("RFMab"):
          m_future_actions.push_back({command, addr_vec, m_clk + m_timing_vals("nRFM1") - 1});
          break;
        case m_commands("RFMsb"):
          m_future_actions.push_back({command, addr_vec, m_clk + m_timing_vals("nRFMsb") - 1});
          break;
        case m_commands("DRFMab"):
          m_future_actions.push_back({command, addr_vec, m_clk + m_timing_vals("nDRFMab") - 1});
          break;
        case m_commands("DRFMsb"):
          m_future_actions.push_back({command, addr_vec, m_clk + m_timing_vals("nDRFMsb") - 1});
          break;
        default:
          // Other commands do not require future actions
          break;
      }
    }

    void handle_future_action(int command, const AddrVec_t& addr_vec) {
      int channel_id = addr_vec[m_levels["channel"]];
      switch (command) {
        case m_commands("REFab"):
          m_channels[channel_id]->update_powers(m_commands("REFab_end"), addr_vec, m_clk);
          m_channels[channel_id]->update_states(m_commands("REFab_end"), addr_vec, m_clk);
          break;
        case m_commands("REFsb"):
          m_channels[channel_id]->update_powers(m_commands("REFsb_end"), addr_vec, m_clk);
          m_channels[channel_id]->update_states(m_commands("REFsb_end"), addr_vec, m_clk);
          break;
        case m_commands("RFMab"):
          m_channels[channel_id]->update_powers(m_commands("RFMab_end"), addr_vec, m_clk);
          m_channels[channel_id]->update_states(m_commands("RFMab_end"), addr_vec, m_clk);
          break;
        case m_commands("RFMsb"):
          m_channels[channel_id]->update_powers(m_commands("RFMsb_end"), addr_vec, m_clk);
          m_channels[channel_id]->update_states(m_commands("RFMsb_end"), addr_vec, m_clk);
          break;
        case m_commands("DRFMab"):
          m_channels[channel_id]->update_powers(m_commands("DRFMab_end"), addr_vec, m_clk);
          m_channels[channel_id]->update_states(m_commands("DRFMab_end"), addr_vec, m_clk);
          break;
        case m_commands("DRFMsb"):
          m_channels[channel_id]->update_powers(m_commands("DRFMsb_end"), addr_vec, m_clk);
          m_channels[channel_id]->update_states(m_commands("DRFMsb_end"), addr_vec, m_clk);
          break;
        default:
          // Other commands do not require future actions
          break;
      }
    };

    int get_preq_command(int command, const AddrVec_t& addr_vec) override {
      int channel_id = addr_vec[m_levels["channel"]];
      return m_channels[channel_id]->get_preq_command(command, addr_vec, m_clk);
    };

    void set_preq_command(ReqBuffer::iterator req_it) override {
      int channel_id = req_it->addr_vec[m_levels["channel"]];
      
      if (req_it->type_id != Request::Type::Read && req_it->type_id != Request::Type::Write)
        req_it->command = m_channels[channel_id]->get_ambit_preq_command(req_it, m_clk);
      else
        req_it->command = m_channels[channel_id]->get_preq_command(req_it->final_command, req_it->addr_vec, m_clk);
    };

    bool check_ready(int command, const AddrVec_t& addr_vec) override {
      int channel_id = addr_vec[m_levels["channel"]];
      return m_channels[channel_id]->check_ready(command, addr_vec, m_clk);
    };

    bool check_rowbuffer_hit(int command, const AddrVec_t& addr_vec) override {
      int channel_id = addr_vec[m_levels["channel"]];
      return m_channels[channel_id]->check_rowbuffer_hit(command, addr_vec, m_clk);
    };
    
    bool check_node_open(int command, const AddrVec_t& addr_vec) override {
      int channel_id = addr_vec[m_levels["channel"]];
      return m_channels[channel_id]->check_node_open(command, addr_vec, m_clk);
    };

  private:
    void set_organization() {
      // Channel width
      m_channel_width = param_group("org").param<int>("channel_width").default_val(32);

      // Organization
      m_organization.count.resize(m_levels.size(), -1);

      // Load organization preset if provided
      if (auto preset_name = param_group("org").param<std::string>("preset").optional()) {
        if (org_presets.count(*preset_name) > 0) {
          m_organization = org_presets.at(*preset_name);
        } else {
          throw ConfigurationError("Unrecognized organization preset \"{}\" in {}!", *preset_name, get_name());
        }
      }

      // Override the preset with any provided settings
      if (auto dq = param_group("org").param<int>("dq").optional()) {
        m_organization.dq = *dq;
      }

      for (int i = 0; i < m_levels.size(); i++){
        auto level_name = m_levels(i);
        if (auto sz = param_group("org").param<int>(level_name).optional()) {
          m_organization.count[i] = *sz;
        }
      }

      if (auto density = param_group("org").param<int>("density").optional()) {
        m_organization.density = *density;
      }

      // Sanity check: is the calculated chip density the same as the provided one?
      size_t _density = size_t(m_organization.count[m_levels["bankgroup"]]) *
                        size_t(m_organization.count[m_levels["bank"]]) *
                        size_t(m_organization.count[m_levels["row"]]) *
                        size_t(m_organization.count[m_levels["column"]]) *
                        size_t(m_organization.dq);
      _density >>= 20;
      if (m_organization.density != _density) {
        throw ConfigurationError(
            "Calculated {} chip density {} Mb does not equal the provided density {} Mb!", 
            get_name(),
            _density, 
            m_organization.density
        );
      }
      int num_channels = m_organization.count[m_levels["channel"]];
      int num_ranks = m_organization.count[m_levels["rank"]];
      s_total_rfm_cycles.resize(num_channels * num_ranks, 0);

      for (int r = 0; r < num_channels * num_ranks; r++) {
        register_stat(s_total_rfm_cycles[r]).name("total_rfm_cycles_rank{}", r);
      }
    };

    void set_timing_vals() {
      m_timing_vals.resize(m_timings.size(), -1);

      // Load timing preset if provided
      bool preset_provided = false;
      if (auto preset_name = param_group("timing").param<std::string>("preset").optional()) {
        if (timing_presets.count(*preset_name) > 0) {
          m_timing_vals = timing_presets.at(*preset_name);
          preset_provided = true;
        } else {
          throw ConfigurationError("Unrecognized timing preset \"{}\" in {}!", *preset_name, get_name());
        }
      }

      // Check for rate (in MT/s), and if provided, calculate and set tCK (in picosecond)
      if (auto dq = param_group("timing").param<int>("rate").optional()) {
        if (preset_provided) {
          throw ConfigurationError("Cannot change the transfer rate of {} when using a speed preset !", get_name());
        }
        m_timing_vals("rate") = *dq;
      }
      int tCK_ps = 1E6 / (m_timing_vals("rate") / 2);
      m_timing_vals("tCK_ps") = tCK_ps;

      // Load the organization specific timings
      int dq_id = [](int dq) -> int {
        switch (dq) {
          case 4:  return 0;
          case 8:  return 1;
          case 16: return 2;
          default: return -1;
        }
      }(m_organization.dq);

      int rate_id = [](int rate) -> int {
        switch (rate) {
          case 3200:  return 0;
          default:    return -1;
        }
      }(m_timing_vals("rate"));

      constexpr int nRRDL_TABLE[3][1] = {
      // 3200  
        { 5, },  // x4
        { 5, },  // x8
        { 5, },  // x16
      };
      constexpr int nFAW_TABLE[3][1] = {
      // 3200  
        { 40, },  // x4
        { 32, },  // x8
        { 32, },  // x16
      };

      if (dq_id != -1 && rate_id != -1) {
        m_timing_vals("nRRDL") = nRRDL_TABLE[dq_id][rate_id];
        m_timing_vals("nFAW")  = nFAW_TABLE [dq_id][rate_id];
      }

      // tCCD_L_WR2 (with RMW) table
      constexpr int nCCD_L_WR2_TABLE[1] = {
      // 3200  
        32,
      };
      if (dq_id == 0) {
        m_timing_vals("nCCDL_WR") = nCCD_L_WR2_TABLE[rate_id];
      }

      // Refresh timings
      // tRFC table (unit is nanosecond!)
      constexpr int tRFC_TABLE[2][3] = {
      //  8Gb   16Gb  32Gb  
        { 195,  295,  410 }, // Normal refresh (tRFC1)
        { 130,  160,  220 }, // FGR 2x (tRFC2)
      };

      // tRFCsb table (unit is nanosecond!)
      constexpr int tRFCsb_TABLE[1][3] = {
      //  8Gb   16Gb  32Gb  
        { 115,  130,  190 }, // Normal refresh (tRFC1)
      };

      // tREFI(base) table (unit is nanosecond!)
      constexpr int tREFI_BASE = 3900;
      int density_id = [](int density_Mb) -> int { 
        switch (density_Mb) {
          case 8192:  return 0;
          case 16384: return 1;
          case 32768: return 2;
          default:    return -1;
        }
      }(m_organization.density);

      m_RH_radius = param<int>("RH_radius").desc("The number of rows to refresh on each side").default_val(2);

      m_timing_vals("nRFC1")  = JEDEC_rounding_DDR5(tRFC_TABLE[0][density_id], tCK_ps);
      m_timing_vals("nRFC2")  = JEDEC_rounding_DDR5(tRFC_TABLE[1][density_id], tCK_ps);
      m_timing_vals("nRFCsb") = JEDEC_rounding_DDR5(tRFCsb_TABLE[0][density_id], tCK_ps);
      m_timing_vals("nREFI")  = JEDEC_rounding_DDR5(tREFI_BASE, tCK_ps);

      m_timing_vals("nRFM1")  = m_timing_vals("nRFC1");
      m_timing_vals("nRFM2")  = m_timing_vals("nRFC2");
      m_timing_vals("nRFMsb") = m_timing_vals("nRFCsb") * m_RH_radius;

      // tRRF table (unit is nanosecond!)
      constexpr int tRRFsb_TABLE[2][3] = {
      //  8Gb 16Gb 32Gb  
        { 70,  70,  70 }, // tRRFab
        { 60,  60,  60 }, // tRRFsb
      };
      m_BRC = param_group("RFM").param<int>("BRC").default_val(2);
      m_timing_vals("nDRFMab") = 2 * m_BRC * JEDEC_rounding_DDR5(tRRFsb_TABLE[0][density_id], tCK_ps);
      m_timing_vals("nDRFMsb") = 2 * m_BRC * JEDEC_rounding_DDR5(tRRFsb_TABLE[1][density_id], tCK_ps);


      // Overwrite timing parameters with any user-provided value
      // Rate and tCK should not be overwritten
      for (int i = 1; i < m_timings.size() - 1; i++) {
        auto timing_name = std::string(m_timings(i));

        if (auto provided_timing = param_group("timing").param<int>(timing_name).optional()) {
          // Check if the user specifies in the number of cycles (e.g., nRCD)
          m_timing_vals(i) = *provided_timing;
        } else if (auto provided_timing = param_group("timing").param<float>(timing_name.replace(0, 1, "t")).optional()) {
          // Check if the user specifies in nanoseconds (e.g., tRCD)
          m_timing_vals(i) = JEDEC_rounding_DDR5(*provided_timing, tCK_ps);
        }
      }

      // Check if there is any uninitialized timings
      for (int i = 0; i < m_timing_vals.size(); i++) {
        if (m_timing_vals(i) == -1) {
          throw ConfigurationError("In \"{}\", timing {} is not specified!", get_name(), m_timings(i));
        }
      }      

      // Set read latency
      m_read_latency = m_timing_vals("nCL") + m_timing_vals("nBL");

      // Populate the timing constraints
      #define V(timing) (m_timing_vals(timing))
      auto all_commands = std::vector<std::string_view>(m_commands.begin(), m_commands.end());

      m_ambit_timing_cons.resize(m_levels.size(), std::vector<std::vector<TimingConsEntry>>(m_commands.size()));

      // populate the initializer
      std::vector<TimingConsInitializer> initializer = {
        /*** Channel ***/ 
        // Two-Cycle Commands
        {.level = "channel", .preceding = {"ACT"}, .following = all_commands, .latency = 2},

        /*** Rank (or different BankGroup) ***/ 
        /// RAS <-> RAS
        {.level = "rank", .preceding = {"ACT"}, .following = {"ACT"}, .latency = V("nRRDS")},  
        {.level = "rank", .preceding = {"ACT"}, .following = {"PREA"}, .latency = V("nRAS")},
        /// RAS <-> REF
        {.level = "rank", .preceding = {"ACT"}, .following = {"REFab", "RFMab", "DRFMab"}, .latency = V("nRC")},
        {.level = "rank", .preceding = {"PRE"}, .following = {"REFab", "RFMab", "DRFMab"}, .latency = V("nRP")},
        
        /*** Same Bank Group ***/ 
        /// RAS <-> RAS
        {.level = "bankgroup", .preceding = {"ACT"}, .following = {"ACT"}, .latency = V("nRRDL")},

        // Bank
        {.level = "bank", .preceding = {"ACT"}, .following = {"ACT"}, .latency = V("nRAS")},
        {.level = "bank", .preceding = {"ACT"}, .following = {"PRE", "PREsb"}, .latency = V("nRAS")},
        {.level = "bank", .preceding = {"PRE"}, .following = {"ACT", "REFsb", "RFMsb", "DRFMsb"}, .latency = V("nRP")},
      };

      // Populate m_ambit_timing_cons
      for (const auto& ts : initializer) {
        int level = m_levels(ts.level);
        for (auto p_cmd_str : ts.preceding) {
          int p_cmd = m_commands(p_cmd_str);
          for (auto f_cmd_str : ts.following) {
            int f_cmd = m_commands(f_cmd_str);
            m_ambit_timing_cons[level][p_cmd].push_back({f_cmd, ts.latency, ts.window, ts.is_sibling});
          }
        }
      }

      populate_timingcons(this, {
          /*** Channel ***/ 
          // Two-Cycle Commands
          {.level = "channel", .preceding = {"ACT", "RD", "RDA", "WR", "WRA"}, .following = all_commands, .latency = 2},

          // CAS <-> CAS
          /// Data bus occupancy
          {.level = "channel", .preceding = {"RD", "RDA"}, .following = {"RD", "RDA"}, .latency = V("nBL")},
          {.level = "channel", .preceding = {"WR", "WRA"}, .following = {"WR", "WRA"}, .latency = V("nBL")},

          /*** Rank (or different BankGroup) ***/ 
          // CAS <-> CAS
          /// nCCDS is the minimal latency for column commands 
          {.level = "rank", .preceding = {"RD", "RDA"}, .following = {"RD", "RDA"}, .latency = V("nCCDS")},
          {.level = "rank", .preceding = {"WR", "WRA"}, .following = {"WR", "WRA"}, .latency = V("nCCDS_WR")},
          /// RD <-> WR, Minimum Read to Write, Assuming Read DQS Offset = 0, tRPST = 0.5, tWPRE = 2 tCK                          
          {.level = "rank", .preceding = {"RD", "RDA"}, .following = {"WR", "WRA"}, .latency = V("nCL") + V("nBL") + 2 - V("nCWL") + 2},   // nCCDS_RTW
          /// WR <-> RD, Minimum Read after Write
          {.level = "rank", .preceding = {"WR", "WRA"}, .following = {"RD", "RDA"}, .latency = V("nCCDS_WTR")},
          /// CAS <-> CAS between sibling ranks, nCS (rank switching) is needed for new DQS
          {.level = "rank", .preceding = {"RD", "RDA"}, .following = {"RD", "RDA", "WR", "WRA"}, .latency = V("nBL") + V("nCS"), .is_sibling = true},
          {.level = "rank", .preceding = {"WR", "WRA"}, .following = {"RD", "RDA"}, .latency = V("nCL")  + V("nBL") + V("nCS") - V("nCWL"), .is_sibling = true},
          /// CAS <-> PREab
          {.level = "rank", .preceding = {"RD"}, .following = {"PREA"}, .latency = V("nRTP")},
          {.level = "rank", .preceding = {"WR"}, .following = {"PREA"}, .latency = V("nCWL") + V("nBL") + V("nWR")},          
          /// RAS <-> RAS
          {.level = "rank", .preceding = {"ACT"}, .following = {"ACT"}, .latency = V("nRRDS")},          
          {.level = "rank", .preceding = {"ACT"}, .following = {"ACT"}, .latency = V("nFAW"), .window = 4},          
          {.level = "rank", .preceding = {"ACT"}, .following = {"PREA"}, .latency = V("nRAS")},          
          {.level = "rank", .preceding = {"PREA"}, .following = {"ACT"}, .latency = V("nRP")},          
          /// RAS <-> REF
          {.level = "rank", .preceding = {"ACT"}, .following = {"REFab", "RFMab", "DRFMab"}, .latency = V("nRC")},          
          {.level = "rank", .preceding = {"PRE", "PREsb"}, .following = {"REFab", "RFMab", "DRFMab"}, .latency = V("nRP")},          
          {.level = "rank", .preceding = {"PREA"}, .following = {"REFab", "RFMab", "DRFMab", "REFsb", "RFMsb", "DRFMsb"}, .latency = V("nRP")},          
          {.level = "rank", .preceding = {"RDA"}, .following = {"REFab", "RFMab", "DRFMab"}, .latency = V("nRP") + V("nRTP")},          
          {.level = "rank", .preceding = {"WRA"}, .following = {"REFab", "RFMab", "DRFMab"}, .latency = V("nCWL") + V("nBL") + V("nWR") + V("nRP")},          
          {.level = "rank", .preceding = {"REFab"}, .following = {"ACT", "PREA", "REFab", "RFMab", "DRFMab", "REFsb", "RFMsb", "DRFMsb"}, .latency = V("nRFC1")},          
          {.level = "rank", .preceding = {"RFMab"}, .following = {"ACT", "PREA", "REFab", "RFMab", "DRFMab", "REFsb", "RFMsb", "DRFMsb"}, .latency = V("nRFM1")},          
          {.level = "rank", .preceding = {"DRFMab"}, .following = {"ACT", "PREA", "REFab", "RFMab", "DRFMab", "REFsb", "RFMsb", "DRFMsb"}, .latency = V("nDRFMab")},          
          {.level = "rank", .preceding = {"REFsb"},  .following = {"PREA", "REFab", "RFMab", "DRFMab"}, .latency = V("nRFCsb")},  
          {.level = "rank", .preceding = {"RFMsb"},  .following = {"PREA", "REFab", "RFMab", "DRFMab"}, .latency = V("nRFMsb")},  
          {.level = "rank", .preceding = {"DRFMsb"}, .following = {"PREA", "REFab", "RFMab", "DRFMab"}, .latency = V("nDRFMsb")},  
          /*** Same Bank Group ***/ 
          /// CAS <-> CAS
          {.level = "bankgroup", .preceding = {"RD", "RDA"}, .following = {"RD", "RDA"}, .latency = V("nCCDL")},          
          {.level = "bankgroup", .preceding = {"WR", "WRA"}, .following = {"WR", "WRA"}, .latency = V("nCCDL_WR")},          
          {.level = "bankgroup", .preceding = {"WR", "WRA"}, .following = {"RD", "RDA"}, .latency = V("nCCDL_WTR")},
          /// RAS <-> RAS
          {.level = "bankgroup", .preceding = {"ACT"}, .following = {"ACT"}, .latency = V("nRRDL")},  

          /*** Bank ***/ 
          {.level = "bank", .preceding = {"ACT"}, .following = {"ACT", "REFsb", "RFMsb", "DRFMsb"}, .latency = V("nRC")},  
          {.level = "bank", .preceding = {"ACT"}, .following = {"RD", "RDA", "WR", "WRA"}, .latency = V("nRCD")},  
          {.level = "bank", .preceding = {"ACT"}, .following = {"PRE", "PREsb"}, .latency = V("nRAS")},  
          {.level = "bank", .preceding = {"PRE", "PREsb"}, .following = {"ACT", "REFsb", "RFMsb", "DRFMsb"}, .latency = V("nRP")},  
          {.level = "bank", .preceding = {"RD"},  .following = {"PRE", "PREsb"}, .latency = V("nRTP")},  
          {.level = "bank", .preceding = {"WR"},  .following = {"PRE", "PREsb"}, .latency = V("nCWL") + V("nBL") + V("nWR")},  
          {.level = "bank", .preceding = {"RDA"}, .following = {"ACT", "REFsb", "RFMsb", "DRFMsb"}, .latency = V("nRTP") + V("nRP")},  
          {.level = "bank", .preceding = {"WRA"}, .following = {"ACT", "REFsb", "RFMsb", "DRFMsb"}, .latency = V("nCWL") + V("nBL") + V("nWR") + V("nRP")},  
          {.level = "bank", .preceding = {"WR"},  .following = {"RDA"}, .latency = V("nCWL") + V("nBL") + V("nWR") - V("nRTP")},  

          /// Same-bank refresh/RFM timings. The timings of the bank in other BGs will be updated by action function
          {.level = "bank", .preceding = {"REFsb"},  .following = {"ACT", "REFsb", "RFMsb", "DRFMsb"}, .latency = V("nRFCsb")},  
          {.level = "bank", .preceding = {"RFMsb"},  .following = {"ACT", "REFsb", "RFMsb", "DRFMsb"}, .latency = V("nRFMsb")},  
          {.level = "bank", .preceding = {"DRFMsb"}, .following = {"ACT", "REFsb", "RFMsb", "DRFMsb"}, .latency = V("nDRFMsb")},  
        }
      );
      #undef V

    };

    static void action_AAP_ACT(Node* node, ReqBuffer::iterator req_it, Clk_t clk) {
      int cur_state = node->m_state;
        if (cur_state == m_states["Closed"]) {
          node->m_row_state[req_it->source1_addr_vec[m_levels["row"]]] = m_states["Opened"];
          node->m_state = m_states["Opened"];
        } else if (cur_state == m_states["Opened"]) {
          node->m_row_state[req_it->dest_addr_vec[m_levels["row"]]] = m_states["Opened"];
          node->m_state = m_states["Multi-Opened"];
        } else {
          spdlog::error("[Action::Bank::ACT] Invalid bank state for ACT command during AAP!");
          std::exit(-1);
        }
    };

    static void action_AAP_PRE(Node* node, ReqBuffer::iterator req_it, Clk_t clk) {
      int cur_state = node->m_state;
      if (cur_state == m_states["Multi-Opened"]) {
        node->m_row_state.clear();
        node->m_state = m_states["Closed"];
        req_it->step_id = req_it->step_id + 1;
      } else {
        spdlog::error("[Action::Bank::PRE] Invalid bank state for PRE command!");
        std::exit(-1);      
      }
    };

    void set_actions() {
      m_actions.resize(m_levels.size(), std::vector<ActionFunc_t<Node>>(m_commands.size()));
      m_rowclone_actions.resize(m_levels.size(), std::vector<RActionFunc_t>(m_commands.size()));
      m_not_actions.resize(m_levels.size(), std::vector<RActionFunc_t>(m_commands.size()));
      m_andor_actions.resize(m_levels.size(), std::vector<RActionFunc_t>(m_commands.size()));
      m_xorxnor_actions.resize(m_levels.size(), std::vector<RActionFunc_t>(m_commands.size()));
      m_nandnor_actions.resize(m_levels.size(), std::vector<RActionFunc_t>(m_commands.size()));

      // m_actions
      // Rank Actions
      m_actions[m_levels["rank"]][m_commands["PREA"]] = Lambdas::Action::Rank::PREab<DDR5Ambit>;
      m_actions[m_levels["rank"]][m_commands["REFab"]] = Lambdas::Action::Rank::REFab<DDR5Ambit>;
      m_actions[m_levels["rank"]][m_commands["REFab_end"]] = Lambdas::Action::Rank::REFab_end<DDR5Ambit>;
      m_actions[m_levels["rank"]][m_commands["RFMab"]] = Lambdas::Action::Rank::REFab<DDR5Ambit>;
      m_actions[m_levels["rank"]][m_commands["RFMab_end"]] = Lambdas::Action::Rank::REFab_end<DDR5Ambit>;
      m_actions[m_levels["rank"]][m_commands["DRFMab"]] = Lambdas::Action::Rank::REFab<DDR5Ambit>;
      m_actions[m_levels["rank"]][m_commands["DRFMab_end"]] = Lambdas::Action::Rank::REFab_end<DDR5Ambit>;
      
      // Same-Bank Actions.
      m_actions[m_levels["bankgroup"]][m_commands["PREsb"]] = Lambdas::Action::BankGroup::PREsb<DDR5Ambit>;

      // We call update_timing for the banks in other BGs here
      m_actions[m_levels["bankgroup"]][m_commands["REFsb"]]  = Lambdas::Action::BankGroup::REFsb<DDR5Ambit>;
      m_actions[m_levels["bankgroup"]][m_commands["REFsb_end"]]  = Lambdas::Action::BankGroup::REFsb_end<DDR5Ambit>;
      m_actions[m_levels["bankgroup"]][m_commands["RFMsb"]]  = Lambdas::Action::BankGroup::REFsb<DDR5Ambit>;
      m_actions[m_levels["bankgroup"]][m_commands["RFMsb_end"]]  = Lambdas::Action::BankGroup::REFsb_end<DDR5Ambit>;
      m_actions[m_levels["bankgroup"]][m_commands["DRFMsb"]] = Lambdas::Action::BankGroup::REFsb<DDR5Ambit>;
      m_actions[m_levels["bankgroup"]][m_commands["DRFMsb_end"]] = Lambdas::Action::BankGroup::REFsb_end<DDR5Ambit>;

      // Bank actions
      m_actions[m_levels["bank"]][m_commands["ACT"]] = Lambdas::Action::Bank::ACT<DDR5Ambit>;
      m_actions[m_levels["bank"]][m_commands["PRE"]] = Lambdas::Action::Bank::PRE<DDR5Ambit>;
      m_actions[m_levels["bank"]][m_commands["RDA"]] = Lambdas::Action::Bank::PRE<DDR5Ambit>;
      m_actions[m_levels["bank"]][m_commands["WRA"]] = Lambdas::Action::Bank::PRE<DDR5Ambit>;

      // m_rowclone_actions
      m_rowclone_actions[m_levels["bank"]][m_commands["ACT"]] = action_AAP_ACT;
      m_rowclone_actions[m_levels["bank"]][m_commands["PRE"]] = action_AAP_PRE;

      // m_not_actions
      m_not_actions[m_levels["bank"]][m_commands["ACT"]] = action_AAP_ACT;
      m_not_actions[m_levels["bank"]][m_commands["PRE"]] = action_AAP_PRE;

      // m_andor_actions
      m_andor_actions[m_levels["bank"]][m_commands["ACT"]] = action_AAP_ACT;
      m_andor_actions[m_levels["bank"]][m_commands["PRE"]] = action_AAP_PRE;

      // m_nand_nor_actions
      m_nandnor_actions[m_levels["bank"]][m_commands["ACT"]] = action_AAP_ACT;
      m_nandnor_actions[m_levels["bank"]][m_commands["PRE"]] = action_AAP_PRE;

      // m_xor_xnor_actions 
      m_xorxnor_actions[m_levels["bank"]][m_commands["ACT"]] = [](Node* node, ReqBuffer::iterator req_it, Clk_t clk) {
        int cur_state = node->m_state;
        int step_id = req_it->step_id;

        if (cur_state == m_states["Closed"]) {
          node->m_row_state[req_it->source1_addr_vec[m_levels["row"]]] = m_states["Opened"];
          node->m_state = m_states["Opened"];
        } else if (cur_state == m_states["Opened"] && (step_id != 3 || step_id != 4)) {
          node->m_row_state[req_it->dest_addr_vec[m_levels["row"]]] = m_states["Opened"];
          node->m_state = m_states["Multi-Opened"];
        } else {
          spdlog::error("[Action::Bank::ACT] Invalid bank state for ACT command during AAP!");
          std::exit(-1);
        }
      };

      m_xorxnor_actions[m_levels["bank"]][m_commands["PRE"]] = [](Node* node, ReqBuffer::iterator req_it, Clk_t clk) {
        int cur_state = node->m_state;
        int step_id  = req_it->step_id;
        if (cur_state == m_states["Multi-Opened"] && (step_id != 3 || step_id != 4)) {
          node->m_row_state.clear();
          node->m_state = m_states["Closed"];
        } else if (cur_state == m_states["Opened"] && (step_id == 3 || step_id == 4)) {
          node->m_row_state.clear();
          node->m_state = m_states["Closed"];
        } else {
          spdlog::error("[Action::Bank::PRE] Invalid bank state for PRE command!");
          std::exit(-1);      
        }
        req_it->step_id = req_it->step_id + 1;
      };
    };

    static int preq_AAP(Node* node, ReqBuffer::iterator req_it, Clk_t clk) {
      int command = req_it->final_command;

      AddrVec_t source_addr = req_it->source1_addr_vec;
      AddrVec_t dest_addr = req_it->dest_addr_vec;

      switch(node->m_state) {
        case m_states["Closed"]: return m_commands["ACT"];
        case m_states["Opened"]: {
          if (node->m_row_state.find(source_addr[m_levels["row"]]) != node->m_row_state.end())
            return m_commands["ACT"];
          else
            return m_commands["PRE"];
        }
        case m_states["Multi-Opened"]: return m_commands["PRE"];
        case m_states["Refreshing"]: return m_commands["ACT"];
        default:
          throw std::runtime_error("[Preq::Bank::ACT] Invalid bank state during RowClone!");
          std::exit(-1);
      }
    };

    void set_preqs() {
      m_preqs.resize(m_levels.size(), std::vector<PreqFunc_t<Node>>(m_commands.size()));
      m_rowclone_preqs.resize(m_levels.size(), std::vector<RPreqFunc_t>(m_commands.size()));
      m_not_preqs.resize(m_levels.size(), std::vector<RPreqFunc_t>(m_commands.size()));
      m_andor_preqs.resize(m_levels.size(), std::vector<RPreqFunc_t>(m_commands.size()));
      m_xorxnor_preqs.resize(m_levels.size(), std::vector<RPreqFunc_t>(m_commands.size()));
      m_nandnor_preqs.resize(m_levels.size(), std::vector<RPreqFunc_t>(m_commands.size()));

      // m_preqs
      // Rank Preqs
      m_preqs[m_levels["rank"]][m_commands["REFab"]]  = Lambdas::Preq::Rank::RequireAllBanksClosed<DDR5Ambit>;
      m_preqs[m_levels["rank"]][m_commands["RFMab"]]  = Lambdas::Preq::Rank::RequireAllBanksClosed<DDR5Ambit>;
      m_preqs[m_levels["rank"]][m_commands["DRFMab"]] = Lambdas::Preq::Rank::RequireAllBanksClosed<DDR5Ambit>;

      // Same-Bank Preqs.
      m_preqs[m_levels["rank"]][m_commands["REFsb"]]  = Lambdas::Preq::Rank::RequireSameBanksClosed<DDR5Ambit>;
      m_preqs[m_levels["rank"]][m_commands["RFMsb"]]  = Lambdas::Preq::Rank::RequireSameBanksClosed<DDR5Ambit>;
      m_preqs[m_levels["rank"]][m_commands["DRFMsb"]] = Lambdas::Preq::Rank::RequireSameBanksClosed<DDR5Ambit>;

      // Bank Preqs
      m_preqs[m_levels["bank"]][m_commands["RD"]] = Lambdas::Preq::Bank::RequireRowOpen<DDR5Ambit>;
      m_preqs[m_levels["bank"]][m_commands["WR"]] = Lambdas::Preq::Bank::RequireRowOpen<DDR5Ambit>;
      m_preqs[m_levels["bank"]][m_commands["ACT"]] = Lambdas::Preq::Bank::RequireRowOpen<DDR5Ambit>;
      m_preqs[m_levels["bank"]][m_commands["PRE"]] = Lambdas::Preq::Bank::RequireBankClosed<DDR5Ambit>;

      // m_rowclone_preqs
      m_rowclone_preqs[m_levels["bank"]][m_commands["PRE"]] = preq_AAP;

      // m_not_preqs
      m_not_preqs[m_levels["bank"]][m_commands["PRE"]] = preq_AAP;

      // m_andor_preqs
      m_andor_preqs[m_levels["bank"]][m_commands["PRE"]] = preq_AAP;

      // m_nandnor_preqs
      m_nandnor_preqs[m_levels["bank"]][m_commands["PRE"]] = preq_AAP;

      // m_xorxnor_preqs
      m_xorxnor_preqs[m_levels["bank"]][m_commands["PRE"]] = [](Node* node, ReqBuffer::iterator req_it, Clk_t clk) {
        int command = req_it->final_command;

        AddrVec_t source_addr = req_it->source1_addr_vec;
        AddrVec_t dest_addr = req_it->dest_addr_vec;
        int step_id  = req_it->step_id;

        if (step_id != 3 && step_id != 4) {
          switch(node->m_state) {
            case m_states["Closed"]: return m_commands["ACT"];
            case m_states["Opened"]: {
              if (node->m_row_state.find(source_addr[m_levels["row"]]) != node->m_row_state.end())
                return m_commands["ACT"];
              else
                return m_commands["PRE"];
            }
            case m_states["Multi-Opened"]: return m_commands["PRE"];
            case m_states["Refreshing"]: return m_commands["ACT"];
            default:
              throw std::runtime_error("[Preq::Bank::ACT] Invalid bank state during RowClone!");
              std::exit(-1);
          }
        } else {
          switch(node->m_state) {
            case m_states["Closed"]: return m_commands["ACT"];
            case m_states["Opened"]: {
              if (node->m_row_state.find(source_addr[m_levels["row"]]) != node->m_row_state.end())
                return m_commands["PRE"];
            }
            case m_states["Refreshing"]: return m_commands["ACT"];
            default:
              throw std::runtime_error("[Preq::Bank::ACT] Invalid bank state during RowClone!");
              std::exit(-1);
          }
        }
      };
    };

    void set_rowhits() {
      m_rowhits.resize(m_levels.size(), std::vector<RowhitFunc_t<Node>>(m_commands.size()));

      m_rowhits[m_levels["bank"]][m_commands["RD"]] = Lambdas::RowHit::Bank::RDWR<DDR5Ambit>;
      m_rowhits[m_levels["bank"]][m_commands["WR"]] = Lambdas::RowHit::Bank::RDWR<DDR5Ambit>;
    }


    void set_rowopens() {
      m_rowopens.resize(m_levels.size(), std::vector<RowhitFunc_t<Node>>(m_commands.size()));

      m_rowopens[m_levels["bank"]][m_commands["RD"]] = Lambdas::RowOpen::Bank::RDWR<DDR5Ambit>;
      m_rowopens[m_levels["bank"]][m_commands["WR"]] = Lambdas::RowOpen::Bank::RDWR<DDR5Ambit>;
    }

    void set_powers() {
      
      m_drampower_enable = param<bool>("drampower_enable").default_val(false);

      if (!m_drampower_enable)
        return;

      m_voltage_vals.resize(m_voltages.size(), -1);

      if (auto preset_name = param_group("voltage").param<std::string>("preset").optional()) {
        if (voltage_presets.count(*preset_name) > 0) {
          m_voltage_vals = voltage_presets.at(*preset_name);
        } else {
          throw ConfigurationError("Unrecognized voltage preset \"{}\" in {}!", *preset_name, get_name());
        }
      }

      m_current_vals.resize(m_currents.size(), -1);

      if (auto preset_name = param_group("current").param<std::string>("preset").optional()) {
        if (current_presets.count(*preset_name) > 0) {
          m_current_vals = current_presets.at(*preset_name);
        } else {
          throw ConfigurationError("Unrecognized current preset \"{}\" in {}!", *preset_name, get_name());
        }
      }

      m_power_debug = param<bool>("power_debug").default_val(false);

      // TODO: Check for multichannel configs.
      int num_channels = m_organization.count[m_levels["channel"]];
      int num_ranks = m_organization.count[m_levels["rank"]];
      m_power_stats.resize(num_channels * num_ranks);
      for (int i = 0; i < num_channels; i++) {
        for (int j = 0; j < num_ranks; j++) {
          m_power_stats[i * num_ranks + j].rank_id = i * num_ranks + j;
          m_power_stats[i * num_ranks + j].cmd_counters.resize(m_cmds_counted.size(), 0);
          m_power_stats[i * num_ranks + j].req_counters.resize(m_reqs_counted.size(), 0);
        }
      }

      m_powers.resize(m_levels.size(), std::vector<PowerFunc_t<Node>>(m_commands.size()));

      m_powers[m_levels["bank"]][m_commands["ACT"]] = Lambdas::Power::Bank::ACT<DDR5Ambit>;
      m_powers[m_levels["bank"]][m_commands["PRE"]] = Lambdas::Power::Bank::PRE<DDR5Ambit>;
      m_powers[m_levels["bank"]][m_commands["RD"]]  = Lambdas::Power::Bank::RD<DDR5Ambit>;
      m_powers[m_levels["bank"]][m_commands["WR"]]  = Lambdas::Power::Bank::WR<DDR5Ambit>;

      // m_powers[m_levels["rank"]][m_commands["REFsb"]] = Lambdas::Power::Rank::REFsb<DDR5Ambit>;
      // m_powers[m_levels["rank"]][m_commands["REFsb_end"]] = Lambdas::Power::Rank::REFsb_end<DDR5Ambit>;
      m_powers[m_levels["rank"]][m_commands["RFMsb"]] = Lambdas::Power::Rank::RFMsb<DDR5Ambit>;
      m_powers[m_levels["rank"]][m_commands["RFMsb_end"]] = Lambdas::Power::Rank::RFMsb_end<DDR5Ambit>;
      // m_powers[m_levels["rank"]][m_commands["DRFMsb"]] = Lambdas::Power::Rank::REFsb<DDR5Ambit>;
      // m_powers[m_levels["rank"]][m_commands["DRFMsb_end"]] = Lambdas::Power::Rank::REFsb_end<DDR5Ambit>;

      m_powers[m_levels["rank"]][m_commands["ACT"]] = Lambdas::Power::Rank::ACT<DDR5Ambit>;
      m_powers[m_levels["rank"]][m_commands["PRE"]] = Lambdas::Power::Rank::PRE<DDR5Ambit>;
      m_powers[m_levels["rank"]][m_commands["PREA"]] = Lambdas::Power::Rank::PREA<DDR5Ambit>;
      m_powers[m_levels["rank"]][m_commands["REFab"]] = Lambdas::Power::Rank::REFab<DDR5Ambit>;
      m_powers[m_levels["rank"]][m_commands["REFab_end"]] = Lambdas::Power::Rank::REFab_end<DDR5Ambit>;
      // m_powers[m_levels["rank"]][m_commands["RFMab"]] = Lambdas::Power::Rank::REFab<DDR5Ambit>;
      // m_powers[m_levels["rank"]][m_commands["RFMab_end"]] = Lambdas::Power::Rank::REFab_end<DDR5Ambit>;
      // m_powers[m_levels["rank"]][m_commands["DRFMab"]] = Lambdas::Power::Rank::REFab<DDR5Ambit>;
      // m_powers[m_levels["rank"]][m_commands["DRFMab_end"]] = Lambdas::Power::Rank::REFab_end<DDR5Ambit>;

      m_powers[m_levels["rank"]][m_commands["PREsb"]] = Lambdas::Power::Rank::PREsb<DDR5Ambit>;

      m_ambit_powers.resize(m_levels.size(), std::vector<AmbitPowerFunc_t>(m_requests.size()));

      m_ambit_powers[m_levels["bank"]][m_requests["rowclone"]] = [](Node* node, ReqBuffer::iterator req_it, Clk_t clk) {
        Lambdas::Power::Bank::debug<DDR5Ambit>(node, "Incrementing RowClone count", clk);
        node->m_spec->m_power_stats[Lambdas::Power::Bank::get_flat_rank_id<DDR5Ambit>(node)].req_counters[DDR5Ambit::m_reqs_counted("rowclone")] += 1;
      };
      m_ambit_powers[m_levels["bank"]][m_requests["not"]] = [](Node* node, ReqBuffer::iterator req_it, Clk_t clk) {
        Lambdas::Power::Bank::debug<DDR5Ambit>(node, "Incrementing not count", clk);
        node->m_spec->m_power_stats[Lambdas::Power::Bank::get_flat_rank_id<DDR5Ambit>(node)].req_counters[DDR5Ambit::m_reqs_counted("not")] += 1;
      };
      m_ambit_powers[m_levels["bank"]][m_requests["andor"]] = [](Node* node, ReqBuffer::iterator req_it, Clk_t clk) {
        Lambdas::Power::Bank::debug<DDR5Ambit>(node, "Incrementing andor count", clk);
        node->m_spec->m_power_stats[Lambdas::Power::Bank::get_flat_rank_id<DDR5Ambit>(node)].req_counters[DDR5Ambit::m_reqs_counted("andor")] += 1;
      };
      m_ambit_powers[m_levels["bank"]][m_requests["nandnor"]] = [](Node* node, ReqBuffer::iterator req_it, Clk_t clk) {
        Lambdas::Power::Bank::debug<DDR5Ambit>(node, "Incrementing nandnor count", clk);
        node->m_spec->m_power_stats[Lambdas::Power::Bank::get_flat_rank_id<DDR5Ambit>(node)].req_counters[DDR5Ambit::m_reqs_counted("nandnor")] += 1;
      };
      m_ambit_powers[m_levels["bank"]][m_requests["xorxnor"]] = [](Node* node, ReqBuffer::iterator req_it, Clk_t clk) {
        Lambdas::Power::Bank::debug<DDR5Ambit>(node, "Incrementing xorxnor count", clk);
        node->m_spec->m_power_stats[Lambdas::Power::Bank::get_flat_rank_id<DDR5Ambit>(node)].req_counters[DDR5Ambit::m_reqs_counted("xorxnor")] += 1;
      };

      // register stats
      register_stat(s_total_background_energy).name("total_background_energy");
      register_stat(s_total_cmd_energy).name("total_cmd_energy");
      register_stat(s_total_request_energy).name("total_request_energy");
      register_stat(s_total_energy).name("total_energy");
      register_stat(s_total_rfm_energy).name("total_rfm_energy");

            
      for (auto& power_stat : m_power_stats){
        register_stat(power_stat.total_background_energy).name("total_background_energy_rank{}", power_stat.rank_id);
        register_stat(power_stat.total_request_energy).name("total_request_energy_rank{}", power_stat.rank_id);
        register_stat(power_stat.total_cmd_energy).name("total_cmd_energy_rank{}", power_stat.rank_id);
        register_stat(power_stat.total_energy).name("total_energy_rank{}", power_stat.rank_id);
        register_stat(power_stat.act_background_energy).name("act_background_energy_rank{}", power_stat.rank_id);
        register_stat(power_stat.pre_background_energy).name("pre_background_energy_rank{}", power_stat.rank_id);
        register_stat(power_stat.active_cycles).name("active_cycles_rank{}", power_stat.rank_id);
        register_stat(power_stat.idle_cycles).name("idle_cycles_rank{}", power_stat.rank_id);
      }
    }

    void create_nodes() {
      int num_channels = m_organization.count[m_levels["channel"]];
      for (int i = 0; i < num_channels; i++) {
        Node* channel = new Node(this, nullptr, 0, i);
        m_channels.push_back(channel);
      }
    }
    
    void finalize() override {
      if (!m_drampower_enable)
        return;

      int num_channels = m_organization.count[m_levels["channel"]];
      int num_ranks = m_organization.count[m_levels["rank"]];
      for (int i = 0; i < num_channels; i++) {
        for (int j = 0; j < num_ranks; j++) {
          process_rank_energy(m_power_stats[i * num_ranks + j], m_channels[i]->m_child_nodes[j]);
        }
      }
    }

    void process_rank_energy(PowerStats& rank_stats, Node* rank_node) {
      
      Lambdas::Power::Rank::finalize_rank<DDR5Ambit>(rank_node, 0, AddrVec_t(), m_clk);

      size_t num_bankgroups = m_organization.count[m_levels["bankgroup"]];

      auto TS = [&](std::string_view timing) { return m_timing_vals(timing); };
      auto VE = [&](std::string_view voltage) { return m_voltage_vals(voltage); };
      auto CE = [&](std::string_view current) { return m_current_vals(current); };

      double tCK_ns = (double) TS("tCK_ps") / 1000.0;

      rank_stats.act_background_energy = (VE("VDD") * CE("IDD3N") + VE("VPP") * CE("IPP3N")) 
                                            * rank_stats.active_cycles * tCK_ns / 1E3;

      rank_stats.pre_background_energy = (VE("VDD") * CE("IDD2N") + VE("VPP") * CE("IPP2N")) 
                                            * rank_stats.idle_cycles * tCK_ns / 1E3;

      // Power from regular ACT and PRE should not be accounted for
      // double act_cmd_energy  = (VE("VDD") * (CE("IDD0") - CE("IDD3N")) + VE("VPP") * (CE("IPP0") - CE("IPP3N"))) 
      //                                 * rank_stats.cmd_counters[m_cmds_counted("ACT")] * TS("nRAS") * tCK_ns / 1E3;

      // double pre_cmd_energy  = (VE("VDD") * (CE("IDD0") - CE("IDD2N")) + VE("VPP") * (CE("IPP0") - CE("IPP2N"))) 
      //                                 * rank_stats.cmd_counters[m_cmds_counted("PRE")] * TS("nRP")  * tCK_ns / 1E3;

      double aap_energy = ((VE("VDD") * (CE("IDD0") - CE("IDD3N")) + VE("VPP") * (CE("IPP0") - CE("IPP3N"))) * TS("nRAS") * 2
                                          + (VE("VDD") * (CE("IDD0") - CE("IDD2N")) + VE("VPP") * (CE("IPP0") - CE("IPP2N"))) * TS("nRP"))
                                      * tCK_ns / 1E3;

      double ap_energy = ((VE("VDD") * (CE("IDD0") - CE("IDD3N")) + VE("VPP") * (CE("IPP0") - CE("IPP3N"))) * TS("nRAS")
                                          + (VE("VDD") * (CE("IDD0") - CE("IDD2N")) + VE("VPP") * (CE("IPP0") - CE("IPP2N"))) * TS("nRP"))
                                      * tCK_ns / 1E3;

      double rowclone_req_energy = rank_stats.req_counters[m_reqs_counted("rowclone")] * aap_energy;
      double not_req_energy      = rank_stats.req_counters[m_reqs_counted("not")] * (2 * aap_energy);
      double andor_req_energy    = rank_stats.req_counters[m_reqs_counted("andor")] * (4 * aap_energy);
      double nandnor_req_energy  = rank_stats.req_counters[m_reqs_counted("nandnor")] * (4 * ap_energy);
      double xorxnor_req_energy  = rank_stats.req_counters[m_reqs_counted("xorxnor")] * (5 * aap_energy + 2 * ap_energy);

      double rd_cmd_energy   = (VE("VDD") * (CE("IDD4R") - CE("IDD3N")) + VE("VPP") * (CE("IPP4R") - CE("IPP3N"))) 
                                      * rank_stats.cmd_counters[m_cmds_counted("RD")] * TS("nBL") * tCK_ns / 1E3;

      double wr_cmd_energy   = (VE("VDD") * (CE("IDD4W") - CE("IDD3N")) + VE("VPP") * (CE("IPP4W") - CE("IPP3N"))) 
                                      * rank_stats.cmd_counters[m_cmds_counted("WR")] * TS("nBL") * tCK_ns / 1E3;

      double ref_cmd_energy  = (VE("VDD") * (CE("IDD5B")) + VE("VPP") * (CE("IPP5B"))) 
                                      * rank_stats.cmd_counters[m_cmds_counted("REF")] * TS("nRFC1") * tCK_ns / 1E3;

      double rfm_cmd_energy = (VE("VDD") * (CE("IDD0") - CE("IDD3N")) + VE("VPP") * (CE("IPP0") - CE("IPP3N"))) * num_bankgroups
                                      * rank_stats.cmd_counters[m_cmds_counted("RFM")] * TS("nRFMsb") * tCK_ns / 1E3;

      rank_stats.total_background_energy = rank_stats.act_background_energy + rank_stats.pre_background_energy;
      rank_stats.total_cmd_energy = /* act_cmd_energy
                                    + pre_cmd_energy */
                                    + rd_cmd_energy
                                    + wr_cmd_energy 
                                    + ref_cmd_energy
                                    + rfm_cmd_energy;
      rank_stats.total_request_energy = rowclone_req_energy
                                      + not_req_energy
                                      + andor_req_energy
                                      + nandnor_req_energy
                                      + xorxnor_req_energy;

      rank_stats.total_energy = rank_stats.total_background_energy + rank_stats.total_cmd_energy + rank_stats.total_request_energy;

      s_total_background_energy += rank_stats.total_background_energy;
      s_total_cmd_energy += rank_stats.total_cmd_energy;
      s_total_request_energy += rank_stats.total_request_energy;
      s_total_energy += rank_stats.total_energy;
      s_total_rfm_energy += rfm_cmd_energy;

      s_total_rfm_cycles[rank_stats.rank_id] = rank_stats.cmd_counters[m_cmds_counted("RFM")] * TS("nRFMsb");
    }
};


}        // namespace Ramulator
