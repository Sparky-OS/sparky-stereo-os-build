# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
include(ECMAddTests)

add_executable(memorykcmtest memorykcmtest.cpp ../src/cushionstatus.cpp ../src/memorykcm.cpp ../src/memorykcm.h)
target_include_directories(memorykcmtest PRIVATE ../src)
target_link_libraries(memorykcmtest sparkystereo_memorysettings Qt::Test KF6::AuthCore KF6::CoreAddons KF6::I18n KF6::KCMUtils KF6::KCMUtilsQuick)
add_test(NAME memorykcmtest COMMAND memorykcmtest)

add_executable(fakepolkit fakepolkit.cpp)
target_link_libraries(fakepolkit Qt::DBus)

add_executable(cushionstatustest cushionstatustest.cpp ../src/cushionstatus.cpp ../src/memorykcm.cpp ../src/memorykcm.h)
target_include_directories(cushionstatustest PRIVATE ../src)
target_link_libraries(cushionstatustest sparkystereo_memorysettings Qt::Test KF6::AuthCore KF6::CoreAddons KF6::I18n KF6::KCMUtils KF6::KCMUtilsQuick)
add_test(NAME cushionstatustest COMMAND cushionstatustest)

add_executable(memorypagetest memorypagetest.cpp)
target_link_libraries(memorypagetest Qt::Test Qt::Quick KF6::I18n KF6::CoreAddons KF6::KCMUtilsQuick)
target_compile_definitions(memorypagetest PRIVATE KCM_PLUGIN="$<TARGET_FILE:kcm_sparkystereo_memory>")
add_dependencies(memorypagetest kcm_sparkystereo_memory)
add_test(NAME memorypagetest COMMAND memorypagetest)
