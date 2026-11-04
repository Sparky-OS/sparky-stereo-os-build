# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
add_executable(sparkystereo_graphics_helper graphicshelper.cpp graphicshelper.h)
target_link_libraries(sparkystereo_graphics_helper sparkystereo_graphics KF6::AuthCore)
install(TARGETS sparkystereo_graphics_helper DESTINATION ${KAUTH_HELPER_INSTALL_DIR})
kauth_install_helper_files(sparkystereo_graphics_helper org.sparkylinux.sparkystereo.graphics root)
kauth_install_actions(org.sparkylinux.sparkystereo.graphics org.sparkylinux.sparkystereo.graphics.actions)
