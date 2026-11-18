# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
cmake_minimum_required(VERSION 3.22)
project(sparky-pjeoffice VERSION 0.1.0)

set(QT_MIN_VERSION "6.8.0")
set(KF_MIN_VERSION "6.10.0")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMQmlModule)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Gui Widgets Network Quick)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS CoreAddons Config I18n KCMUtils Notifications StatusNotifierItem)

add_definitions(-DTRANSLATION_DOMAIN=\"sparky-pjeoffice\")

add_subdirectory(src)

ki18n_install(po)
install(FILES data/sparky-pjeoffice.notifyrc DESTINATION ${KDE_INSTALL_KNOTIFYRCDIR})
