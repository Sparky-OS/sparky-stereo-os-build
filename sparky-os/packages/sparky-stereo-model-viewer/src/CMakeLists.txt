add_executable(stereo-model-viewer main.cpp viewer.cpp f3dworker.cpp)
qt_add_resources(stereo-model-viewer "ui" PREFIX "/" FILES ui/Main.qml)
target_link_libraries(stereo-model-viewer PRIVATE Qt6::Core Qt6::Gui Qt6::Quick Qt6::QuickControls2 Qt6::Qml
    KF6::CoreAddons KF6::I18n KF6::I18nQml KF6::ConfigCore f3d::libf3d X11::X11)
install(TARGETS stereo-model-viewer ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
