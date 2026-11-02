# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
cmake_minimum_required(VERSION 3.22)
project(sparky-stereo-problems-plasma VERSION 0.1.0)

set(QT_MIN_VERSION "6.8.0")
set(KF_MIN_VERSION "6.10.0")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Gui)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS I18n Notifications)
find_package(PkgConfig REQUIRED)
pkg_check_modules(PROBLEMS REQUIRED IMPORTED_TARGET sparky-stereo-problems)

add_definitions(-DTRANSLATION_DOMAIN=\"sparky-stereo-problems-plasma\")

add_executable(sparky-stereo-problems-notifier src/main.cpp src/notifier.cpp src/notifier.h)
target_link_libraries(sparky-stereo-problems-notifier Qt6::Core Qt6::Gui KF6::I18n KF6::Notifications PkgConfig::PROBLEMS)
# the engine's library is private (Debian Policy 10.2): found through its own folder
set_target_properties(sparky-stereo-problems-notifier PROPERTIES INSTALL_RPATH "${PROBLEMS_LIBDIR}" BUILD_WITH_INSTALL_RPATH ON)
install(TARGETS sparky-stereo-problems-notifier DESTINATION ${KDE_INSTALL_BINDIR})
install(FILES sparky-stereo-problems.notifyrc DESTINATION ${KDE_INSTALL_KNOTIFYRCDIR})
install(FILES systemd/user/sparky-stereo-problems-notifier.service systemd/user/sparky-stereo-problems-notifier.path
        DESTINATION ${KDE_INSTALL_SYSTEMDUSERUNITDIR})

ki18n_install(po)
