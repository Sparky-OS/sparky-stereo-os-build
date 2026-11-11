# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
# SPDX-License-Identifier: BSD-3-Clause
add_library(umsrenderer STATIC backend.cpp)
target_include_directories(umsrenderer PUBLIC ${CMAKE_CURRENT_SOURCE_DIR} ../src)
target_link_libraries(umsrenderer PUBLIC umsprofile Qt6::Network Qt6::Xml KF6::I18n)
add_executable(ums-renderer main.cpp window.cpp mpris.cpp)
target_link_libraries(ums-renderer PRIVATE umsrenderer Qt6::Widgets Qt6::DBus)
install(TARGETS ums-renderer DESTINATION ${KDE_INSTALL_BINDIR})
add_subdirectory(purpose)
