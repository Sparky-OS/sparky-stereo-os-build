# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
# SPDX-License-Identifier: BSD-3-Clause
foreach(kind tv headset)
    kcoreaddons_add_plugin(ums_${kind} SOURCES plugin.cpp INSTALL_NAMESPACE "kf6/purpose")
    target_compile_definitions(ums_${kind} PRIVATE UMS_TARGET="${kind}")
    if(kind STREQUAL "headset")
        target_compile_definitions(ums_${kind} PRIVATE UMS_HEADSET=1)
    endif()
    target_link_libraries(ums_${kind} PRIVATE KF6::Purpose KF6::CoreAddons KF6::I18n)
endforeach()
