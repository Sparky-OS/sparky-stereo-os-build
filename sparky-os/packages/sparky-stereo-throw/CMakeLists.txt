# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later
cmake_minimum_required(VERSION 3.22)
project(sparky-stereo-throw VERSION 0.3.0)

set(QT_MIN_VERSION "6.8.0")
set(KF_MIN_VERSION "6.10.0")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Gui Network DBus Quick Qml)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS CoreAddons Config I18n DNSSD Notifications KCMUtils)
find_package(KPipeWire REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(AV REQUIRED IMPORTED_TARGET libavformat libavcodec libavutil)
pkg_check_modules(PIPEWIRE REQUIRED IMPORTED_TARGET libpipewire-0.3)
pkg_check_modules(WAYLAND REQUIRED IMPORTED_TARGET wayland-client)
pkg_check_modules(PROBLEMS REQUIRED IMPORTED_TARGET sparky-stereo-problems)

add_definitions(-DTRANSLATION_DOMAIN=\"sparky-stereo-throw\")

add_subdirectory(src)
if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/kcm/CMakeLists.txt)
    add_subdirectory(kcm)
endif()
if(BUILD_TESTING)
    add_subdirectory(tests)
endif()

ki18n_install(po)
install(FILES data/devices.json DESTINATION ${KDE_INSTALL_DATADIR}/sparky-stereo-throw)
install(FILES data/sparkystereothrow.notifyrc DESTINATION ${KDE_INSTALL_KNOTIFYRCDIR})
# KWin gives zkde_screencast_unstable_v1 to the program whose desktop file's Exec names it (canonical path) and lists the
# interface in X-KDE-Wayland-Interfaces (KWin src/utils/serviceutils.h, fetchProcessServiceField)
configure_file(data/org.sparky.throw.desktop.in org.sparky.throw.desktop @ONLY)
configure_file(data/sparky-stereo-throw.service.in sparky-stereo-throw.service @ONLY)
configure_file(data/org.sparky.Throw.service.in org.sparky.Throw.service @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/org.sparky.throw.desktop DESTINATION ${KDE_INSTALL_APPDIR})
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/sparky-stereo-throw.service DESTINATION lib/systemd/user)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/org.sparky.Throw.service DESTINATION ${KDE_INSTALL_DBUSSERVICEDIR})
install(FILES man/sparky-stereo-throw.1 DESTINATION share/man/man1)
