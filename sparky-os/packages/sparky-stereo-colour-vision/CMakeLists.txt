# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
cmake_minimum_required(VERSION 3.22)
project(sparky-stereo-colour-vision VERSION 0.1.0)

set(QT_MIN_VERSION "6.8.0")
set(KF_MIN_VERSION "6.10.0")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Gui Quick)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS CoreAddons I18n KCMUtils)

add_definitions(-DTRANSLATION_DOMAIN=\"kcm_sparkystereo_colourvision\")

add_subdirectory(src)

ki18n_install(po)
install(PROGRAMS helper/sparky-stereo-colour-vision DESTINATION ${KDE_INSTALL_BINDIR})
install(FILES profile.d/sparky-stereo-colour-vision.sh DESTINATION ${KDE_INSTALL_SYSCONFDIR}/profile.d)
install(FILES systemd/sparky-stereo-colour-vision.path systemd/sparky-stereo-colour-vision.service DESTINATION lib/systemd/user)
install(FILES data/maps.json data/limits.json data/nanorc data/console-protan.palette data/console-deutan.palette data/console-tritan.palette
              data/console-mono.palette
        DESTINATION ${KDE_INSTALL_DATADIR}/sparky-stereo/colour-vision)
install(FILES data/BreezeColourVisionProtan.colorscheme data/BreezeColourVisionDeutan.colorscheme
              data/BreezeColourVisionTritan.colorscheme data/BreezeColourVisionMono.colorscheme
        DESTINATION ${KDE_INSTALL_DATADIR}/konsole)
file(GLOB SHIPPED_SCHEMES ${CMAKE_CURRENT_SOURCE_DIR}/data/color-schemes/*.colors)
install(FILES ${SHIPPED_SCHEMES} DESTINATION ${KDE_INSTALL_DATADIR}/color-schemes)
install(CODE "foreach(unit sparky-stereo-colour-vision.path:default.target sparky-stereo-colour-vision.service:plasma-workspace.target)
  string(REPLACE \":\" \";\" pair \"\${unit}\")
  list(GET pair 0 name)
  list(GET pair 1 target)
  file(MAKE_DIRECTORY \"\$ENV{DESTDIR}\${CMAKE_INSTALL_PREFIX}/lib/systemd/user/\${target}.wants\")
  execute_process(COMMAND ln -sf ../\${name} \"\$ENV{DESTDIR}\${CMAKE_INSTALL_PREFIX}/lib/systemd/user/\${target}.wants/\${name}\")
endforeach()")
