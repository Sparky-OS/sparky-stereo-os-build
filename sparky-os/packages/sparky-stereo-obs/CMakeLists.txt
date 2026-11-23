# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/20
# Copyright 2026 under the GNU GPL3 License
# The edition's stereo module for OBS Studio: built against the libobs and obs-frontend-api of the OBS the edition
# installs (deb-multimedia's obs-studio, libobs-dev), the shared stereo policy (libstereo-policy) and Qt 6 Widgets.
cmake_minimum_required(VERSION 3.25)
project(sparky-stereo-obs VERSION 0.3.0 LANGUAGES C CXX)

include(GNUInstallDirs)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(libobs 33 REQUIRED)
find_package(obs-frontend-api REQUIRED)
find_package(Qt6 REQUIRED COMPONENTS Core Widgets)
find_package(PkgConfig REQUIRED)
pkg_check_modules(STEREO_POLICY REQUIRED IMPORTED_TARGET stereo-policy>=1.23.0)
# Stereo::ScreenMode: whether a screen shows 3D, the one signal the edition's capture programs read (Spectacle's
# ImagePlatformKWin::updateStereoOutputs())
find_package(StereoLayer 1.23 REQUIRED)
# The previews as 3D areas: their Wayland surfaces declared full side by side
pkg_check_modules(STEREO_DECLARE REQUIRED IMPORTED_TARGET stereo-declare>=1.4)
find_package(Qt6 REQUIRED COMPONENTS Gui)
# The Stereo input filter: a picture with its depth map drawn by the stereo layer's depth library on the GPU, in OBS's
# own OpenGL context, whose functions EGL finds; FFmpeg's AVStereo3D values read from a media source, from its header
# only (nothing of libavutil is called)
pkg_check_modules(STEREO_DIBR REQUIRED IMPORTED_TARGET stereo-dibr>=1.23.0)
pkg_check_modules(EGL REQUIRED IMPORTED_TARGET egl)
pkg_check_modules(AVUTIL REQUIRED libavutil)

add_library(sparky-stereo-obs MODULE
	src/plugin.cpp
	src/marks.cpp
	src/sei.c
	src/stereo-input.cpp
	src/preview.cpp
	src/layer-words.cpp)
set_target_properties(sparky-stereo-obs PROPERTIES PREFIX "")
target_link_libraries(sparky-stereo-obs PRIVATE OBS::libobs OBS::obs-frontend-api Qt6::Core Qt6::Widgets
	PkgConfig::STEREO_POLICY PkgConfig::STEREO_DECLARE Stereo::Layer Qt6::Gui PkgConfig::STEREO_DIBR PkgConfig::EGL)
target_include_directories(sparky-stereo-obs PRIVATE ${AVUTIL_INCLUDE_DIRS})
target_compile_options(sparky-stereo-obs PRIVATE -Wall -Wextra)
target_compile_definitions(sparky-stereo-obs PRIVATE PROJECT_VERSION="${PROJECT_VERSION}")

# OBS 33 loads a system plugin from <libdir>/obs-modules/plugins/<name>.so and its data from
# <datadir>/obs/obs-modules/plugins/<name> (frontend/plugin-manager/PluginModuleLoader_Linux.cpp).
install(TARGETS sparky-stereo-obs LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}/obs-modules/plugins)
install(DIRECTORY data/ DESTINATION ${CMAKE_INSTALL_DATADIR}/obs/obs-modules/plugins/sparky-stereo-obs)

include(CTest)
if(BUILD_TESTING)
	add_executable(test-sei tests/test-sei.c src/sei.c)
	add_test(NAME sei COMMAND test-sei)
endif()
