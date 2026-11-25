# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later
set(VIEWPORTER_XML ${WAYLAND_PROTOCOLS_DIR}/stable/viewporter/viewporter.xml)
add_custom_command(OUTPUT viewporter-client-protocol.h COMMAND ${WAYLAND_SCANNER} client-header ${VIEWPORTER_XML} viewporter-client-protocol.h DEPENDS ${VIEWPORTER_XML})
add_custom_command(OUTPUT viewporter-protocol.c COMMAND ${WAYLAND_SCANNER} private-code ${VIEWPORTER_XML} viewporter-protocol.c DEPENDS ${VIEWPORTER_XML})

add_library(sparkystereosavers STATIC
    savermodel.cpp savermodel.h
    showstore.cpp showstore.h
    saverrunner.cpp saverrunner.h
    pairsurface.cpp pairsurface.h
    saverpreview.cpp saverpreview.h
    ${CMAKE_CURRENT_BINARY_DIR}/viewporter-protocol.c ${CMAKE_CURRENT_BINARY_DIR}/viewporter-client-protocol.h)
set_target_properties(sparkystereosavers PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(sparkystereosavers PUBLIC ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR})
target_link_libraries(sparkystereosavers PUBLIC Qt6::Core Qt6::Gui Qt6::Quick KF6::I18n KF6::ConfigCore PRIVATE Qt6::GuiPrivate PkgConfig::STEREODECLARE PkgConfig::WAYLAND)

kcmutils_add_qml_kcm(kcm_sparkystereo_screensavers SOURCES saverskcm.cpp saverskcm.h)
target_link_libraries(kcm_sparkystereo_screensavers PRIVATE sparkystereosavers KF6::ConfigCore KF6::CoreAddons KF6::I18n KF6::KCMUtils Qt6::Quick)
