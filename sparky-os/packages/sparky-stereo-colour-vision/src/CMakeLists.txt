# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
kcmutils_add_qml_kcm(kcm_sparkystereo_colourvision SOURCES colourvisionkcm.cpp colourvisionkcm.h)
target_link_libraries(kcm_sparkystereo_colourvision PRIVATE KF6::CoreAddons KF6::I18n KF6::KCMUtils Qt6::Quick)
