#include "dram_controller/controller.h"
#include "memory_system/memory_system.h"

namespace Ramulator {

class TerracottaChargeCacheMASADRAMController final : public IDRAMController, public Implementation {
  RAMULATOR_REGISTER_IMPLEMENTATION(IDRAMController, TerracottaChargeCacheMASADRAMController, "TerracottaChargeCacheMASAController", "A TerracottaChargeCache+MASA DRAM controller.");

  typedef enum lookup_result_t {
    HIT = 0,
    MISS = 1,
  } lookup_result_t;

  class entry {
    public:
      bool valid;
      uint64_t tag;
      uint64_t lru_counter;

      entry() : valid(false), tag(0), lru_counter(0) {}
  };

  // Per-bank HCRAC with {row, subarray} address (like Terracotta ChargeCache but with SA bits to avoid aliasing)
  class HCRAC {
    private:
    std::vector<std::vector<entry>> entries;
    uint64_t m_ways;
    uint64_t m_caching_duration;
    uint64_t m_num_sets;
    uint64_t m_inv_idx;
    uint64_t m_capacity;

    uint64_t num_sa_bits;
    uint64_t row_idx, sa_idx;


    public:
    HCRAC(int num_entries, int num_ways, int caching_duration, IDRAM* dram) : entries(num_entries / num_ways, std::vector<entry>(num_ways)),
                                                              m_ways(num_ways),
                                                              m_caching_duration(caching_duration),
                                                              m_capacity(num_entries) {
      m_num_sets = num_entries / num_ways;
      m_inv_idx = 0;

      num_sa_bits = dram->get_level_size("subarray") > 1 ? (uint64_t)std::ceil(std::log2(dram->get_level_size("subarray"))) : 0;
      row_idx = dram->m_levels("row");
      sa_idx = dram->m_levels("subarray");

    }

    ~HCRAC() {
      entries.clear();
    }

    bool lookup(AddrVec_t addr_vec) {
      uint64_t hcrac_addr = get_hcrac_addr(addr_vec);
      uint64_t set_idx = get_set_idx(hcrac_addr);
      bool hit = false;

      uint64_t entry_idx = 0;
      for (auto& entry : entries[set_idx]) {
        if (entry.valid && entry.tag == hcrac_addr) {
          hit = true;
          break;
        }
        entry_idx++;
      }

      if (hit) {
        for (auto& entry : entries[set_idx]) {
          if (entry.valid) {
            entry.lru_counter = (entry.lru_counter == 0) ? 0 : entry.lru_counter - 1;
          }
        }
        entries[set_idx][entry_idx].lru_counter = m_ways - 1;
      }

      return hit;
    }

    std::tuple<bool, bool> update(AddrVec_t addr_vec) {
      uint64_t hcrac_addr = get_hcrac_addr(addr_vec);
      uint64_t set_idx = get_set_idx(hcrac_addr);

      for (auto& entry : entries[set_idx]) {
        if (entry.valid && entry.tag == hcrac_addr) {
          return std::make_tuple(false, false);
        }
      }

      for (auto& entry : entries[set_idx]) {
        if (!entry.valid) {
          entry.tag = hcrac_addr;
          entry.lru_counter = m_ways - 1;
          entry.valid = true;
          return std::make_tuple(true, false);
        }
      }

      int lru_index = 0;
      uint64_t min_lru = entries[set_idx][0].lru_counter;
      for (int i = 1; i < entries[set_idx].size(); i++) {
        if (entries[set_idx][i].lru_counter < min_lru) {
          min_lru = entries[set_idx][i].lru_counter;
          lru_index = i;
        }
      }

      entries[set_idx][lru_index].tag = hcrac_addr;
      entries[set_idx][lru_index].lru_counter = m_ways - 1;
      entries[set_idx][lru_index].valid = true;

      return std::make_tuple(true, true);
    }

