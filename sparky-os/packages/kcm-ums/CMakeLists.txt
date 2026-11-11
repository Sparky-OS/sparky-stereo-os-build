# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
# SPDX-License-Identifier: BSD-3-Clause

cmake_minimum_required(VERSION 3.20)
project(kcm-ums VERSION 0.2.0)

set(QT_MIN_VERSION 6.8.0)
set(KF_MIN_VERSION 6.10.0)

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
kde_enable_exceptions()
include(ECMQmlModule)
include(FeatureSummary)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Gui Qml Quick Test Widgets Network DBus Xml)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS CoreAddons I18n KCMUtils Purpose)

add_definitions(-DTRANSLATION_DOMAIN="kcm_ums")

ki18n_install(po)

add_subdirectory(src)
add_subdirectory(controller)
if(BUILD_TESTING)
    add_subdirectory(autotests)
endif()

feature_summary(WHAT ALL INCLUDE_QUIET_PACKAGES FATAL_ON_MISSING_REQUIRED_PACKAGES)
