#ifndef     RAMULATOR_CONTROLLER_HIT_H
#define     RAMULATOR_CONTROLLER_HIT_H

#include <cstdint>

namespace Ramulator {

class hit {
    public:
        hit(bool found, uint64_t idx, uint64_t data) : m_found(found), m_idx(idx), m_data(data) {}

        bool found() const { return m_found; }
        uint64_t index() const { return m_idx; }
        uint64_t data() const { return m_data; }

    private:
        bool m_found;
        uint64_t m_idx;
        uint64_t m_data;
};

} // namespace ramulator2


#endif   // RAMULATOR_CONTROLLER_HIT_H