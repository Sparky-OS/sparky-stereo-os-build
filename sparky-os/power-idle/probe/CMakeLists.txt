cmake_minimum_required(VERSION 3.16)
project(PowerIdleSettingsProbe LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_AUTOMOC ON)
find_package(ECM REQUIRED NO_MODULE)
list(APPEND CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
find_package(Qt6 REQUIRED COMPONENTS Core DBus)
find_package(KF6Config REQUIRED)

if(NOT EXISTS "${POWERDEVIL_SOURCE}/PowerDevilProfileSettings.kcfg")
    message(FATAL_ERROR "Pass POWERDEVIL_SOURCE pointing to the inspected PowerDevil checkout")
endif()
if(NOT EXISTS "${PLASMA_WORKSPACE_SOURCE}/components/sessionsprivate/kscreensaversettings.kcfgc")
    message(FATAL_ERROR "Pass PLASMA_WORKSPACE_SOURCE pointing to the inspected Plasma Workspace checkout")
endif()

# Only the library export decoration is supplied by the standalone probe.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/powerdevilcore_export.h" "#define POWERDEVILCORE_EXPORT\n")
set(probe_sources
    main.cpp
    "${POWERDEVIL_SOURCE}/daemon/powerdevilsettingsdefaults.cpp"
    "${POWERDEVIL_SOURCE}/daemon/powerdevilenums.h"
)
kconfig_add_kcfg_files(probe_sources
    "${POWERDEVIL_SOURCE}/PowerDevilProfileSettings.kcfgc"
    "${PLASMA_WORKSPACE_SOURCE}/components/sessionsprivate/kscreensaversettings.kcfgc"
    GENERATE_MOC
)
add_executable(settings-probe ${probe_sources})
target_include_directories(settings-probe PRIVATE
    "${CMAKE_CURRENT_BINARY_DIR}"
    "${POWERDEVIL_SOURCE}/daemon"
)
target_link_libraries(settings-probe PRIVATE Qt6::Core Qt6::DBus KF6::ConfigCore KF6::ConfigGui)

option(BUILD_TIMELINE_PROBE "Build the hardware-specific timeline reader" OFF)
if(BUILD_TIMELINE_PROBE)
    add_executable(timeline-hardware hardware.cpp)
    target_link_libraries(timeline-hardware PRIVATE Qt6::Core Qt6::DBus)
    find_package(KF6Solid REQUIRED)
    target_link_libraries(settings-probe PRIVATE KF6::Solid)
    list(REMOVE_ITEM probe_sources main.cpp)
    add_executable(timeline-probe timeline.cpp ${probe_sources})
    target_include_directories(timeline-probe PRIVATE "${CMAKE_CURRENT_BINARY_DIR}" "${POWERDEVIL_SOURCE}/daemon")
    target_link_libraries(timeline-probe PRIVATE Qt6::Core Qt6::DBus KF6::ConfigCore KF6::ConfigGui KF6::Solid)
endif()
