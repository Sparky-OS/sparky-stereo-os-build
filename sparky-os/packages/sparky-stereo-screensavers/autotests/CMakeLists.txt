# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later
add_executable(savermodeltest savermodeltest.cpp)
target_link_libraries(savermodeltest PRIVATE sparkystereosavers Qt6::Test)
add_test(NAME savermodeltest COMMAND savermodeltest)
# a proof tool for the rig: what the page lists and reads on an installed system (not installed, not a test by itself)
add_executable(saverstate saverstate.cpp)
target_link_libraries(saverstate PRIVATE sparkystereosavers)
