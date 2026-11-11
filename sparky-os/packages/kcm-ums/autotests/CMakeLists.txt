# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
# SPDX-License-Identifier: BSD-3-Clause

include(ECMAddTests)

ecm_add_test(umsprofiletest.cpp ../src/umsprofile.cpp ../src/umsservice.cpp
    TEST_NAME umsprofiletest
    LINK_LIBRARIES Qt6::Test Qt6::Core)

add_executable(kcmumstest kcmumstest.cpp)
add_dependencies(kcmumstest kcm_ums)
target_compile_definitions(kcmumstest PRIVATE KCM_PLUGIN_PATH="$<TARGET_FILE:kcm_ums>")
target_link_libraries(kcmumstest Qt6::Test Qt6::Gui KF6::KCMUtils KF6::KCMUtilsCore KF6::CoreAddons)
add_test(NAME kcmumstest COMMAND kcmumstest)
set_tests_properties(kcmumstest PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

add_executable(umsprofile-write umsprofile-write.cpp ../src/umsprofile.cpp)
target_link_libraries(umsprofile-write Qt6::Core)
