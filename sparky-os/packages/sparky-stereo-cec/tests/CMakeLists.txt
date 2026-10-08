# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
find_package(PkgConfig REQUIRED)
pkg_check_modules(WaylandServer REQUIRED IMPORTED_TARGET wayland-server)
find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)
if(NOT DPMS_PROTOCOL)
    set(DPMS_PROTOCOL /usr/share/plasma-wayland-protocols/dpms.xml)
endif()
add_custom_command(OUTPUT dpms-server.h dpms-code.c
    COMMAND ${WAYLAND_SCANNER} server-header ${DPMS_PROTOCOL} dpms-server.h
    COMMAND ${WAYLAND_SCANNER} private-code ${DPMS_PROTOCOL} dpms-code.c
    DEPENDS ${DPMS_PROTOCOL})
add_executable(cec-test-server server.cpp dpms-code.c dpms-server.h)
target_include_directories(cec-test-server PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
target_link_libraries(cec-test-server PRIVATE Qt6::Core PkgConfig::WaylandServer)
add_library(cec-test-ioctl SHARED ioctl.c)
set_target_properties(cec-test-ioctl PROPERTIES AUTOMOC OFF)
target_link_libraries(cec-test-ioctl PRIVATE dl)
add_executable(cec-test test.cpp)
target_link_libraries(cec-test PRIVATE cec-controller Qt6::Test)
add_executable(cec-vivid-test vivid.cpp)
target_link_libraries(cec-vivid-test PRIVATE cec-adapter)
