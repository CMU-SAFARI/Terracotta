#include "base/request.h"

namespace Ramulator {

Request::Request(Addr_t addr, int type): addr(addr), type_id(type) {};

Request::Request(AddrVec_t addr_vec, int type): addr_vec(addr_vec), type_id(type) {};

Request::Request(Addr_t addr, int type, int source_id, std::function<void(Request&)> callback):
addr(addr), type_id(type), source_id(source_id), callback(callback) {};

// Support for RowClone requests
Request::Request(Addr_t addr, Addr_t ext_addr, int type, int source_id, std::function<void(Request&)> callback):
addr(addr), ext_addr(ext_addr), type_id(type), source_id(source_id), callback(callback) {};

Request::Request(AddrVec_t addr_vec, AddrVec_t ext_addr_vec, int type, int source_id, std::function<void(Request&)> callback):
addr_vec(addr_vec), ext_addr_vec(ext_addr_vec), type_id(type), source_id(source_id), callback(callback) {};

Request::Request(AddrVec_t addr_vec, AddrVec_t ext_addr_vec, AddrVec_t real_addr_vec, int type, int source_id, std::function<void(Request&)> callback):
addr_vec(addr_vec), ext_addr_vec(ext_addr_vec), real_addr_vec(real_addr_vec), type_id(type), source_id(source_id), callback(callback) {};

// Support for PuM requests
Request::Request(Addr_t source1_addr, Addr_t source2_addr, Addr_t dest_addr, int type, int source_id, std::function<void(Request&)> callback):
addr(source1_addr), source1_addr(source1_addr), source2_addr(source2_addr), dest_addr(dest_addr), type_id(type), step_id(0), source_id(source_id), callback(callback) {};

}        // namespace Ramulator

