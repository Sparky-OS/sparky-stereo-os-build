# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
add_executable(problemskcmtest problemskcmtest.cpp)
target_link_libraries(problemskcmtest Qt6::Test Qt6::Quick KF6::I18n KF6::CoreAddons KF6::KCMUtilsQuick PkgConfig::PROBLEMS)
target_compile_definitions(problemskcmtest PRIVATE KCM_PLUGIN="$<TARGET_FILE:kcm_sparkystereo_problems>")
add_dependencies(problemskcmtest kcm_sparkystereo_problems)
add_test(NAME problemskcmtest COMMAND problemskcmtest)
