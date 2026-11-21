cmake_minimum_required(VERSION 3.16)
project(vtk_quad_buffer_blit C CXX)
# Debian's VTK CMake package names MPI::MPI_C in VTK::mpi's link interface, so MPI is found first.
find_package(MPI REQUIRED COMPONENTS C)
find_package(VTK REQUIRED COMPONENTS GUISupportQt RenderingOpenGL2 FiltersSources InteractionStyle)
find_package(Qt6 REQUIRED COMPONENTS Widgets OpenGL)
add_executable(vtk-quad-buffer-blit main.cxx)
target_link_libraries(vtk-quad-buffer-blit PRIVATE ${VTK_LIBRARIES} Qt6::Widgets Qt6::OpenGL)
vtk_module_autoinit(TARGETS vtk-quad-buffer-blit MODULES ${VTK_LIBRARIES})
