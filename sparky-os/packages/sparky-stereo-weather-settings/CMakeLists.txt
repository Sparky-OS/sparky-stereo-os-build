# SPDX-License-Identifier: GPL-3.0-or-later
cmake_minimum_required(VERSION 3.25)
project(sparky-stereo-weather-settings LANGUAGES CXX)

find_package(ECM 6.30 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
find_package(Qt6 REQUIRED COMPONENTS Core Quick)
find_package(KF6 6.30 REQUIRED COMPONENTS Config CoreAddons I18n KCMUtils)

kcmutils_add_qml_kcm(kcm_sparkystereo_weather SOURCES weatherkcm.cpp)
target_link_libraries(kcm_sparkystereo_weather PRIVATE KF6::ConfigCore KF6::CoreAddons KF6::I18n KF6::KCMUtils)
ki18n_install(po)