    void invalidate(void) {
      uint64_t set_idx = m_inv_idx / m_ways;
      uint64_t way_idx = m_inv_idx % m_ways;

      entries[set_idx][way_idx].valid = false;

      m_inv_idx++;
      if (m_inv_idx == m_capacity)
        m_inv_idx = 0;
    }

    // Address = {row, subarray} — per-bank HCRAC doesn't need bank/bg/rank bits
    uint64_t get_hcrac_addr (AddrVec_t addr_vec) {
      uint64_t hcrac_addr = addr_vec[row_idx];
      hcrac_addr = (hcrac_addr << num_sa_bits) | addr_vec[sa_idx];
      return hcrac_addr;
    }

    uint64_t get_set_idx (uint64_t hcrac_addr) {
      return hcrac_addr % m_num_sets;
    }

    void finalize() {}

  };

  private:
    std::deque<Request> pending;

    ReqBuffer m_active_buffer;
    ReqBuffer m_priority_buffer;
    ReqBuffer m_read_buffer;
    ReqBuffer m_write_buffer;

    int m_bank_addr_idx = -1;

    float m_wr_low_watermark;
    float m_wr_high_watermark;
    int controller_latency;
    bool  m_is_write_mode = false;

    // TerracottaChargeCache parameters
    int m_set_associativity = 0;
    int m_num_entries_per_bank_per_core = 0;
    int m_caching_duration = 0;

    uint64_t m_hcrac_inv_idx = 0;
    uint64_t m_hcrac_inv_interval = 0;

    size_t m_num_banks = 0;
    std::vector<HCRAC*> m_hcrac; // One HCRAC per bank

    bool m_is_debug = false;

    // Adaptive CC filtering — EWMA-based C/A bus utilization
    float m_ewma_alpha = 0.0f;
    float m_bus_util_threshold = 1.0f;
    int   m_ewma_window = 0;
    float m_ewma_bus_util = 0.0f;
    size_t m_window_busy_cycles = 0;
    Clk_t  m_window_start_clk = 0;

    // Cached command IDs (populated in setup)
    int m_cmd_ACT = -1;
    int m_cmd_RD = -1;
    int m_cmd_WR = -1;
    int m_cmd_RDA = -1;
    int m_cmd_WRA = -1;
    int m_cmd_SA_SEL = -1;
    int m_cmd_PRE_SA = -1;

    // Adaptive CC stats
    size_t s_cc_acts_issued = 0;
    size_t s_cc_acts_suppressed = 0;
    size_t s_normal_acts_issued = 0;
    size_t s_ca_bus_busy_cycles = 0;

    // MASA parameters
    int m_num_subarrays = 0;
    int m_sa_level_idx = -1;

    size_t s_row_hits = 0;
    size_t s_row_misses = 0;
    size_t s_row_conflicts = 0;
    size_t s_read_row_hits = 0;
    size_t s_read_row_misses = 0;
    size_t s_read_row_conflicts = 0;
    size_t s_write_row_hits = 0;
    size_t s_write_row_misses = 0;
    size_t s_write_row_conflicts = 0;

    size_t m_num_cores = 0;
    std::vector<size_t> s_read_row_hits_per_core;
    std::vector<size_t> s_read_row_misses_per_core;
    std::vector<size_t> s_read_row_conflicts_per_core;

    std::vector<size_t> s_hcrac_hits_per_bank;
    std::vector<size_t> s_hcrac_misses_per_bank;
    std::vector<size_t> s_hcrac_updates_per_bank;
    std::vector<size_t> s_hcrac_invalidations_per_bank;
    std::vector<size_t> s_hcrac_evictions_per_bank;

    size_t s_hcrac_hits = 0;
    size_t s_hcrac_misses = 0;
    size_t s_hcrac_updates = 0;
    size_t s_hcrac_invalidations = 0;
    size_t s_hcrac_evictions = 0;

