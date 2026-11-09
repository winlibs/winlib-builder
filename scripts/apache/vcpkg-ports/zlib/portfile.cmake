# Based on microsoft/vcpkg 07f4812200df3d3c931c0c8a6081d3b21fe2bf9f ports/zlib.
# Use zlib 1.4 with its upstream MSVC library names.
# When this port is updated, the minizip port should be updated at the same time
vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO winlibs/zlib
    REF cf7eb981cf4fce56a88608c68fd3f255a2c452c9
    SHA512 7d44dcae97cbc5581b021346837aa58cef57902ea2382cb2289d187afa2402be6a09c8775de422c2262216d15164dc3c1e3a1e462da68700ce722ec7882181da
    HEAD_REF master
    PATCHES
        0001-no-version-script-on-ohos.patch
        0002-honor-selected-library-components.patch
)

string(COMPARE EQUAL "${VCPKG_LIBRARY_LINKAGE}" "dynamic" ZLIB_BUILD_SHARED)
string(COMPARE EQUAL "${VCPKG_LIBRARY_LINKAGE}" "static" ZLIB_BUILD_STATIC)

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DZLIB_BUILD_TESTING=OFF
        -DZLIB_BUILD_SHARED=${ZLIB_BUILD_SHARED}
        -DZLIB_BUILD_STATIC=${ZLIB_BUILD_STATIC}
)

vcpkg_cmake_install()
vcpkg_copy_pdbs()
vcpkg_cmake_config_fixup(CONFIG_PATH "lib/cmake/zlib")
vcpkg_fixup_pkgconfig()

set(ZLIB_PKGCONFIG_LIBRARY z)
if(VCPKG_TARGET_IS_WINDOWS)
    if(NOT VCPKG_TARGET_IS_MINGW)
        set(ZLIB_PKGCONFIG_LIBRARY libz)
    endif()
    if(VCPKG_LIBRARY_LINKAGE STREQUAL "static")
        string(APPEND ZLIB_PKGCONFIG_LIBRARY s)
    endif()
endif()
vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/lib/pkgconfig/zlib.pc" " -lz" " -l${ZLIB_PKGCONFIG_LIBRARY}")
if(NOT VCPKG_BUILD_TYPE)
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/debug/lib/pkgconfig/zlib.pc" "/include" "/../include")
    if(VCPKG_TARGET_IS_WINDOWS)
        vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/debug/lib/pkgconfig/zlib.pc" " -lz" " -l${ZLIB_PKGCONFIG_LIBRARY}d")
    endif()
endif()

if(VCPKG_LIBRARY_LINKAGE STREQUAL "static")
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/zconf.h" "ifdef ZLIB_DLL" "if 0")
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/share/zlib/ZLIBConfig.cmake" [[_ZLIB_supported_components "shared" "static"]] [[_ZLIB_supported_components "static"]])
else()
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/zconf.h" "ifdef ZLIB_DLL" "if 1")
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/share/zlib/ZLIBConfig.cmake" [[_ZLIB_supported_components "shared" "static"]] [[_ZLIB_supported_components "shared"]])
endif()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/vcpkg-cmake-wrapper.cmake" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
file(COPY "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
