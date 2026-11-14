# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
cmake_minimum_required(VERSION 3.22)
project(sparky-stereo-graphics VERSION 0.2.10)

set(QT_MIN_VERSION "6.8.0")
set(KF_MIN_VERSION "6.10.0")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMQmlModule)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core DBus Quick)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS Auth Config CoreAddons I18n KCMUtils)
find_package(PkgConfig REQUIRED)
pkg_check_modules(PROBLEMS REQUIRED IMPORTED_TARGET GLOBAL sparky-stereo-problems)

add_definitions(-DTRANSLATION_DOMAIN=\"kcm_sparkystereo_graphics\")

add_subdirectory(src)
add_subdirectory(src/helper)

if(BUILD_TESTING)
    find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Test)
    find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS Service)
    find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Quick)
    add_subdirectory(autotests)
endif()

install(PROGRAMS share/sparky-stereo-gpu-run DESTINATION ${KDE_INSTALL_BINDIR})
install(FILES share/plasma-env/sparky-stereo-graphics.sh DESTINATION /etc/xdg/plasma-workspace/env)
file(GLOB SPARKY_MACHINES share/machines/*.conf)
install(FILES ${SPARKY_MACHINES} DESTINATION ${KDE_INSTALL_DATADIR}/sparky-stereo-graphics/machines)
install(FILES share/systemd/sparky-stereo-gpu-record.service DESTINATION ${KDE_INSTALL_SYSTEMDUNITDIR}/system)
install(FILES share/systemd/user/sparky-stereo-gpu-died@.service share/systemd/user/sparky-stereo-gpu-survived@.service DESTINATION ${KDE_INSTALL_SYSTEMDUNITDIR}/user)
install(FILES share/systemd/user/app-.service.d/10-sparky-stereo-graphics.conf DESTINATION ${KDE_INSTALL_SYSTEMDUNITDIR}/user/app-.service.d)

if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/po)
    ki18n_install(po)
endif()