    size_t s_cc_acts = 0;      // Aggregate: s_cc_acts_issued + s_cc_acts_suppressed
    size_t s_normal_acts = 0;  // Aggregate: s_normal_acts_issued

    size_t s_num_read_reqs = 0;
    size_t s_num_write_reqs = 0;
    size_t s_num_other_reqs = 0;
    size_t s_queue_len = 0;
    size_t s_read_queue_len = 0;
    size_t s_write_queue_len = 0;
    size_t s_priority_queue_len = 0;
    float s_queue_len_avg = 0;
    float s_read_queue_len_avg = 0;
    float s_write_queue_len_avg = 0;
    float s_priority_queue_len_avg = 0;

    size_t s_read_latency = 0;
    float s_avg_read_latency = 0;


  public:
    void init() override {
      m_wr_low_watermark =  param<float>("wr_low_watermark").desc("Threshold for switching back to read mode.").default_val(0.2f);
      m_wr_high_watermark = param<float>("wr_high_watermark").desc("Threshold for switching to write mode.").default_val(0.8f);
      controller_latency = param<int>("controller_latency").desc("Latency of the memory controller in cycles.").default_val(0);

      m_set_associativity = param_group("Config").param<int>("set_associativity").required().desc("Set associativity of the ChargeCache.");
      m_num_entries_per_bank_per_core = param_group("Config").param<int>("num_entries_per_bank_per_core").required().desc("Number of entries per bank per core in the ChargeCache.");
      m_caching_duration = param_group("Config").param<int>("caching_duration").required().desc("Duration (in ms) for which a row stays in the ChargeCache.");
      m_is_debug = param_group("Config").param<bool>("is_debug").desc("Enable debug messages.").default_val(false);

      // Adaptive CC filter parameters
      m_ewma_alpha = param_group("AdaptiveCC").param<float>("ewma_alpha").desc("EWMA smoothing factor.").default_val(0.125f);
      m_bus_util_threshold = param_group("AdaptiveCC").param<float>("bus_util_threshold").desc("Suppress CC when bus util EWMA exceeds this.").default_val(1.0f);
      m_ewma_window = param_group("AdaptiveCC").param<int>("ewma_window").desc("Window size in cycles for bus utilization sampling.").default_val(1000);

      m_scheduler = create_child_ifce<IScheduler>();
      m_refresh = create_child_ifce<IRefreshManager>();    
      m_rowpolicy = create_child_ifce<IRowPolicy>();    

      if (m_config["plugins"]) {
        YAML::Node plugin_configs = m_config["plugins"];
        for (YAML::iterator it = plugin_configs.begin(); it != plugin_configs.end(); ++it) {
          m_plugins.push_back(create_child_ifce<IControllerPlugin>(*it));
        }
      }
    };

