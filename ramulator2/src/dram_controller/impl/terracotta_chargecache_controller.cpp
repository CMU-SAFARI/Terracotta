#include "dram_controller/controller.h"
#include "memory_system/memory_system.h"

namespace Ramulator {

class TerracottaChargeCacheDRAMController final : public IDRAMController, public Implementation {
  RAMULATOR_REGISTER_IMPLEMENTATION(IDRAMController, TerracottaChargeCacheDRAMController, "TerracottaChargeCacheController", "A ChargeCache Terracotta controller.");

  typedef enum lookup_result_t {
    HIT = 0,  // Entry found and is valid
    MISS = 1, // Entry not found
  } lookup_result_t;

  class entry {
    public:
      bool valid;
      uint64_t tag;
      uint64_t lru_counter;

      entry() : valid(false), tag(0), lru_counter(0) {}
  };

  class HCRAC {
    private:
    std::vector<std::vector<entry>> entries;
    uint64_t m_ways;
    uint64_t m_caching_duration;
    uint64_t m_num_sets;
    uint64_t m_inv_idx;
    uint64_t m_capacity;

    uint64_t num_row_bits;
    uint64_t row_idx;

    std::vector<size_t> s_hcrac_hits_per_set;
    std::vector<size_t> s_hcrac_misses_per_set;

    public:
    // Constructor
    HCRAC(int num_entries, int num_ways, int caching_duration, IDRAM* dram) : entries(num_entries / num_ways, std::vector<entry>(num_ways)),
                                                              m_ways(num_ways),
                                                              m_caching_duration(caching_duration),
                                                              m_capacity(num_entries) {
      m_num_sets = num_entries / num_ways;
      m_inv_idx = 0;

      row_idx = dram->m_levels("row");

      s_hcrac_hits_per_set.resize(m_num_sets, 0);
      s_hcrac_misses_per_set.resize(m_num_sets, 0);
    }

    // Destructor
    ~HCRAC() {
      entries.clear();
    }

    bool lookup(AddrVec_t addr_vec) {
      uint64_t hcrac_addr = get_hcrac_addr(addr_vec);
      uint64_t set_idx = get_set_idx(hcrac_addr);
      bool hit = false;

      // Perform lookup
      uint64_t entry_idx = 0;
      for (auto& entry : entries[set_idx]) {
        if (entry.valid && entry.tag == hcrac_addr) {
          hit = true;
          break;
        }
        entry_idx++;
      }

      // Update LRU counters
      if (hit) {
        for (auto& entry : entries[set_idx]) {
          if (entry.valid) {
            entry.lru_counter = (entry.lru_counter == 0) ? 0 : entry.lru_counter - 1;
          }
        }
        entries[set_idx][entry_idx].lru_counter = m_ways - 1; // Most recently used

        // Stats
        s_hcrac_hits_per_set[set_idx]++;  
      } else {
        s_hcrac_misses_per_set[set_idx]++;
      }

      return hit; // Miss
    }

    std::tuple<bool, bool> update(AddrVec_t addr_vec) {

      uint64_t hcrac_addr = get_hcrac_addr(addr_vec);
      uint64_t set_idx = get_set_idx(hcrac_addr);

      // Check if the entry already exists
      for (auto& entry : entries[set_idx]) {
        if (entry.valid && entry.tag == hcrac_addr) {
          // Entry already exists, no need to update
          return std::make_tuple(false, false);
        }
      }

      // Find an invalid entry to replace
      for (auto& entry : entries[set_idx]) {
        if (!entry.valid) {
          entry.tag = hcrac_addr;
          entry.lru_counter = m_ways - 1; // Most recently used
          entry.valid = true;
          return std::make_tuple(true, false); // Updated
        }
      }

      // If all entries are valid, find the entry with the least lru_counter value
      int lru_index = 0;
      uint64_t min_lru = entries[set_idx][0].lru_counter;
      for (int i = 1; i < entries[set_idx].size(); i++) {
        if (entries[set_idx][i].lru_counter < min_lru) {
          min_lru = entries[set_idx][i].lru_counter;
          lru_index = i;
        }
      }

      // Evict the entry at lru_index and insert the new one
      entries[set_idx][lru_index].tag = hcrac_addr;
      entries[set_idx][lru_index].lru_counter = m_ways - 1; // Most recently used
      entries[set_idx][lru_index].valid = true;

      return std::make_tuple(true, true); // Updated, Evicted
    }

