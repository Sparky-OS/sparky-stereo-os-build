# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
add_library(sparkystereo_graphics STATIC
    gpuinventory.cpp gpuinventory.h
    graphicssettings.cpp graphicssettings.h
    machinerecord.cpp machinerecord.h
    appentries.cpp appentries.h
    resolver.cpp resolver.h
    powerprofiles.cpp powerprofiles.h
)
set_target_properties(sparkystereo_graphics PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(sparkystereo_graphics PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(sparkystereo_graphics PUBLIC Qt::Core Qt::DBus KF6::ConfigCore)

kcmutils_add_qml_kcm(kcm_sparkystereo_graphics SOURCES graphicskcm.cpp graphicskcm.h)
target_link_libraries(kcm_sparkystereo_graphics PRIVATE sparkystereo_graphics KF6::CoreAddons KF6::I18n KF6::KCMUtils)

add_executable(sparky-stereo-gpu-env cli/gpuenv.cpp)
target_link_libraries(sparky-stereo-gpu-env PRIVATE sparkystereo_graphics)
install(TARGETS sparky-stereo-gpu-env DESTINATION ${KDE_INSTALL_BINDIR})

add_executable(sparky-stereo-gpu-record cli/gpurecord.cpp)
target_compile_definitions(sparky-stereo-gpu-record PRIVATE SPARKY_MACHINES_DIR="${KDE_INSTALL_FULL_DATADIR}/sparky-stereo-graphics/machines")
target_link_libraries(sparky-stereo-gpu-record PRIVATE sparkystereo_graphics)
install(TARGETS sparky-stereo-gpu-record DESTINATION ${KDE_INSTALL_BINDIR})