    void setup(IFrontEnd* frontend, IMemorySystem* memory_system) override {
      m_dram = memory_system->get_ifce<IDRAM>();
      m_bank_addr_idx = m_dram->m_levels("bank");
      m_priority_buffer.max_size = 512*3 + 32;

      m_num_banks = m_dram->get_level_size("rank") * m_dram->get_level_size("bankgroup") * m_dram->get_level_size("bank");
      m_num_cores = frontend->get_num_cores();

      // MASA setup
      m_sa_level_idx = m_dram->m_levels("subarray");
      m_num_subarrays = m_dram->get_level_size("subarray");

      // Cache command IDs for bus cost lookup
      m_cmd_ACT    = m_dram->m_commands("ACT");
      m_cmd_RD     = m_dram->m_commands("RD");
      m_cmd_WR     = m_dram->m_commands("WR");
      m_cmd_RDA    = m_dram->m_commands("RDA");
      m_cmd_WRA    = m_dram->m_commands("WRA");
      m_cmd_SA_SEL = m_dram->m_commands("SA_SEL");
      m_cmd_PRE_SA = m_dram->m_commands("PRE_SA");

      // Per-bank HCRAC setup (like Terracotta ChargeCache)
      for (int i = 0; i < m_num_banks; i++) {
        m_hcrac.push_back(new HCRAC(m_num_cores * m_num_entries_per_bank_per_core, m_set_associativity, m_caching_duration, m_dram));
      }
      m_hcrac_inv_interval = JEDEC_rounding_DDR5(m_caching_duration * 1000000 / (m_num_cores * m_num_entries_per_bank_per_core), m_dram->m_timing_vals("tCK_ps"));

      s_read_row_hits_per_core.resize(m_num_cores, 0);
      s_read_row_misses_per_core.resize(m_num_cores, 0);
      s_read_row_conflicts_per_core.resize(m_num_cores, 0);

      register_stat(s_row_hits).name("row_hits_{}", m_channel_id);
      register_stat(s_row_misses).name("row_misses_{}", m_channel_id);
      register_stat(s_row_conflicts).name("row_conflicts_{}", m_channel_id);
      register_stat(s_read_row_hits).name("read_row_hits_{}", m_channel_id);
      register_stat(s_read_row_misses).name("read_row_misses_{}", m_channel_id);
      register_stat(s_read_row_conflicts).name("read_row_conflicts_{}", m_channel_id);
      register_stat(s_write_row_hits).name("write_row_hits_{}", m_channel_id);
      register_stat(s_write_row_misses).name("write_row_misses_{}", m_channel_id);
      register_stat(s_write_row_conflicts).name("write_row_conflicts_{}", m_channel_id);

      for (size_t core_id = 0; core_id < m_num_cores; core_id++) {
        register_stat(s_read_row_hits_per_core[core_id]).name("read_row_hits_core_{}", core_id);
        register_stat(s_read_row_misses_per_core[core_id]).name("read_row_misses_core_{}", core_id);
        register_stat(s_read_row_conflicts_per_core[core_id]).name("read_row_conflicts_core_{}", core_id);
      }

      register_stat(s_num_read_reqs).name("num_read_reqs_{}", m_channel_id);
      register_stat(s_num_write_reqs).name("num_write_reqs_{}", m_channel_id);
      register_stat(s_num_other_reqs).name("num_other_reqs_{}", m_channel_id);
      register_stat(s_queue_len).name("queue_len_{}", m_channel_id);
      register_stat(s_read_queue_len).name("read_queue_len_{}", m_channel_id);
      register_stat(s_write_queue_len).name("write_queue_len_{}", m_channel_id);
      register_stat(s_priority_queue_len).name("priority_queue_len_{}", m_channel_id);
      register_stat(s_queue_len_avg).name("queue_len_avg_{}", m_channel_id);
      register_stat(s_read_queue_len_avg).name("read_queue_len_avg_{}", m_channel_id);
      register_stat(s_write_queue_len_avg).name("write_queue_len_avg_{}", m_channel_id);
      register_stat(s_priority_queue_len_avg).name("priority_queue_len_avg_{}", m_channel_id);

      s_hcrac_hits_per_bank.resize(m_num_banks, 0);
      s_hcrac_misses_per_bank.resize(m_num_banks, 0);
      s_hcrac_updates_per_bank.resize(m_num_banks, 0);
      s_hcrac_invalidations_per_bank.resize(m_num_banks, 0);
      s_hcrac_evictions_per_bank.resize(m_num_banks, 0);

      register_stat(s_hcrac_hits).name("hcrac_hits_{}", m_channel_id);
      register_stat(s_hcrac_misses).name("hcrac_misses_{}", m_channel_id);
      register_stat(s_hcrac_updates).name("hcrac_updates_{}", m_channel_id);
      register_stat(s_hcrac_invalidations).name("hcrac_invalidations_{}", m_channel_id);
      register_stat(s_hcrac_evictions).name("hcrac_evictions_{}", m_channel_id);

      register_stat(s_cc_acts).name("cc_acts_{}", m_channel_id);
      register_stat(s_normal_acts).name("normal_acts_{}", m_channel_id);

      register_stat(s_cc_acts_issued).name("cc_acts_issued_{}", m_channel_id);
      register_stat(s_cc_acts_suppressed).name("cc_acts_suppressed_{}", m_channel_id);
      register_stat(s_normal_acts_issued).name("normal_acts_issued_{}", m_channel_id);
      register_stat(s_ca_bus_busy_cycles).name("ca_bus_busy_cycles_{}", m_channel_id);

      register_stat(s_read_latency).name("read_latency_{}", m_channel_id);
      register_stat(s_avg_read_latency).name("avg_read_latency_{}", m_channel_id);
    };

