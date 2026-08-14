#ifndef     RAMULATOR_CONTROLLER_INJECTOR_H
#define     RAMULATOR_CONTROLLER_INJECTOR_H

#include <vector>
#include <string>

#include "base/base.h"


namespace Ramulator {

class IInjector {
  RAMULATOR_REGISTER_INTERFACE(IInjector, "Injector", "Injector Interface.");

  public:
    virtual void tick() = 0;
};

}        // namespace Ramulator


#endif   // RAMULATOR_CONTROLLER_INJECTOR_H