    void invalidate(void) {
      uint64_t set_idx = m_inv_idx / m_ways;
      uint64_t way_idx = m_inv_idx % m_ways;

      entries[set_idx][way_idx].valid = false;

      m_inv_idx++;
      if (m_inv_idx == m_capacity)
        m_inv_idx = 0;
    }

    uint64_t get_hcrac_addr (AddrVec_t addr_vec) {
      uint64_t hcrac_addr = addr_vec[row_idx];
      return hcrac_addr;
    }

    uint64_t get_set_idx (uint64_t hcrac_addr) {
      return hcrac_addr % m_num_sets;
    }

    void finalize() {
    }

  };

  private:
    std::deque<Request> pending;          // A queue for read requests that are about to finish (callback after RL)

    ReqBuffer m_active_buffer;            // Buffer for requests being served. This has the highest priority 
    ReqBuffer m_priority_buffer;          // Buffer for high-priority requests (e.g., maintenance like refresh).
    ReqBuffer m_read_buffer;              // Read request buffer
    ReqBuffer m_write_buffer;             // Write request buffer

    int m_bank_addr_idx = -1;

    float m_wr_low_watermark;
    float m_wr_high_watermark;
    int controller_latency;
    bool  m_is_write_mode = false;

    // TerracottaChargeCache parameters
    int m_set_associativity = 0;
    int m_num_entries_per_bank_per_core = 0;
    int m_caching_duration = 0; // in ms

    uint64_t m_hcrac_inv_idx = 0;
    uint64_t m_hcrac_inv_interval = 0;

    size_t m_num_banks = 0;
    std::vector<HCRAC*> m_hcrac; // One HCRAC per bank

    bool m_is_debug = false;
    // TerracottaChargeCache parameters

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
      m_num_entries_per_bank_per_core = param_group("Config").param<int>("num_entries_per_bank_per_core").required().desc("Number of entries in the ChargeCache.");
      m_caching_duration = param_group("Config").param<int>("caching_duration").required().desc("Duration (in ms) for which a row stays in the ChargeCache.");

      m_is_debug = param_group("Config").param<bool>("is_debug").desc("Enable debug messages.").default_val(false);

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

      // ChargeCache setup
      for (int i = 0; i < m_num_banks; i++) {
        m_hcrac.push_back(new HCRAC(m_num_cores * m_num_entries_per_bank_per_core, m_set_associativity, m_caching_duration, m_dram));
      }
      m_hcrac_inv_interval = JEDEC_rounding_DDR5(m_caching_duration * 1000000 / (m_num_cores * m_num_entries_per_bank_per_core), m_dram->m_timing_vals("tCK_ps"));
      // ChargeCache setup

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

      // for (size_t bank_id = 0; bank_id < m_num_banks; bank_id++) {
      //   register_stat(s_hcrac_hits_per_bank[bank_id]).name("hcrac_hits_bank_{}", bank_id);
      //   register_stat(s_hcrac_misses_per_bank[bank_id]).name("hcrac_misses_bank_{}", bank_id);
      //   register_stat(s_hcrac_updates_per_bank[bank_id]).name("hcrac_updates_bank_{}", bank_id);
      //   register_stat(s_hcrac_invalidations_per_bank[bank_id]).name("hcrac_invalidations_bank_{}", bank_id);
      //   register_stat(s_hcrac_evictions_per_bank[bank_id]).name("hcrac_evictions_bank_{}", bank_id);
      // }

      register_stat(s_hcrac_hits).name("hcrac_hits_{}", m_channel_id);
      register_stat(s_hcrac_misses).name("hcrac_misses_{}", m_channel_id);
      register_stat(s_hcrac_updates).name("hcrac_updates_{}", m_channel_id);
      register_stat(s_hcrac_invalidations).name("hcrac_invalidations_{}", m_channel_id);
      register_stat(s_hcrac_evictions).name("hcrac_evictions_{}", m_channel_id);

      register_stat(s_read_latency).name("read_latency_{}", m_channel_id);
      register_stat(s_avg_read_latency).name("avg_read_latency_{}", m_channel_id);
    };

