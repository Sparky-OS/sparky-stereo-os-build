# SPDX-License-Identifier: GPL-3.0-or-later
cmake_minimum_required(VERSION 3.22)
project(sparky-storage-cleanup)
find_package(ECM 6.10 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)
include(KDECMakeSettings)
find_package(Qt6 6.8 REQUIRED COMPONENTS Core Widgets Quick)
find_package(KF6 6.10 REQUIRED COMPONENTS CoreAddons I18n KCMUtils KIO)
set(CMAKE_CXX_STANDARD 20)
add_definitions(-DTRANSLATION_DOMAIN="kcm_sparkystereo_storage_cleanup")
kcmutils_add_qml_kcm(kcm_sparkystereo_storage_cleanup SOURCES storagekcm.cpp storagekcm.h)
target_link_libraries(kcm_sparkystereo_storage_cleanup PRIVATE Qt6::Core KF6::CoreAddons KF6::I18n KF6::KCMUtilsQuick)
kcoreaddons_add_plugin(storagecleanupproperties SOURCES driveproperties.cpp INSTALL_NAMESPACE "kf6/propertiesdialog")
target_link_libraries(storagecleanupproperties PRIVATE Qt6::Widgets KF6::CoreAddons KF6::I18n KF6::KIOWidgets)
ki18n_install(po)
install(PROGRAMS sparky-open-storage-cleanup DESTINATION "${KDE_INSTALL_BINDIR}")
install(PROGRAMS sparky-storage-cleanup-admin DESTINATION libexec)
install(FILES org.sparkylinux.storage-cleanup.policy DESTINATION "${KDE_INSTALL_DATADIR}/polkit-1/actions")
install(PROGRAMS sparky-storage-cleanup-space sparky-storage-cleanup-weekly DESTINATION libexec)
install(FILES systemd/sparky-storage-cleanup.timer systemd/sparky-storage-cleanup.service DESTINATION lib/systemd/user)

find_program(SPARKY_PROBLEMS sparky-stereo-problems REQUIRED)
add_custom_target(problem_catalogs ALL
    COMMAND ${SPARKY_PROBLEMS} catalog sparky-stereo-storage-kcm
        "${CMAKE_CURRENT_SOURCE_DIR}/lang" "${CMAKE_CURRENT_BINARY_DIR}/catalogs"
    VERBATIM)
install(DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/catalogs/" DESTINATION lib/systemd/catalog)
