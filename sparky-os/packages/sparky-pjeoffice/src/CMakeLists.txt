# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
add_library(sparkypjeofficestate STATIC signerstate.cpp signerstate.h)
set_target_properties(sparkypjeofficestate PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(sparkypjeofficestate PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(sparkypjeofficestate PUBLIC Qt6::Core Qt6::Network)

add_executable(sparky-pjeoffice-tray tray.cpp)
target_link_libraries(sparky-pjeoffice-tray PRIVATE sparkypjeofficestate Qt6::Widgets KF6::ConfigCore KF6::I18n KF6::Notifications KF6::StatusNotifierItem)
install(TARGETS sparky-pjeoffice-tray RUNTIME DESTINATION ${KDE_INSTALL_BINDIR})

kcmutils_add_qml_kcm(kcm_sparkystereo_pjeoffice SOURCES pjeofficekcm.cpp pjeofficekcm.h)
target_link_libraries(kcm_sparkystereo_pjeoffice PRIVATE sparkypjeofficestate KF6::CoreAddons KF6::ConfigCore KF6::I18n KF6::KCMUtils Qt6::Quick)
