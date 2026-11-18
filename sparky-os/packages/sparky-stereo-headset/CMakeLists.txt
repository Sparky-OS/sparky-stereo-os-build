# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
cmake_minimum_required(VERSION 3.22)
project(sparky-stereo-headset VERSION 0.1.0)

set(QT_MIN_VERSION "6.8.0")
set(KF_MIN_VERSION "6.10.0")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMQmlModule)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Gui Quick Qml)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS CoreAddons Config I18n KCMUtils Notifications)
find_package(Plasma REQUIRED)

add_definitions(-DTRANSLATION_DOMAIN=\"kcm_sparkystereo_headset\")

add_subdirectory(src)
add_subdirectory(applet)

ki18n_install(po)
install(FILES data/sparkystereoheadset.notifyrc DESTINATION ${KDE_INSTALL_KNOTIFYRCDIR})
install(FILES data/sparky-stereo-headset.service DESTINATION lib/systemd/user)
install(FILES man/sparky-stereo-headset.1 DESTINATION share/man/man1)
install(CODE "file(MAKE_DIRECTORY \"\$ENV{DESTDIR}\${CMAKE_INSTALL_PREFIX}/lib/systemd/user/default.target.wants\")
execute_process(COMMAND ln -sf ../sparky-stereo-headset.service \"\$ENV{DESTDIR}\${CMAKE_INSTALL_PREFIX}/lib/systemd/user/default.target.wants/sparky-stereo-headset.service\")")
