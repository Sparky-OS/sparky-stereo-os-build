# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
add_library(sparkystereoheadset STATIC headsetengine.cpp headsetengine.h headsetstore.cpp headsetstore.h)
set_target_properties(sparkystereoheadset PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(sparkystereoheadset PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(sparkystereoheadset PUBLIC Qt6::Core KF6::I18n KF6::ConfigCore)

add_executable(sparky-stereo-headset cli.cpp)
target_link_libraries(sparky-stereo-headset PRIVATE sparkystereoheadset KF6::Notifications)
install(TARGETS sparky-stereo-headset RUNTIME DESTINATION ${KDE_INSTALL_BINDIR})

kcmutils_add_qml_kcm(kcm_sparkystereo_headset SOURCES headsetkcm.cpp headsetkcm.h)
target_link_libraries(kcm_sparkystereo_headset PRIVATE sparkystereoheadset KF6::CoreAddons KF6::I18n KF6::KCMUtils Qt6::Quick)

ecm_add_qml_module(sparkystereoheadsetqml URI "org.sparky.stereo.headset" VERSION 1.0 GENERATE_PLUGIN_SOURCE DEPENDENCIES QtCore)
target_sources(sparkystereoheadsetqml PRIVATE headsetstatus.cpp headsetstatus.h)
target_link_libraries(sparkystereoheadsetqml PRIVATE sparkystereoheadset Qt6::Qml KF6::Notifications)
ecm_finalize_qml_module(sparkystereoheadsetqml)