    bool send(Request& req) override {
      req.final_command = m_dram->m_request_translations(req.type_id);

      switch (req.type_id) {
        case Request::Type::Read: {
          s_num_read_reqs++;
          break;
        }
        case Request::Type::Write: {
          s_num_write_reqs++;
          break;
        }
        default: {
          s_num_other_reqs++;
          break;
        }
      }

      // Forward existing write requests to incoming read requests
      if (req.type_id == Request::Type::Read) {
        auto compare_addr = [req](const Request& wreq) {
          return wreq.addr == req.addr;
        };
        if (std::find_if(m_write_buffer.begin(), m_write_buffer.end(), compare_addr) != m_write_buffer.end()) {
          // The request will depart at the next cycle
          req.depart = m_clk + 1;
          pending.push_back(req);
          return true;
        }
      }

      // Else, enqueue them to corresponding buffer based on request type id
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
        // We could not enqueue the request
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
      m_clk++;

      // Update statistics
      s_queue_len += m_read_buffer.size() + m_write_buffer.size() + m_priority_buffer.size() + pending.size();
      s_read_queue_len += m_read_buffer.size() + pending.size();
      s_write_queue_len += m_write_buffer.size();
      s_priority_queue_len += m_priority_buffer.size();

      // 1. Serve completed reads
      serve_completed_reads();

      m_refresh->tick();

      // 2. Try to find a request to serve.
      ReqBuffer::iterator req_it;
      ReqBuffer* buffer = nullptr;
      bool request_found = schedule_request(req_it, buffer);

      if (request_found) {
        if (m_is_debug) {
          std::cout << "Request found, command: " << req_it->command << " from core: " << req_it->source_id << " Address Vector: [";
          for (const auto& addr : req_it->addr_vec) {
            std::cout << addr << " ";
          }
          std::cout << "]" << std::endl;
        }
      }

      // 2.0.0. Perform HCRAC invalidation
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

        req_it->scratchpad[0] = 0; // Default to normal request

        int rank = req_it->addr_vec[m_dram->m_levels("rank")];
        int bg = req_it->addr_vec[m_dram->m_levels("bankgroup")];
        int bank = req_it->addr_vec[m_dram->m_levels("bank")];
        int flat_bank_id = rank * (m_dram->get_level_size("bankgroup") * m_dram->get_level_size("bank")) + bg * m_dram->get_level_size("bank") + bank;

        // 1.0 Handle ACTs
        if (command == m_dram->m_commands("ACT") && 
              (req_it->type_id == Request::Type::Read || req_it->type_id == Request::Type::Write) &&
              req_it->source_id >= 0 && req_it->source_id < m_num_cores) {
          // 1.2 Perform HCRAC lookup
          HCRAC* hcrac = m_hcrac[flat_bank_id];
          bool lookup = hcrac->lookup(req_it->addr_vec);
          if (lookup) {
            if (m_is_debug) {
              std::cout << "HCRAC hit for core " << req_it->source_id << std::endl;
            }
            s_hcrac_hits_per_bank[flat_bank_id]++;
            req_it->scratchpad[0] = 1; // HCRAC hit
          } else {
            if (m_is_debug) {
              std::cout << "HCRAC miss for core " << req_it->source_id << std::endl;
            }
            s_hcrac_misses_per_bank[flat_bank_id]++;
          }
        }

        // 2.0 Handle PRE, RDA, and WRA commands
        if (command == m_dram->m_commands("PRE") || command == m_dram->m_commands("RDA") || command == m_dram->m_commands("WRA")) {
          std::vector<AddrVec_t> open_addresses = get_open_addresses(req_it->addr_vec);

          for (auto& addr_vec : open_addresses) {
            if (m_is_debug) {
              std::cout << "Updating HCRAC for bank " << flat_bank_id << " Address Vector: [";
              for (const auto& addr : addr_vec) {
                std::cout << addr << " ";
              }
              std::cout << "]" << std::endl;
            }
            // compute the flat_bank_id using addr_vec
            int rank = addr_vec[m_dram->m_levels("rank")];
            int bg = addr_vec[m_dram->m_levels("bankgroup")];
            int bank = addr_vec[m_dram->m_levels("bank")];
            int flat_bank_id = rank * (m_dram->get_level_size("bankgroup") * m_dram->get_level_size("bank")) + bg * m_dram->get_level_size("bank") + bank;

            HCRAC* hcrac = m_hcrac[flat_bank_id];

            std::tuple<bool, bool> result = hcrac->update(addr_vec);
            if (std::get<1>(result))
              s_hcrac_evictions_per_bank[flat_bank_id]++;
            if (std::get<0>(result))
              s_hcrac_updates_per_bank[flat_bank_id]++;
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
        // If we find a real request to serve
        if (req_it->is_stat_updated == false) {
          update_request_stats(req_it);
        }
        m_dram->issue_command(req_it);

        // If we are issuing the last command, set depart clock cycle and move the request to the pending queue
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
    /**
     * @brief    Helper function to check if a request is hitting an open row
     * @details
     * 
     */
    bool is_row_hit(ReqBuffer::iterator& req)
    {
        return m_dram->check_rowbuffer_hit(req->final_command, req->addr_vec);
    }
    /**
     * @brief    Helper function to check if a request is opening a row
     * @details
     * 
    */
    bool is_row_open(ReqBuffer::iterator& req)
    {
        return m_dram->check_node_open(req->final_command, req->addr_vec);
    }

    std::vector<AddrVec_t> get_open_addresses(AddrVec_t addr_vec)
    {
      return m_dram->get_open_addresses(addr_vec);
    }

    /**
     * @brief    
     * @details
     * 
     */
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

    /**
     * @brief    Helper function to serve the completed read requests
     * @details
     * This function is called at the beginning of the tick() function.
     * It checks the pending queue to see if the top request has received data from DRAM.
     * If so, it finishes this request by calling its callback and poping it from the pending queue.
     */
    void serve_completed_reads() {
      if (pending.size()) {
        // Check the first pending request
        auto& req = pending[0];
        if (req.depart <= m_clk) {
          // Request received data from dram
          if (req.depart - req.arrive > 1) {
            // Check if this requests accesses the DRAM or is being forwarded.
            s_read_latency += req.depart - req.arrive;
          }

          if (req.callback) {
            // If the request comes from outside (e.g., processor), call its callback
            req.callback(req);
          }
          // Finally, remove this request from the pending queue
          pending.pop_front();
        }
      };
    };


    /**
     * @brief    Checks if we need to switch to write mode
     * 
     */
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


    /**
     * @brief    Helper function to find a request to schedule from the buffers.
     * 
     */
    bool schedule_request(ReqBuffer::iterator& req_it, ReqBuffer*& req_buffer) {
      bool request_found = false;
      // 2.1    First, check the act buffer to serve requests that are already activating (avoid useless ACTs)
      if (req_it= m_scheduler->get_best_request(m_active_buffer); req_it != m_active_buffer.end()) {
        if (m_dram->check_ready(req_it->command, req_it->addr_vec)) {
          request_found = true;
          req_buffer = &m_active_buffer;
        }
      }

      // 2.2    If no requests can be scheduled from the act buffer, check the rest of the buffers
      if (!request_found) {
        // 2.2.1    We first check the priority buffer to prioritize e.g., maintenance requests
        if (m_priority_buffer.size() != 0) {
          req_buffer = &m_priority_buffer;
          req_it = m_priority_buffer.begin();
          req_it->command = m_dram->get_preq_command(req_it->final_command, req_it->addr_vec);
          
          request_found = m_dram->check_ready(req_it->command, req_it->addr_vec);
          if (!request_found & m_priority_buffer.size() != 0) {
            return false;
          }
        }

        // 2.2.1    If no request to be scheduled in the priority buffer, check the read and write buffers.
        if (!request_found) {
          // Query the write policy to decide which buffer to serve
          set_write_mode();
          auto& buffer = m_is_write_mode ? m_write_buffer : m_read_buffer;
          if (req_it = m_scheduler->get_best_request(buffer); req_it != buffer.end()) {
            request_found = m_dram->check_ready(req_it->command, req_it->addr_vec);
            req_buffer = &buffer;
          }
        }
      }

      // 2.3 If we find a request to schedule, we need to check if it will close an opened row in the active buffer.
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

      return;
    }

};
  
}   // namespace Ramulator