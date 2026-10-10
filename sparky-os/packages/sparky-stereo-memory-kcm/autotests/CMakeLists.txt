# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
include(ECMAddTests)

add_executable(memorykcmtest memorykcmtest.cpp ../src/memorykcm.cpp ../src/memorykcm.h)
target_include_directories(memorykcmtest PRIVATE ../src)
target_link_libraries(memorykcmtest sparkystereo_memorysettings Qt::Test KF6::AuthCore KF6::CoreAddons KF6::I18n KF6::KCMUtils KF6::KCMUtilsQuick)
add_test(NAME memorykcmtest COMMAND memorykcmtest)

add_executable(fakepolkit fakepolkit.cpp)
target_link_libraries(fakepolkit Qt::DBus)
