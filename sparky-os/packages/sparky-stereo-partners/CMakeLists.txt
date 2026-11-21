# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
cmake_minimum_required(VERSION 3.22)
project(sparky-stereo-partners VERSION 0.1.0)

set(QT_MIN_VERSION "6.8.0")
set(KF_MIN_VERSION "6.10.0")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Quick)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS CoreAddons I18n KCMUtils)

add_definitions(-DTRANSLATION_DOMAIN=\"kcm_sparkystereo_partners\")

add_subdirectory(src)

ki18n_install(po)
install(PROGRAMS bin/sparky-stereo-partners DESTINATION ${KDE_INSTALL_BINDIR})
install(PROGRAMS bin/install-engine DESTINATION libexec/sparky-stereo-partners)
install(FILES share/sparky-stereo-partnersrc DESTINATION /etc/xdg)
# a category of its own at the top of System Settings (systemsettings 6.7: SettingsBase reads every categories/*.desktop)
install(FILES share/settings-partners.desktop DESTINATION ${KDE_INSTALL_DATADIR}/systemsettings/categories)
install(FILES polkit/org.sparkylinux.sparkystereo.partners.policy DESTINATION ${KDE_INSTALL_DATADIR}/polkit-1/actions)
