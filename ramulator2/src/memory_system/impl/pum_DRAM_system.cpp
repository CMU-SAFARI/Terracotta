#include "memory_system/memory_system.h"
#include "translation/translation.h"
#include "dram_controller/controller.h"
#include "addr_mapper/addr_mapper.h"
#include "dram/dram.h"

namespace Ramulator {

class PuMDRAMSystem final : public IMemorySystem, public Implementation {
  RAMULATOR_REGISTER_IMPLEMENTATION(IMemorySystem, PuMDRAMSystem, "PuMDRAM", " DRAM-based memory system that supports PuM.");

  protected:
    Clk_t m_clk = 0;
    IDRAM*  m_dram;
    IAddrMapper*  m_addr_mapper;
    std::vector<IDRAMController*> m_controllers;

  public:
    int s_num_read_requests_queued = 0;
    int s_num_write_requests_queued = 0;
    int s_num_other_requests_queued = 0;

    int s_num_read_requests_attempted = 0;
    int s_num_write_requests_attempted = 0;
    int s_num_other_requests_attempted = 0;

    int s_num_pum_requests_queued = 0;        // Count of PuM requests queued
    int s_num_pum_requests_attempted = 0;     // Count of PuM requests attempted

  public:
    void init() override { 
      // Create device (a top-level node wrapping all channel nodes)
      m_dram = create_child_ifce<IDRAM>();
      m_addr_mapper = create_child_ifce<IAddrMapper>();

      int num_channels = m_dram->get_level_size("channel");   

      // Create memory controllers
      for (int i = 0; i < num_channels; i++) {
        IDRAMController* controller = create_child_ifce<IDRAMController>();
        controller->m_impl->set_id(fmt::format("Channel {}", i));
        controller->m_channel_id = i;
        m_controllers.push_back(controller);
      }

      m_clock_ratio = param<uint>("clock_ratio").required();

      register_stat(m_clk).name("memory_system_cycles");
      register_stat(s_num_read_requests_queued).name("total_num_read_requests_queued");
      register_stat(s_num_write_requests_queued).name("total_num_write_requests_queued");
      register_stat(s_num_other_requests_queued).name("total_num_other_requests_queued");
      register_stat(s_num_read_requests_attempted).name("total_num_read_requests_attempted");
      register_stat(s_num_write_requests_attempted).name("total_num_write_requests_attempted");
      register_stat(s_num_other_requests_attempted).name("total_num_other_requests_attempted");


      // Registers RowClone stat
      register_stat(s_num_pum_requests_queued).name("total_num_pum_requests_queued");
      register_stat(s_num_pum_requests_attempted).name("total_num_pum_requests_attempted");

    };

    void setup(IFrontEnd* frontend, IMemorySystem* memory_system) override { }

    bool send(Request req) override {
      m_addr_mapper->apply(req);
      int channel_id = req.addr_vec[0];
      bool is_success = m_controllers[channel_id]->send(req);

      if (is_success) {
        switch (req.type_id) {
          case Request::Type::Read: {
            s_num_read_requests_queued++;
            break;
          }
          case Request::Type::Write: {
            s_num_write_requests_queued++;
            break;
          }
          // Count PuM requests
          case Request::Type::RowClone: 
          case Request::Type::NOT:
          case Request::Type::AND_OR:
          case Request::Type::XOR_XNOR:
          case Request::Type::NAND_NOR: {
            s_num_pum_requests_queued++;
            break;
          }
          default: {
            s_num_other_requests_queued++;
            break;
          }
        }
      }

      return is_success;
    };
    
    void tick() override {
      m_clk++;
      m_dram->tick();
      for (auto controller : m_controllers) {
        controller->tick();
      }
    };

    float get_tCK() override {
      return m_dram->m_timing_vals("tCK_ps") / 1000.0f;
    }

    // const SpecDef& get_supported_requests() override {
    //   return m_dram->m_requests;
    // };
};
  
}   // namespace 

