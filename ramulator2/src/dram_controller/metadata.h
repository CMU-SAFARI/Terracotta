#ifndef     RAMULATOR_CONTROLLER_METADATA_H
#define     RAMULATOR_CONTROLLER_METADATA_H

#include <cstdint>
#include <string>
#include <vector>

#include "base/base.h"
#include "base/utils.h"
#include "dram_controller/controller.h"
#include "dram_controller/hit.h"


namespace Ramulator {

class IMetadata {
    RAMULATOR_REGISTER_INTERFACE(IMetadata, "Metadata", "Metadata Interface");

    protected:
        IDRAMController* m_ctrl = nullptr;
        IDRAM* m_dram = nullptr;

        int m_num_ranks = -1;
        int m_num_banks = -1;
        int m_num_entries = -1;
        bool m_is_debug = false;

        // Compute the tag for a given request iterator
        virtual uint64_t compute_tag(ReqBuffer::iterator& req_it) const = 0;

        // Compute the bank ID for a given request iterator
        virtual uint64_t compute_bank_id(ReqBuffer::iterator& req_it) const = 0;

    public:
        // Update a metadata key-value pair.
        // If value is valid, update or insert the key.
        // If value is invalid (e.g., std::nullopt or a special value), invalidate the key.
        // If eviction is requested, remove the key.
        virtual void update(bool is_hit, bool request_found, ReqBuffer::iterator& req_it) = 0;

        // Perform a lookup return a tuple of hit and and data
        // hit is true if the key exists, false otherwise
        // If hit is true, data is valid and contains the value associated with the key
        virtual hit lookup(bool request_found, ReqBuffer::iterator& req_it) = 0;
};

} // namespace ramulator2


#endif   // RAMULATOR_CONTROLLER_METADATA_H