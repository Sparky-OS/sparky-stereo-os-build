# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
cmake_minimum_required(VERSION 3.25)
project(live-caption-proof LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
find_package(Captiond REQUIRED COMPONENTS Testing)
add_executable(stand-in stand-in.cpp)
target_link_libraries(stand-in PRIVATE Captiond::Client Captiond::Testing)
add_executable(capture-nodes capture-nodes.cpp)
target_link_libraries(capture-nodes PRIVATE Captiond::Client Captiond::Testing)
