# The headers follow the SenseGlove-API repository at the commit named in /usr/share/doc/senseglove-api-dev/SOURCE; the
# libraries are v22. No version check beyond "exists": SenseGlove publishes no version number for the headers.
set(PACKAGE_VERSION "22")
set(PACKAGE_VERSION_COMPATIBLE TRUE)
if(PACKAGE_FIND_VERSION VERSION_GREATER PACKAGE_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE FALSE)
endif()
if(PACKAGE_FIND_VERSION STREQUAL PACKAGE_VERSION)
  set(PACKAGE_VERSION_EXACT TRUE)
endif()
