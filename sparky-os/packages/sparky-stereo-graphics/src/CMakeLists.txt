# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
add_library(sparkystereo_graphics STATIC
    gpuinventory.cpp gpuinventory.h
    graphicssettings.cpp graphicssettings.h
    machinerecord.cpp machinerecord.h
    appentries.cpp appentries.h
    resolver.cpp resolver.h
    powerprofiles.cpp powerprofiles.h
    problems.cpp problems.h
)
set_target_properties(sparkystereo_graphics PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(sparkystereo_graphics PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
# the edition's one engine keeps the problems (ORDER 350); its library is private to it (Debian Policy 8: not covered),
# found through its own folder
target_link_libraries(sparkystereo_graphics PUBLIC Qt::Core Qt::DBus KF6::ConfigCore KF6::I18n PkgConfig::PROBLEMS)

kcmutils_add_qml_kcm(kcm_sparkystereo_graphics SOURCES graphicskcm.cpp graphicskcm.h)
target_link_libraries(kcm_sparkystereo_graphics PRIVATE sparkystereo_graphics KF6::CoreAddons KF6::I18n KF6::KCMUtils)

add_executable(sparky-stereo-gpu-env cli/gpuenv.cpp)
target_include_directories(sparky-stereo-gpu-env PRIVATE cli)
target_link_libraries(sparky-stereo-gpu-env PRIVATE sparkystereo_graphics)
install(TARGETS sparky-stereo-gpu-env DESTINATION ${KDE_INSTALL_BINDIR})

add_executable(sparky-stereo-gpu-record cli/gpurecord.cpp)
target_compile_definitions(sparky-stereo-gpu-record PRIVATE SPARKY_MACHINES_DIR="${KDE_INSTALL_FULL_DATADIR}/sparky-stereo-graphics/machines")
target_link_libraries(sparky-stereo-gpu-record PRIVATE sparkystereo_graphics)
install(TARGETS sparky-stereo-gpu-record DESTINATION ${KDE_INSTALL_BINDIR})

foreach(target kcm_sparkystereo_graphics sparky-stereo-gpu-env sparky-stereo-gpu-record)
    set_target_properties(${target} PROPERTIES INSTALL_RPATH "${PROBLEMS_LIBDIR}" BUILD_WITH_INSTALL_RPATH ON)
endforeach()
