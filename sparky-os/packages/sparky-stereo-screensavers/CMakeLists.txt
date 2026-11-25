# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later
cmake_minimum_required(VERSION 3.22)
project(sparky-stereo-screensavers VERSION 0.1.0 LANGUAGES C CXX)

set(QT_MIN_VERSION "6.8.0")
set(KF_MIN_VERSION "6.10.0")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
include(ECMQmlModule)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Gui Quick)
find_package(Qt6GuiPrivate ${QT_MIN_VERSION} REQUIRED NO_MODULE)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS Config CoreAddons I18n KCMUtils)
find_package(PkgConfig REQUIRED)
pkg_check_modules(STEREODECLARE REQUIRED IMPORTED_TARGET stereo-declare>=1.12.2)
pkg_check_modules(WAYLAND REQUIRED IMPORTED_TARGET wayland-client)
pkg_get_variable(WAYLAND_PROTOCOLS_DIR wayland-protocols pkgdatadir)
find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)

add_definitions(-DTRANSLATION_DOMAIN=\"kcm_sparkystereo_screensavers\")
set(SAVER_HELPER_DIR lib/sparky-stereo-screensavers)
add_definitions(-DSAVER_HELPER=\"${CMAKE_INSTALL_PREFIX}/${SAVER_HELPER_DIR}/sparky-saver-preview\")

add_subdirectory(src)

if(BUILD_TESTING)
    find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Test)
    add_subdirectory(autotests)
endif()

ki18n_install(po)
install(PROGRAMS helper/sparky-saver-preview DESTINATION ${SAVER_HELPER_DIR})
install(FILES org.sparky.stereo-savers.desktop DESTINATION ${KDE_INSTALL_APPDIR})
