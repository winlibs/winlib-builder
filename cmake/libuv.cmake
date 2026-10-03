# Keep the established PHP DLL/import-library names and distinguish the static
# archive. Defer until libuv has created its targets, without modifying its source.
function(configure_winlibs_libuv)
  set_target_properties(uv PROPERTIES OUTPUT_NAME libuv)
  set_target_properties(uv_a PROPERTIES
    OUTPUT_NAME libuv_a
    PREFIX ""
    COMPILE_PDB_NAME libuv_a
    COMPILE_PDB_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
endfunction()

cmake_language(DEFER CALL configure_winlibs_libuv)
