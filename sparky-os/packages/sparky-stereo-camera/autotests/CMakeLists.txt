add_executable(packing-list-test packing-list-test.cpp)
target_link_libraries(packing-list-test PRIVATE sparkystereocamera Qt6::Test)
add_test(NAME packing-list COMMAND packing-list-test)