    bool send(Request& req) override {
      req.final_command = m_dram->m_request_translations(req.type_id);

      switch (req.type_id) {
        case Request::Type::Read: { s_num_read_reqs++; break; }
        case Request::Type::Write: { s_num_write_reqs++; break; }
        default: { s_num_other_reqs++; break; }
      }

      if (req.type_id == Request::Type::Read) {
        auto compare_addr = [req](const Request& wreq) {
          return wreq.addr == req.addr;
        };
        if (std::find_if(m_write_buffer.begin(), m_write_buffer.end(), compare_addr) != m_write_buffer.end()) {
          req.depart = m_clk + 1;
          pending.push_back(req);
          return true;
        }
      }

      bool is_success = false;
      req.arrive = m_clk;
      if        (req.type_id == Request::Type::Read) {
        is_success = m_read_buffer.enqueue(req);
      } else if (req.type_id == Request::Type::Write) {
        is_success = m_write_buffer.enqueue(req);
      } else {
        throw std::runtime_error("Invalid request type!");
      }
      if (!is_success) {
        req.arrive = -1;
        return false;
      }

      return true;
    };

    bool priority_send(Request& req) override {
      req.final_command = m_dram->m_request_translations(req.type_id);
      bool is_success = false;
      is_success = m_priority_buffer.enqueue(req);
      return is_success;
    }

