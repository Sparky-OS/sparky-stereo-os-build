# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later
set(XML /usr/share/plasma-wayland-protocols/zkde-screencast-unstable-v1.xml)
add_custom_command(OUTPUT zkde-screencast-unstable-v1-client-protocol.h
    COMMAND wayland-scanner client-header ${XML} zkde-screencast-unstable-v1-client-protocol.h DEPENDS ${XML})
add_custom_command(OUTPUT zkde-screencast-unstable-v1-protocol.c
    COMMAND wayland-scanner private-code ${XML} zkde-screencast-unstable-v1-protocol.c DEPENDS ${XML})

add_library(throwcore STATIC
    castmessage.cpp castchannel.cpp devicetable.cpp discovery.cpp networkscreen.cpp streamer.cpp tell.cpp
    throwsession.cpp daemon.cpp logging.cpp
    zkde-screencast-unstable-v1-client-protocol.h zkde-screencast-unstable-v1-protocol.c)
target_include_directories(throwcore PUBLIC ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR})
target_link_libraries(throwcore PUBLIC Qt6::Core Qt6::Gui Qt6::Network Qt6::DBus KF6::ConfigCore KF6::I18n KF6::DNSSD
    KF6::Notifications K::KPipeWire K::KPipeWireRecord PkgConfig::AV PkgConfig::WAYLAND PkgConfig::PROBLEMS)
set_target_properties(throwcore PROPERTIES POSITION_INDEPENDENT_CODE ON)

add_executable(sparky-stereo-throwd main.cpp)
target_link_libraries(sparky-stereo-throwd throwcore)
install(TARGETS sparky-stereo-throwd DESTINATION ${KDE_INSTALL_LIBEXECDIR})

add_executable(sparky-stereo-throw cli.cpp)
target_link_libraries(sparky-stereo-throw Qt6::Core Qt6::DBus KF6::I18n)
install(TARGETS sparky-stereo-throw ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
