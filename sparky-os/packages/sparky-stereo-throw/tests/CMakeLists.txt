# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later
add_executable(castmessage-vectors castmessage-vectors.cpp)
target_link_libraries(castmessage-vectors throwcore)
add_test(NAME castmessage-against-pychromecast COMMAND python3 ${CMAKE_CURRENT_SOURCE_DIR}/castmessage-check.py $<TARGET_FILE:castmessage-vectors>)
add_executable(codecplan codecplan.cpp)
target_link_libraries(codecplan throwcore)
add_test(NAME codec-plan-against-the-table COMMAND codecplan ${CMAKE_SOURCE_DIR}/data/devices.json)
set_tests_properties(codec-plan-against-the-table PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