    void tick() override {
      if (m_is_debug)
        std::cout << "Cycle: " << m_clk << std::endl;
      m_clk++;

      s_queue_len += m_read_buffer.size() + m_write_buffer.size() + m_priority_buffer.size() + pending.size();
      s_read_queue_len += m_read_buffer.size() + pending.size();
      s_write_queue_len += m_write_buffer.size();
      s_priority_queue_len += m_priority_buffer.size();

      serve_completed_reads();

      m_refresh->tick();

      ReqBuffer::iterator req_it;
      ReqBuffer* buffer = nullptr;
      bool request_found = schedule_request(req_it, buffer);

      // Update EWMA bus utilization at window boundaries
      if (m_ewma_window > 0 && (m_clk - m_window_start_clk) >= (Clk_t)m_ewma_window) {
        float window_util = (float)m_window_busy_cycles / (float)m_ewma_window;
        m_ewma_bus_util = m_ewma_alpha * window_util + (1.0f - m_ewma_alpha) * m_ewma_bus_util;
        m_window_busy_cycles = 0;
        m_window_start_clk = m_clk;
      }

      if (request_found) {
        if (m_is_debug) {
          std::cout << "Request found, command: " << req_it->command << " from core: " << req_it->source_id << " Address Vector: [";
          for (const auto& addr : req_it->addr_vec) {
            std::cout << addr << " ";
          }
          std::cout << "]" << std::endl;
        }
      }

      // 2.0.0. Perform per-bank HCRAC invalidation
      if (m_clk % m_hcrac_inv_interval == 0)
      {
        if (m_is_debug) {
          std::cout << "Invalidating entries" << std::endl;
        }
        for (int i = 0; i < m_num_banks; i++) {
          s_hcrac_invalidations_per_bank[i]++;
          m_hcrac[i]->invalidate();
        }
      }

      if (request_found) {
        int command = req_it->command;

        req_it->scratchpad[0] = 0;

        int rank = req_it->addr_vec[m_dram->m_levels("rank")];
        int bg = req_it->addr_vec[m_dram->m_levels("bankgroup")];
        int bank = req_it->addr_vec[m_dram->m_levels("bank")];
        int flat_bank_id = rank * (m_dram->get_level_size("bankgroup") * m_dram->get_level_size("bank")) + bg * m_dram->get_level_size("bank") + bank;

        // 1.0 Handle ACTs — lookup per-bank HCRAC with adaptive filtering
        if (command == m_cmd_ACT && 
              (req_it->type_id == Request::Type::Read || req_it->type_id == Request::Type::Write) &&
              req_it->source_id >= 0 && req_it->source_id < m_num_cores) {
          HCRAC* hcrac = m_hcrac[flat_bank_id];
          bool lookup = hcrac->lookup(req_it->addr_vec);
          if (lookup) {
            s_hcrac_hits_per_bank[flat_bank_id]++;
            if (m_ewma_bus_util < m_bus_util_threshold) {
              if (m_is_debug)
                std::cout << "HCRAC hit ISSUED for bank " << flat_bank_id << " (bus_util=" << m_ewma_bus_util << ")" << std::endl;
              req_it->scratchpad[0] = 1;
              s_cc_acts_issued++;
            } else {
              if (m_is_debug)
                std::cout << "HCRAC hit SUPPRESSED for bank " << flat_bank_id << " (bus_util=" << m_ewma_bus_util << ")" << std::endl;
              s_cc_acts_suppressed++;
            }
          } else {
            if (m_is_debug)
              std::cout << "HCRAC miss for bank " << flat_bank_id << std::endl;
            s_hcrac_misses_per_bank[flat_bank_id]++;
            s_normal_acts_issued++;
          }
        }

        // 2.0 Handle precharge commands — update per-bank HCRAC with open rows
        bool is_precharge = (command == m_dram->m_commands("PRE_SA") || command == m_dram->m_commands("RDA") || command == m_dram->m_commands("WRA"));
        bool is_bank_precharge = (command == m_dram->m_commands("PRE"));
        bool is_all_bank_precharge = (command == m_dram->m_commands("PREA"));

        if (is_precharge || is_bank_precharge || is_all_bank_precharge) {
          if (is_precharge) {
            // PRE_SA/RDA/WRA — closes a single subarray
            AddrVec_t pre_addr_vec = req_it->addr_vec;
            std::vector<int> open_rows = get_open_rows(pre_addr_vec);
            for (auto row : open_rows) {
              AddrVec_t hcrac_addr_vec = pre_addr_vec;
              hcrac_addr_vec[m_dram->m_levels("row")] = row;
              if (m_is_debug) {
                std::cout << "Updating HCRAC for bank " << flat_bank_id << " Address Vector: [";
                for (const auto& addr : hcrac_addr_vec) { std::cout << addr << " "; }
                std::cout << "]" << std::endl;
              }
              std::tuple<bool, bool> result = m_hcrac[flat_bank_id]->update(hcrac_addr_vec);
              if (std::get<1>(result))
                s_hcrac_evictions_per_bank[flat_bank_id]++;
              if (std::get<0>(result))
                s_hcrac_updates_per_bank[flat_bank_id]++;
            }
          } else if (is_bank_precharge) {
            // PRE — closes the entire bank, iterate all subarrays
            AddrVec_t pre_addr_vec = req_it->addr_vec;
            for (int sa = 0; sa < m_num_subarrays; sa++) {
              pre_addr_vec[m_sa_level_idx] = sa;
              std::vector<int> open_rows = get_open_rows(pre_addr_vec);
              for (auto row : open_rows) {
                AddrVec_t hcrac_addr_vec = pre_addr_vec;
                hcrac_addr_vec[m_dram->m_levels("row")] = row;
                if (m_is_debug) {
                  std::cout << "Updating HCRAC for bank " << flat_bank_id << " Address Vector: [";
                  for (const auto& addr : hcrac_addr_vec) { std::cout << addr << " "; }
                  std::cout << "]" << std::endl;
                }
                std::tuple<bool, bool> result = m_hcrac[flat_bank_id]->update(hcrac_addr_vec);
                if (std::get<1>(result))
                  s_hcrac_evictions_per_bank[flat_bank_id]++;
                if (std::get<0>(result))
                  s_hcrac_updates_per_bank[flat_bank_id]++;
              }
            }
          }
        }
      }

      // 2.1 Take row policy action
      m_rowpolicy->update(request_found, req_it);

      // 3. Update all plugins
      for (auto plugin : m_plugins) {
        plugin->update(request_found, req_it);
      }

      // 4. Finally, issue the commands to serve the request
      if (request_found) {
        if (req_it->is_stat_updated == false) {
          update_request_stats(req_it);
        }
        m_dram->issue_command(req_it);

        // Track C/A bus utilization for this command
        {
          int bus_cycles = get_cmd_bus_cycles(req_it->command, req_it->scratchpad[0]);
          m_window_busy_cycles += bus_cycles;
          s_ca_bus_busy_cycles += bus_cycles;
        }

        if (req_it->command == req_it->final_command) {
          if (req_it->type_id == Request::Type::Read) {
            req_it->depart = m_clk + m_dram->m_read_latency + controller_latency;
            pending.push_back(*req_it);
          } else if (req_it->type_id == Request::Type::Write) {
          }
          buffer->remove(req_it);
        } else {
          if (m_dram->m_command_meta(req_it->command).is_opening) {
            m_active_buffer.enqueue(*req_it);
            buffer->remove(req_it);
          }
        }

      }
    }


