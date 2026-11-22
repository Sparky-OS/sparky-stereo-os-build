cmake_minimum_required(VERSION 3.16)
project(vtk_native_colour_size C CXX)
# Debian's VTK CMake package names MPI::MPI_C in VTK::mpi's link interface, so MPI is found first.
find_package(MPI REQUIRED COMPONENTS C)
find_package(VTK REQUIRED COMPONENTS GUISupportQt RenderingOpenGL2 FiltersSources InteractionStyle)
find_package(Qt6 REQUIRED COMPONENTS Widgets OpenGL OpenGLWidgets)
add_executable(vtk-native-colour-size main.cxx)
target_link_libraries(vtk-native-colour-size PRIVATE ${VTK_LIBRARIES} Qt6::Widgets Qt6::OpenGL Qt6::OpenGLWidgets)
vtk_module_autoinit(TARGETS vtk-native-colour-size MODULES ${VTK_LIBRARIES})
