cmake_minimum_required(VERSION 3.22)
project(DecoderDefault LANGUAGES CXX)
set(CMAKE_AUTOMOC ON)
find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml)
find_package(KF6Config REQUIRED)
add_executable(config-proof main.cpp)
target_include_directories(config-proof PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
target_link_libraries(config-proof PRIVATE Qt6::Core Qt6::Gui Qt6::Qml KF6::ConfigCore KF6::ConfigGui)
set(KCFG_INPUT /w/sources/kdenlive/src/kdenlivesettings.kcfg CACHE FILEPATH "Settings under test")
kconfig_target_kcfg_file(config-proof FILE ${KCFG_INPUT}
    CLASS_NAME KdenliveSettings MUTATORS SINGLETON GENERATE_PROPERTIES GENERATE_MOC
    QML_REGISTRATION DEFAULT_VALUE_GETTERS)
