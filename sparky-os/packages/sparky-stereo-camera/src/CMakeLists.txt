# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
add_library(sparkystereocamera STATIC
    v4l2camera.cpp v4l2camera.h
    pipewirecameras.cpp pipewirecameras.h
    camerastore.cpp camerastore.h
    packings.cpp packings.h
    standardnames.cpp standardnames.h
    cameraservice.cpp cameraservice.h)
set_target_properties(sparkystereocamera PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(sparkystereocamera PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(sparkystereocamera PUBLIC Qt6::Core KF6::I18n PkgConfig::STEREOPOLICY)

add_executable(sparky-stereo-camera cli.cpp)
target_link_libraries(sparky-stereo-camera PRIVATE sparkystereocamera)
install(TARGETS sparky-stereo-camera RUNTIME DESTINATION ${KDE_INSTALL_BINDIR})

kcmutils_add_qml_kcm(kcm_sparkystereo_camera SOURCES camerakcm.cpp camerakcm.h previewsource.cpp previewsource.h)
target_link_libraries(kcm_sparkystereo_camera PRIVATE sparkystereocamera KF6::CoreAddons KF6::I18n KF6::KCMUtils Qt6::Quick Qt6::Multimedia PkgConfig::PIPEWIRE)
