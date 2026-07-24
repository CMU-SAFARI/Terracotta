#include <vector>

#include "base/base.h"
#include "dram/dram.h"
#include "addr_mapper/addr_mapper.h"
#include "memory_system/memory_system.h"

namespace Ramulator {

class LinearMapperBase : public IAddrMapper {
  public:
    IDRAM* m_dram = nullptr;

    int m_num_levels = -1;          // How many levels in the hierarchy?
    std::vector<int> m_addr_bits;   // How many address bits for each level in the hierarchy?
    Addr_t m_tx_offset = -1;

    int m_col_bits_idx = -1;
    int m_row_bits_idx = -1;


  protected:
    void setup(IFrontEnd* frontend, IMemorySystem* memory_system) {
      m_dram = memory_system->get_ifce<IDRAM>();

      // Populate m_addr_bits vector with the number of address bits for each level in the hierachy
      const auto& count = m_dram->m_organization.count;
      m_num_levels = count.size();
      m_addr_bits.resize(m_num_levels);
      for (size_t level = 0; level < m_addr_bits.size(); level++) {
        m_addr_bits[level] = calc_log2(count[level]);
      }

      // Last (Column) address have the granularity of the prefetch size
      m_addr_bits[m_num_levels - 1] -= calc_log2(m_dram->m_internal_prefetch_size);

      int tx_bytes = m_dram->m_internal_prefetch_size * m_dram->m_channel_width / 8;
      m_tx_offset = calc_log2(tx_bytes);

      // Determine where are the row and col bits for ChRaBaRoCo and RoBaRaCoCh
      try {
        m_row_bits_idx = m_dram->m_levels("row");
      } catch (const std::out_of_range& r) {
        throw std::runtime_error(fmt::format("Organization \"row\" not found in the spec, cannot use linear mapping!"));
      }

      // Assume column is always the last level
      m_col_bits_idx = m_num_levels - 1;
    }

    virtual AddrVec_t map(Addr_t addr) {
      AddrVec_t addr_vec(m_num_levels, -1);
      
      if (addr != -1) {
        addr = addr >> m_tx_offset;
        for (int i = m_addr_bits.size() - 1; i >= 0; i--) {
          addr_vec[i] = slice_lower_bits(addr, m_addr_bits[i]);
        }
      }

      return addr_vec;
    }

    void apply(Request& req)  {
      req.addr_vec = map(req.addr);
      req.ext_addr_vec = map(req.ext_addr);
      req.real_addr_vec = map(req.real_addr);
      req.source1_addr_vec = map(req.source1_addr);
      req.source2_addr_vec = map(req.source2_addr);
      req.dest_addr_vec = map(req.dest_addr);
    }
};


class ChRaBaRoCo final : public LinearMapperBase, public Implementation {
  RAMULATOR_REGISTER_IMPLEMENTATION(IAddrMapper, ChRaBaRoCo, "ChRaBaRoCo", "Applies a trival mapping to the address.");

  public:
    void init() override { };

    void setup(IFrontEnd* frontend, IMemorySystem* memory_system) override {
      LinearMapperBase::setup(frontend, memory_system);
    }

    AddrVec_t map(Addr_t addr) override {
      AddrVec_t addr_vec(m_num_levels, -1);

      if (addr != -1) {
        addr = addr >> m_tx_offset;
        for (int i = m_addr_bits.size() - 1; i >= 0; i--) {
          addr_vec[i] = slice_lower_bits(addr, m_addr_bits[i]);
        }
      }
      return addr_vec;
    }
};


class RoBaRaCoCh final : public LinearMapperBase, public Implementation {
  RAMULATOR_REGISTER_IMPLEMENTATION(IAddrMapper, RoBaRaCoCh, "RoBaRaCoCh", "Applies a RoBaRaCoCh mapping to the address.");

  public:
    void init() override { };

    void setup(IFrontEnd* frontend, IMemorySystem* memory_system) override {
      LinearMapperBase::setup(frontend, memory_system);
    }

