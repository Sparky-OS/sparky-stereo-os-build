# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
add_library(sparkystereo_memorysettings STATIC memorysettings.cpp memorysettings.h)
set_target_properties(sparkystereo_memorysettings PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(sparkystereo_memorysettings PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(sparkystereo_memorysettings PUBLIC Qt::Core)

kcmutils_add_qml_kcm(kcm_sparkystereo_memory SOURCES memorykcm.cpp memorykcm.h)
target_link_libraries(kcm_sparkystereo_memory PRIVATE sparkystereo_memorysettings KF6::AuthCore KF6::CoreAddons KF6::I18n KF6::KCMUtils)
