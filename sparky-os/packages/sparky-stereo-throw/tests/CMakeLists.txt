# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later
add_executable(castmessage-vectors castmessage-vectors.cpp)
target_link_libraries(castmessage-vectors throwcore)
add_test(NAME castmessage-against-pychromecast COMMAND python3 ${CMAKE_CURRENT_SOURCE_DIR}/castmessage-check.py $<TARGET_FILE:castmessage-vectors>)