  private:
    bool is_row_hit(ReqBuffer::iterator& req)
    {
        return m_dram->check_rowbuffer_hit(req->final_command, req->addr_vec);
    }
    bool is_row_open(ReqBuffer::iterator& req)
    {
        return m_dram->check_node_open(req->final_command, req->addr_vec);
    }

    std::vector<int> get_open_rows(AddrVec_t addr_vec)
    {
      return m_dram->get_open_rows(addr_vec);
    }

    int get_cmd_bus_cycles(int command, int scratchpad_0) {
      if (command == m_cmd_ACT)
        return (scratchpad_0 == 1) ? 3 : 2;
      if (command == m_cmd_RD  || command == m_cmd_WR  ||
          command == m_cmd_RDA || command == m_cmd_WRA ||
          command == m_cmd_SA_SEL || command == m_cmd_PRE_SA)
        return 2;
      return 1;
    }

    void update_request_stats(ReqBuffer::iterator& req)
    {
      req->is_stat_updated = true;

      if (req->type_id == Request::Type::Read) 
      {
        if (is_row_hit(req)) {
          s_read_row_hits++;
          s_row_hits++;
          if (req->source_id != -1)
            s_read_row_hits_per_core[req->source_id]++;
        } else if (is_row_open(req)) {
          s_read_row_conflicts++;
          s_row_conflicts++;
          if (req->source_id != -1)
            s_read_row_conflicts_per_core[req->source_id]++;
        } else {
          s_read_row_misses++;
          s_row_misses++;
          if (req->source_id != -1)
            s_read_row_misses_per_core[req->source_id]++;
        } 
      } 
      else if (req->type_id == Request::Type::Write) 
      {
        if (is_row_hit(req)) {
          s_write_row_hits++;
          s_row_hits++;
        } else if (is_row_open(req)) {
          s_write_row_conflicts++;
          s_row_conflicts++;
        } else {
          s_write_row_misses++;
          s_row_misses++;
        }
      }
    }

