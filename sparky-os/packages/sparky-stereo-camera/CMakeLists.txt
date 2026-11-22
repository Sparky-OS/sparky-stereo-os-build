# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
cmake_minimum_required(VERSION 3.22)
project(sparky-stereo-camera VERSION 0.1.2)

set(QT_MIN_VERSION "6.8.0")
set(KF_MIN_VERSION "6.10.0")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMQmlModule)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Gui Quick Multimedia)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS CoreAddons I18n KCMUtils)
find_package(PkgConfig REQUIRED)
pkg_check_modules(STEREOPOLICY REQUIRED IMPORTED_TARGET stereo-policy>=1.23.2)
pkg_check_modules(PIPEWIRE REQUIRED IMPORTED_TARGET libpipewire-0.3 libspa-0.2)

add_definitions(-DTRANSLATION_DOMAIN=\"kcm_sparkystereo_camera\")

add_subdirectory(src)

if(BUILD_TESTING)
    find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Test)
    add_subdirectory(autotests)
endif()

ki18n_install(po)
install(FILES systemd/sparky-stereo-camera.service DESTINATION lib/systemd/user)
install(FILES man/sparky-stereo-camera.1 DESTINATION share/man/man1)
install(CODE "file(MAKE_DIRECTORY \"\$ENV{DESTDIR}\${CMAKE_INSTALL_PREFIX}/lib/systemd/user/default.target.wants\")
execute_process(COMMAND ln -sf ../sparky-stereo-camera.service \"\$ENV{DESTDIR}\${CMAKE_INSTALL_PREFIX}/lib/systemd/user/default.target.wants/sparky-stereo-camera.service\")")
