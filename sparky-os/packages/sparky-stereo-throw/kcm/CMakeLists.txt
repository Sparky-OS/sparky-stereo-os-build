# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later
kcmutils_add_qml_kcm(kcm_sparkystereo_throw SOURCES throwkcm.cpp throwkcm.h)
target_link_libraries(kcm_sparkystereo_throw PRIVATE Qt6::DBus Qt6::Quick KF6::CoreAddons KF6::I18n KF6::KCMUtils)
