# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
add_executable(sparkystereo_memory_helper memoryhelper.cpp memoryhelper.h)
target_link_libraries(sparkystereo_memory_helper sparkystereo_memorysettings KF6::AuthCore)
install(TARGETS sparkystereo_memory_helper DESTINATION ${KAUTH_HELPER_INSTALL_DIR})
kauth_install_helper_files(sparkystereo_memory_helper org.sparkylinux.sparkystereo.memory root)
kauth_install_actions(org.sparkylinux.sparkystereo.memory org.sparkylinux.sparkystereo.memory.actions)
