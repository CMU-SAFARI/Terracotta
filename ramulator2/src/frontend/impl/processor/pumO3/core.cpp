#include <filesystem>
#include <iostream>
#include <fstream>
#include <stdexcept>

#include <spdlog/spdlog.h>

#include "base/exception.h"
#include "base/utils.h"
#include "frontend/impl/processor/pumO3/core.h"
#include "frontend/impl/processor/pumO3/llc.h"

namespace Ramulator {

namespace fs = std::filesystem;

PuMO3Core::Trace::Trace(std::string file_path_str) {
  fs::path trace_path(file_path_str);
  if (!fs::exists(trace_path)) {
    throw ConfigurationError("Trace {} does not exist!", file_path_str);
  }

  std::ifstream trace_file(trace_path);
  if (!trace_file.is_open()) {
    throw ConfigurationError("Trace {} cannot be opened!", file_path_str);
  }

  std::string line;
  while (std::getline(trace_file, line)) {
    std::vector<std::string> tokens;
    tokenize(tokens, line, " ");

    int num_tokens = tokens.size();
    if (num_tokens != 7) {
      throw ConfigurationError("Trace {} format invalid!", file_path_str);
    }
    int bubble_count = std::stoi(tokens[0]);
    int type = std::stoi(tokens[1]);
    Addr_t load_addr = std::stoll(tokens[2]);
    Addr_t store_addr = std::stoll(tokens[3]);
    Addr_t source1_addr = std::stoll(tokens[4]);
    Addr_t source2_addr = std::stoll(tokens[5]);
    Addr_t dest_addr = std::stoll(tokens[6]);

    m_trace.push_back({bubble_count, type, load_addr, store_addr, source1_addr, source2_addr, dest_addr});
  }

  trace_file.close();
  m_trace_length = m_trace.size();
}

int PuMO3Core::Trace::num_instructions() {
  int num_instructions = 0;
  for (const auto& inst : m_trace) {
    num_instructions += inst.bubble_count;
    if (inst.type == 0) {
      num_instructions += (inst.load_addr != -1) + (inst.store_addr != -1);
    } else if (inst.type == 1 || inst.type == 2) {
      num_instructions += 1;
    } else {
      throw std::runtime_error("Only LD/ST instructions are supported in the PuMO3 core model right now!");
    }
  }
  return num_instructions;
}

const PuMO3Core::Trace::Inst& PuMO3Core::Trace::get_next_inst() {
  const Inst& inst = m_trace[m_curr_trace_idx];
  m_curr_trace_idx = (m_curr_trace_idx + 1) % m_trace_length;
  return inst;
}

PuMO3Core::InstWindow::InstWindow(int ipc, int depth):
m_ipc(ipc), m_depth(depth),
m_ready_list(depth, false), m_addr_list(depth, -1), m_depart_list(depth, -1) {};

bool PuMO3Core::InstWindow::is_full() {
  return m_load == m_depth;
}

void PuMO3Core::InstWindow::insert(bool ready, Addr_t addr, Clk_t clk) {
  m_ready_list.at(m_head_idx) = ready;
  m_addr_list.at(m_head_idx) = addr;
  m_depart_list.at(m_head_idx) = clk;

  m_head_idx = (m_head_idx + 1) % m_depth;
  m_load++;
}

int PuMO3Core::InstWindow::retire() {
  if (m_load == 0) return 0;

  int num_retired = 0;
  while (m_load > 0 && num_retired < m_ipc) {
    if (!m_ready_list.at(m_tail_idx))
      break;

    m_tail_idx = (m_tail_idx + 1) % m_depth;
    m_load--;
    num_retired++;
  }
  return num_retired;
}

Clk_t PuMO3Core::InstWindow::set_ready(Addr_t addr) {
  if (m_load == 0) return std::numeric_limits<Clk_t>::max();

  int index = m_tail_idx;
  Clk_t min = std::numeric_limits<Clk_t>::max();
  for (int i = 0; i < m_load; i++) {
    if (m_addr_list[index] == addr) {
      m_ready_list[index] = true;
      if (m_depart_list[index] < min) {
        min = m_depart_list[index];
      }
    }
    index++;
    if (index == m_depth) {
      index = 0;
    }
  }
  return min;
}

PuMO3Core::PuMO3Core(int id, int ipc, int depth, size_t num_iterations, std::string trace_path, std::string operation, ITranslation* translation, PuMO3LLC* llc, int lat_hist_sens, std::string& dump_path):
m_id(id), m_window(ipc, depth), m_trace(trace_path), m_operation(operation), m_translation(translation), m_llc(llc), m_lat_hist_sens(lat_hist_sens) {
  m_num_expected_insts = num_iterations * m_trace.num_instructions();
  
  // Fetch the instructions and addresses for tick 0
  auto inst = m_trace.get_next_inst();
  m_num_bubbles = inst.bubble_count;
  m_type = inst.type;
  m_load_addr = inst.load_addr;
  m_writeback_addr = inst.store_addr;
  m_source1_addr = inst.source1_addr;
  m_source2_addr = inst.source2_addr;
  m_dest_addr = inst.dest_addr;
  if (dump_path == "") {
    return;
  }
  m_dump_path = fmt::format("{}.core{}", dump_path, id);
  auto parent_path = m_dump_path.parent_path();
  if (!parent_path.empty()) {
    std::filesystem::create_directories(parent_path);
    if (!(std::filesystem::exists(parent_path) && std::filesystem::is_directory(parent_path))) {
      throw ConfigurationError("Invalid path to latency dump file: {}", parent_path.string());
    }
  }
}

void PuMO3Core::tick() {
  m_clk++;

  s_insts_retired += m_window.retire();
  if (!reached_expected_num_insts) {
    if (s_insts_retired >= m_num_expected_insts) {
      dump_latency_histogram();
      reached_expected_num_insts = true;
      s_cycles_recorded = m_clk;
    }
  }

  // First, issue the non-memory instructions
  int num_inserted_insts = 0;
  while (m_num_bubbles > 0) {
    if (num_inserted_insts == m_window.m_ipc) {
      return;
    }
    if (m_window.is_full()) {
      return;
    };
    m_window.insert(true, -1, -1);
    num_inserted_insts++;
    m_num_bubbles--;
  }

  // Handle LDST requests
  if (m_type == 0) {
    // Second, try to send the load to the LLC
    if (m_load_addr != -1) {
      if (num_inserted_insts == m_window.m_ipc) {
        return;
      }
      if (m_window.is_full()) {
        return;
      };

      Request load_request(m_load_addr, Request::Type::Read, m_id, m_callback);
      if (!m_translation->translate(load_request)) {
        return;
      };

      if (m_llc->send(load_request)) {
        s_mem_requests_issued++;
        m_window.insert(false, load_request.addr, m_clk);
        m_load_addr = -1;
        if (m_writeback_addr != -1) {
          // If there is still writeback, return without getting the next trace line
          // The write back will be issued in the next cycle
          // TODO: Should we allow both load and writeback to issue at the same cycle?
          return;
        }
      } else {
        return;
      }
    }

    // Third, try to send the writeback to the LLC
    if (m_writeback_addr != -1) {
      Request writeback_request(m_writeback_addr, Request::Type::Write, m_id, m_callback);
      if (!m_translation->translate(writeback_request)) {
        return;
      };
      if (!m_llc->send(writeback_request)) {
        return;
      }
      s_mem_requests_issued++;
    }
  } else if (m_type == 1) {
    // Two input PuM instructions
    if (m_operation == "andor" || m_operation == "xorxnor" || m_operation == "nandnor") {
      if (num_inserted_insts == m_window.m_ipc) {
        return;
      }
      if (m_window.is_full()) {
        return;
      };

      if (m_source1_addr == -1 || m_source2_addr == -1 || m_dest_addr == -1) {
        throw std::runtime_error("Source and destination addresses cannot be -1 for type 1 operations in PuMO3 core model!");
      }

      Request pum_request(-1, Request::Type::Read); // Dummy initialization
      if (m_operation == "andor") {
        pum_request = Request(m_source1_addr, m_source2_addr, m_dest_addr, Request::Type::AND_OR, m_id, m_callback);
      } else if (m_operation == "xorxnor") {
        pum_request = Request(m_source1_addr, m_source2_addr, m_dest_addr, Request::Type::XOR_XNOR, m_id, m_callback);
      } else if (m_operation == "nandnor") {
        pum_request = Request(m_source1_addr, m_source2_addr, m_dest_addr, Request::Type::NAND_NOR, m_id, m_callback);
      } else {
        throw std::runtime_error("Invalid operation for type 1 instructions in PuMO3 core model!");
      }

      if (!m_translation->translate(pum_request)) {
        return;
      };

      if (m_llc->send(pum_request)) {
        s_mem_requests_issued++;
        m_window.insert(false, pum_request.addr, m_clk);
        m_source1_addr = -1;
        m_source2_addr = -1;
        m_dest_addr = -1;
      } else {
        return;
      }
    } else {
      throw std::runtime_error("Only AND/OR, XOR/XNOR, NAND/NOR operations are supported in the type 1 operations for PuMO3 core model right now!");
    }

  } else if (m_type == 2) {
    // One-input PuM instructions
    if (m_operation == "copy" || m_operation == "not") {
      if (num_inserted_insts == m_window.m_ipc) {
        return;
      }
      if (m_window.is_full()) {
        return;
      };

      if (m_source1_addr == -1 || m_dest_addr == -1) {
        throw std::runtime_error("Source and destination addresses cannot be -1 for type 2 operations in PuMO3 core model!");
      }

      Request pum_request(-1, Request::Type::Read); // Dummy initialization
      if (m_operation == "copy") {
        pum_request = Request(m_source1_addr, -1, m_dest_addr, Request::Type::RowClone, m_id, m_callback);
      } else if (m_operation == "not") {
        pum_request = Request(m_source1_addr, -1, m_dest_addr, Request::Type::NOT, m_id, m_callback);
      } else {
        throw std::runtime_error("Invalid operation for type 2 instructions in PuMO3 core model!");
      }

      if (!m_translation->translate(pum_request)) {
        return;
      };
      
      if (m_llc->send(pum_request)) {
        s_mem_requests_issued++;
        m_window.insert(false, pum_request.addr, m_clk);
        m_source1_addr = -1;
        m_dest_addr = -1;
      } else {
        return;
      }
    } else {
      throw std::runtime_error("Only copy and not operations are supported in the type 2 operations for PuMO3 core model right now!");
    }
  } else {
    throw std::runtime_error("Only LD/ST instructions are supported in the PuMO3 core model right now!");
  }

  auto inst = m_trace.get_next_inst();
  m_num_bubbles = inst.bubble_count;
  m_type = inst.type;
  m_load_addr = inst.load_addr;
  m_writeback_addr = inst.store_addr;
  m_source1_addr = inst.source1_addr;
  m_source2_addr = inst.source2_addr;
  m_dest_addr = inst.dest_addr;
}

void PuMO3Core::receive(Request& req) {
  Clk_t depart = m_window.set_ready(req.addr);
  Clk_t arrive = m_clk;
  int req_duration = arrive - depart;

  if (!reached_expected_num_insts && depart != std::numeric_limits<Clk_t>::max()) {
    s_mem_access_cycles += req_duration;
    m_last_mem_cycle = depart;
    int lat_bucket = req_duration - (req_duration % m_lat_hist_sens);
    if (m_lat_histogram.find(lat_bucket) == m_lat_histogram.end()) {
      m_lat_histogram[lat_bucket] = 0;
    }
    m_lat_histogram[lat_bucket]++;
  }
}

void PuMO3Core::dump_latency_histogram() {
  if (m_dump_path == "") {
    return;
  }
  std::ofstream output(m_dump_path);
  for (const auto& [bucket_base, count] : m_lat_histogram) {
    output << fmt::format("{}, {}", bucket_base, count) << std::endl;
  }
  output.close();
}

}        // namespace Ramulator
