add_executable(packing-list-test packing-list-test.cpp)
target_link_libraries(packing-list-test PRIVATE sparkystereocamera Qt6::Test)
add_test(NAME packing-list COMMAND packing-list-test)

add_executable(preview-refusal-test preview-refusal-test.cpp ../src/camerakcm.cpp ../src/previewsource.cpp)
target_link_libraries(preview-refusal-test PRIVATE sparkystereocamera Qt6::Test Qt6::Quick Qt6::Multimedia KF6::CoreAddons KF6::I18n KF6::KCMUtils PkgConfig::PIPEWIRE)
target_compile_definitions(preview-refusal-test PRIVATE CAMERA_QML_PATH="${CMAKE_CURRENT_SOURCE_DIR}/../src/ui/main.qml")
# This executable needs the isolated PipeWire camera fixture; the ordinary
# build's ctest never opens a camera on the build host.
