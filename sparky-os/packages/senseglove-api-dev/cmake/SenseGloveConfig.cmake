# CMake package for the SenseGlove C++ API: the headers come from the senseglove-api-dev package, the two
# libraries (SGCore, SGConnect) from SenseGlove, fetched by the Stereo APTus entry "SenseGlove API libraries (C++)".
#
#   find_package(SenseGlove REQUIRED)
#   target_link_libraries(myprogram PRIVATE SenseGlove::SGCore SenseGlove::SGConnect)
#
# SenseGlove built v20 to v22 with libstdc++'s old std::string ABI (no [abi:cxx11] in their exported names, measured with nm -D),
# so the targets compile a program with _GLIBCXX_USE_CXX11_ABI=0; without it the link fails with undefined references.
#
# SENSEGLOVE_LIBRARY_DIR (cache or environment) names another folder that holds libsgcore.so and libsgconnect.so.
if(TARGET SenseGlove::SGCore)
  return()
endif()
if(NOT DEFINED SENSEGLOVE_LIBRARY_DIR AND DEFINED ENV{SENSEGLOVE_LIBRARY_DIR})
  set(SENSEGLOVE_LIBRARY_DIR "$ENV{SENSEGLOVE_LIBRARY_DIR}")
endif()
if(NOT DEFINED SENSEGLOVE_LIBRARY_DIR)
  set(SENSEGLOVE_LIBRARY_DIR "/opt/senseglove-api/lib")
endif()
get_filename_component(_senseglove_prefix "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
set(SenseGlove_INCLUDE_DIR "${_senseglove_prefix}/include")
set(_senseglove_missing "")
if(NOT EXISTS "${SenseGlove_INCLUDE_DIR}/SenseGlove/Core/HandLayer.hpp")
  string(APPEND _senseglove_missing "The headers are missing from ${SenseGlove_INCLUDE_DIR}/SenseGlove (package senseglove-api-dev). ")
endif()
foreach(_name sgcore sgconnect)
  if(NOT EXISTS "${SENSEGLOVE_LIBRARY_DIR}/lib${_name}.so")
    string(APPEND _senseglove_missing
      "lib${_name}.so is not in ${SENSEGLOVE_LIBRARY_DIR}. ")
  endif()
endforeach()
if(NOT CMAKE_SYSTEM_PROCESSOR STREQUAL "x86_64")
  string(APPEND _senseglove_missing "SenseGlove publishes these libraries for x86-64 and aarch64; the entry installs the x86-64 ones. ")
endif()
if(_senseglove_missing)
  set(SenseGlove_FOUND FALSE)
  set(SenseGlove_NOT_FOUND_MESSAGE
    "${_senseglove_missing}The libraries are SenseGlove's own binaries and are fetched from SenseGlove when you install the entry \"SenseGlove API libraries (C++)\" in Stereo APTus (VR and SteamVR), or name your own folder with -DSENSEGLOVE_LIBRARY_DIR=DIR. See /usr/share/doc/senseglove-api-dev/README.Debian.")
  return()
endif()
foreach(_name sgcore sgconnect)
  string(TOUPPER "${_name}" _upper)
  if(_name STREQUAL "sgcore")
    set(_target SGCore)
  else()
    set(_target SGConnect)
  endif()
  add_library(SenseGlove::${_target} SHARED IMPORTED)
  set_target_properties(SenseGlove::${_target} PROPERTIES
    IMPORTED_LOCATION "${SENSEGLOVE_LIBRARY_DIR}/lib${_name}.so"
    IMPORTED_SONAME "lib${_name}.so"
    INTERFACE_INCLUDE_DIRECTORIES "${SenseGlove_INCLUDE_DIR}"
    INTERFACE_COMPILE_DEFINITIONS "_GLIBCXX_USE_CXX11_ABI=0")
endforeach()
set(SenseGlove_FOUND TRUE)
