# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# a KCM's QML takes its strings from the domain named like the plugin
remove_definitions(-DTRANSLATION_DOMAIN=\"sparky-stereo-problems-plasma\")
add_definitions(-DTRANSLATION_DOMAIN=\"kcm_sparkystereo_problems\")
kcmutils_add_qml_kcm(kcm_sparkystereo_problems SOURCES problemskcm.cpp problemskcm.h)
target_link_libraries(kcm_sparkystereo_problems PRIVATE Qt6::DBus KF6::CoreAddons KF6::I18n KF6::KCMUtils PkgConfig::PROBLEMS)
# the engine's library is private (Debian Policy 10.2): found through its own folder
set_target_properties(kcm_sparkystereo_problems PROPERTIES INSTALL_RPATH "${PROBLEMS_LIBDIR}" BUILD_WITH_INSTALL_RPATH ON)
ki18n_install(po)
