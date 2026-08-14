add_library(ramulator-controller OBJECT)

target_sources(
  ramulator-controller PRIVATE
  bh_controller.h 
  bh_scheduler.h 
  controller.h 
  scheduler.h 
  plugin.h
  refresh.h
  rowpolicy.h
  injector.h
  hit.h
  metadata.h

  impl/bh_dram_controller.cpp
  impl/dummy_controller.cpp
  impl/generic_dram_controller.cpp
  impl/prac_dram_controller.cpp


  impl/chargecache_oracle_controller.cpp
  impl/chargecache_controller.cpp
  impl/terracotta_chargecache_controller.cpp
  impl/chargecache_masa_controller.cpp
  impl/terracotta_chargecache_masa_controller.cpp

  impl/mopac_dram_controller.cpp

  impl/pum_dram_controller.cpp
  
  impl/scheduler/bh_scheduler.cpp
  impl/scheduler/blocking_scheduler.cpp
  impl/scheduler/generic_scheduler.cpp
  impl/scheduler/bliss_scheduler.cpp
  impl/scheduler/prac_scheduler.cpp

  impl/scheduler/pum_scheduler.cpp

  impl/refresh/all_bank_refresh.cpp
  
  impl/rowpolicy/basic_rowpolicies.cpp


  impl/plugin/trace_recorder.cpp
  impl/plugin/cmd_counter.cpp
  impl/plugin/para.cpp
  impl/plugin/graphene.cpp
  impl/plugin/oracle_rh.cpp
  impl/plugin/twice.cpp
  impl/plugin/hydra.cpp
  impl/plugin/rrs.cpp
  impl/plugin/aqua.cpp
  impl/plugin/rfm_manager.cpp

  impl/pluginutil/windowed_counter.cpp
  impl/pluginutil/windowed_counter.h
  impl/pluginutil/self_extending_counter.cpp
  impl/pluginutil/self_extending_counter.h
  impl/plugin/throttleable.h
  impl/plugin/throttleable.cpp
  impl/plugin/dummy_mitigation.cpp

  impl/plugin/blockhammer/blockhammer_throttler.h 
  impl/plugin/blockhammer/blockhammer_util.h 
  impl/plugin/blockhammer/blockhammer.cpp 
  impl/plugin/blockhammer/blockhammer.h 

  impl/plugin/device_config/device_config.cpp 
  impl/plugin/device_config/device_config.h 

  impl/plugin/bliss/bliss.cpp 
  impl/plugin/bliss/bliss.h 

  impl/plugin/prac/prac.cpp 
  impl/plugin/prac/prac.h
  impl/plugin/prac/mopac.cpp
  impl/plugin/prac/terracotta_mopac.cpp
)

target_link_libraries(
  ramulator
  PRIVATE
  ramulator-controller
)