    void serve_completed_reads() {
      if (pending.size()) {
        auto& req = pending[0];
        if (req.depart <= m_clk) {
          if (req.depart - req.arrive > 1) {
            s_read_latency += req.depart - req.arrive;
          }

          if (req.callback) {
            req.callback(req);
          }
          pending.pop_front();
        }
      };
    };

    void set_write_mode() {
      if (!m_is_write_mode) {
        if ((m_write_buffer.size() > m_wr_high_watermark * m_write_buffer.max_size) || m_read_buffer.size() == 0) {
          m_is_write_mode = true;
        }
      } else {
        if ((m_write_buffer.size() < m_wr_low_watermark * m_write_buffer.max_size) && m_read_buffer.size() != 0) {
          m_is_write_mode = false;
        }
      }
    };

    bool schedule_request(ReqBuffer::iterator& req_it, ReqBuffer*& req_buffer) {
      bool request_found = false;
      if (req_it= m_scheduler->get_best_request(m_active_buffer); req_it != m_active_buffer.end()) {
        if (m_dram->check_ready(req_it->command, req_it->addr_vec)) {
          request_found = true;
          req_buffer = &m_active_buffer;
        }
      }

      if (!request_found) {
        if (m_priority_buffer.size() != 0) {
          req_buffer = &m_priority_buffer;
          req_it = m_priority_buffer.begin();
          req_it->command = m_dram->get_preq_command(req_it->final_command, req_it->addr_vec);
          
          request_found = m_dram->check_ready(req_it->command, req_it->addr_vec);
          if (!request_found & m_priority_buffer.size() != 0) {
            return false;
          }
        }

        if (!request_found) {
          set_write_mode();
          auto& buffer = m_is_write_mode ? m_write_buffer : m_read_buffer;
          if (req_it = m_scheduler->get_best_request(buffer); req_it != buffer.end()) {
            request_found = m_dram->check_ready(req_it->command, req_it->addr_vec);
            req_buffer = &buffer;
          }
        }
      }

      if (request_found) {
        if (m_dram->m_command_meta(req_it->command).is_closing) {
          auto& rowgroup = req_it->addr_vec;
          for (auto _it = m_active_buffer.begin(); _it != m_active_buffer.end(); _it++) {
            auto& _it_rowgroup = _it->addr_vec;
            bool is_matching = true;
            for (int i = 0; i < m_bank_addr_idx + 1 ; i++) {
              if (_it_rowgroup[i] != rowgroup[i] && _it_rowgroup[i] != -1 && rowgroup[i] != -1) {
                is_matching = false;
                break;
              }
            }
            if (is_matching) {
              request_found = false;
              break;
            }
          }
        }
      }

      return request_found;
    }

    void finalize() override {
      s_avg_read_latency = (float) s_read_latency / (float) s_num_read_reqs;

      s_queue_len_avg = (float) s_queue_len / (float) m_clk;
      s_read_queue_len_avg = (float) s_read_queue_len / (float) m_clk;
      s_write_queue_len_avg = (float) s_write_queue_len / (float) m_clk;
      s_priority_queue_len_avg = (float) s_priority_queue_len / (float) m_clk;

      for (int i = 0; i < m_num_banks; i++) {
        m_hcrac[i]->finalize();
      }

      for (int i = 0; i < m_num_banks; i++) {
        s_hcrac_hits += s_hcrac_hits_per_bank[i];
        s_hcrac_misses += s_hcrac_misses_per_bank[i];
        s_hcrac_updates += s_hcrac_updates_per_bank[i];
        s_hcrac_invalidations += s_hcrac_invalidations_per_bank[i];
        s_hcrac_evictions += s_hcrac_evictions_per_bank[i];
      }

      s_cc_acts = s_cc_acts_issued + s_cc_acts_suppressed;
      s_normal_acts = s_normal_acts_issued;

      return;
    }

};
  
}   // namespace Ramulator