    AddrVec_t map(Addr_t addr) override {
      AddrVec_t addr_vec(m_num_levels, -1);
      
      if (addr != -1) {
        addr = addr >> m_tx_offset;
        addr_vec[0] = slice_lower_bits(addr, m_addr_bits[0]);
        addr_vec[m_addr_bits.size() - 1] = slice_lower_bits(addr, m_addr_bits[m_addr_bits.size() - 1]);
        for (int i = 1; i <= m_row_bits_idx; i++) {
          addr_vec[i] = slice_lower_bits(addr, m_addr_bits[i]);
        }
      }

      return addr_vec;
    }
};


class RoRaBaChCo final : public LinearMapperBase, public Implementation {
  RAMULATOR_REGISTER_IMPLEMENTATION(IAddrMapper, RoRaBaChCo, "RoRaBaChCo", "Applies a RoRaBaChCo mapping to the address.");

  public:
    void init() override { };

    void setup(IFrontEnd* frontend, IMemorySystem* memory_system) override {
      LinearMapperBase::setup(frontend, memory_system);
    }

    AddrVec_t map(Addr_t addr) override {
      AddrVec_t addr_vec(m_num_levels, -1);

      if (addr != -1) {
        addr = addr >> m_tx_offset;
        addr_vec[m_col_bits_idx] = slice_lower_bits(addr, m_addr_bits[m_col_bits_idx]);
        addr_vec[0] = slice_lower_bits(addr, m_addr_bits[0]);

        // Bank bits
        int m_bg_bits_idx = 2;
        int m_bank_bits_idx = 3;
        addr_vec[m_bg_bits_idx] = slice_lower_bits(addr, m_addr_bits[m_bg_bits_idx]);
        addr_vec[m_bank_bits_idx] = slice_lower_bits(addr, m_addr_bits[m_bank_bits_idx]);
        
        // Rank bits
        int m_rank_bits_idx = 1;
        addr_vec[m_rank_bits_idx] = slice_lower_bits(addr, m_addr_bits[m_rank_bits_idx]);
        addr_vec[m_row_bits_idx] = slice_lower_bits(addr, m_addr_bits[m_row_bits_idx]);

        // The rest of the bits
        for (int i = 0; i < m_num_levels; i++) {
          if (i != m_col_bits_idx && i != m_row_bits_idx && i != m_bank_bits_idx && i != m_bg_bits_idx && i != m_rank_bits_idx && i != 0) {
            addr_vec[i] = slice_lower_bits(addr, m_addr_bits[i]);
          }
        }
      }

      return addr_vec;
    }
};


class MOP4CLXOR final : public LinearMapperBase, public Implementation {
  RAMULATOR_REGISTER_IMPLEMENTATION(IAddrMapper, MOP4CLXOR, "MOP4CLXOR", "Applies a MOP4CLXOR mapping to the address.");

  public:
    void init() override { };

    void setup(IFrontEnd* frontend, IMemorySystem* memory_system) override {
      LinearMapperBase::setup(frontend, memory_system);
    }

    AddrVec_t map(Addr_t addr) override {
      AddrVec_t addr_vec(m_num_levels, -1);
      
      if (addr != -1) {
        addr = addr >> m_tx_offset;
        addr_vec[m_col_bits_idx] = slice_lower_bits(addr, 2);
        for (int lvl = 0 ; lvl < m_row_bits_idx ; lvl++)
            addr_vec[lvl] = slice_lower_bits(addr, m_addr_bits[lvl]);
        addr_vec[m_col_bits_idx] += slice_lower_bits(addr, m_addr_bits[m_col_bits_idx]-2) << 2;
        addr_vec[m_row_bits_idx] = (int) addr;

        int row_xor_index = 0; 
        for (int lvl = 0 ; lvl < m_col_bits_idx ; lvl++){
          if (m_addr_bits[lvl] > 0){
            int mask = (addr_vec[m_col_bits_idx] >> row_xor_index) & ((1<<m_addr_bits[lvl])-1);
            addr_vec[lvl] = addr_vec[lvl] xor mask;
            row_xor_index += m_addr_bits[lvl];
          }
        }
      }
      
      return addr_vec;
    }
};

}   // namespace Ramulator