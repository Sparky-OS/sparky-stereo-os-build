# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
# SPDX-License-Identifier: BSD-3-Clause

add_library(umsprofile STATIC umsprofile.cpp umsservice.cpp)
target_link_libraries(umsprofile PUBLIC Qt6::Core)
set_target_properties(umsprofile PROPERTIES POSITION_INDEPENDENT_CODE ON)

kcmutils_add_qml_kcm(kcm_ums SOURCES kcm_ums.cpp kcm_ums.h)
target_link_libraries(kcm_ums PRIVATE umsprofile Qt6::Quick KF6::CoreAddons KF6::I18n KF6::KCMUtilsCore KF6::KCMUtils)
