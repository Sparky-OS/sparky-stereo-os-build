# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
cmake_minimum_required(VERSION 3.22)
project(sparky-stereo-model-viewer VERSION 0.1.0)

set(QT_MIN_VERSION "6.8.0")
set(KF_MIN_VERSION "6.10.0")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMQmlModule)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Gui Widgets Quick QuickControls2 Qml)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS CoreAddons I18n Config)
find_package(f3d REQUIRED COMPONENTS library)
find_package(X11 REQUIRED)

add_definitions(-DTRANSLATION_DOMAIN=\"stereo-model-viewer\")

add_subdirectory(src)

ki18n_install(po)
install(FILES data/org.sparkystereo.ModelViewer.desktop DESTINATION ${KDE_INSTALL_APPDIR})
install(FILES data/org.sparkystereo.ModelViewer.metainfo.xml DESTINATION ${KDE_INSTALL_METAINFODIR})
install(FILES man/stereo-model-viewer.1 DESTINATION share/man/man1)
