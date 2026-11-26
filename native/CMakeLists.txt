cmake_minimum_required(VERSION 3.22)
project(aosp17_aapt2 LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
include("${CMAKE_CURRENT_LIST_DIR}/aapt2-sources.cmake")

find_package(Threads REQUIRED)
set(ZLIB_USE_STATIC_LIBS ON)
set(CMAKE_FIND_LIBRARY_SUFFIXES .a)
find_package(ZLIB REQUIRED)
find_package(PNG REQUIRED)
find_package(EXPAT REQUIRED)
unset(CMAKE_FIND_LIBRARY_SUFFIXES)

set(framework "${AOSP_SOURCE}/frameworks/base")
set(soong "${AOSP_SOURCE}/build/soong")
set(system "${AOSP_SOURCE}/system")
set(incremental "${system}/incremental_delivery/incfs")
set(aapt "${framework}/tools/aapt2")

include_directories(
    "${system}/libbase/include"
    "${system}/logging/liblog/include"
    "${system}/core/libutils/include"
    "${system}/core/libutils/binder/include"
    "${system}/core/libcutils/include"
    "${system}/core/libprocessgroup/include"
    "${system}/core/libsystem/include"
    "${system}/libziparchive/include"
    "${system}/libziparchive/incfs_support/include"
    "${incremental}/util/include"
    "${framework}/libs/androidfw/include"
    "${framework}/libs/androidfw/include_pathutils"
    "${framework}/cmds/idmap2/libidmap2_policies/include"
    "${soong}/cc/libbuildversion/include"
    "${AOSP_SOURCE}/external/fmtlib/include"
    "${AOSP_JDK}/include" "${AOSP_JDK}/include/linux"
    "${AOSP_SOURCE}/external/googletest/googletest/include" "${AOSP_WORK}/generated/include"
    "${aapt}"
)
add_compile_definitions(
    _FILE_OFFSET_BITS=64 _GNU_SOURCE FMT_HEADER_ONLY STATIC_ANDROIDFW_FOR_TOOLS
    INCFS_SUPPORT_DISABLED=1 ZLIB_CONST LIBLOG_LOG_TAG=1006 SNET_EVENT_LOG_TAG=1397638484
    ANDROID_DEBUGGABLE=0
)
add_compile_options(-ffunction-sections -fdata-sections)

add_library(aapt2_host_support STATIC
    ${ANDROID_BASE}
    ${ANDROID_LOG}
    ${ANDROID_UTILS}
    ${ANDROID_UTILS_BINDER}
    ${ANDROID_CUTILS}
    ${ANDROID_ZIP}
    "${incremental}/util/map_ptr.cpp"
    "${soong}/cc/libbuildversion/libbuildversion.cpp"
)
target_link_libraries(aapt2_host_support PUBLIC Threads::Threads ZLIB::ZLIB)

if(EXISTS "${AOSP_WORK}/generated/include/android_content_res.h")
    set(ABSL_BUILD_TESTING OFF)
    set(ABSL_PROPAGATE_CXX_STD ON)
    set(ABSL_USE_GOOGLETEST_HEAD OFF)
    add_subdirectory("${AOSP_SOURCE}/external/abseil-cpp" absl-build EXCLUDE_FROM_ALL)
    set(protobuf_BUILD_TESTS OFF)
    set(protobuf_BUILD_EXAMPLES OFF)
    set(protobuf_BUILD_LIBUPB OFF)
    set(protobuf_BUILD_PROTOC_BINARIES OFF)
    set(protobuf_LOCAL_DEPENDENCIES_ONLY ON)
    set(protobuf_INSTALL OFF)
    set(protobuf_WITH_ZLIB OFF)
    add_subdirectory("${AOSP_SOURCE}/external/protobuf" protobuf-build EXCLUDE_FROM_ALL)
    add_executable(host_protoc IMPORTED)
    set_target_properties(host_protoc PROPERTIES IMPORTED_LOCATION "${AOSP_PROTOC}")
    file(GLOB flag_sources CONFIGURE_DEPENDS "${AOSP_WORK}/generated/*.cc")
    set(protos ${AAPT2})
    list(FILTER protos INCLUDE REGEX "[.]proto$")
    list(FILTER AAPT2 EXCLUDE REGEX "[.]proto$")
    set(generated_protos "")
    set(proto_output "${CMAKE_CURRENT_BINARY_DIR}/aosp-protos")
    file(MAKE_DIRECTORY "${proto_output}")
    foreach(proto IN LISTS protos)
        file(RELATIVE_PATH relative "${AOSP_SOURCE}" "${proto}")
        string(REGEX REPLACE "[.]proto$" ".pb" stem "${relative}")
        set(source_output "${proto_output}/${stem}.cc")
        set(header_output "${proto_output}/${stem}.h")
        add_custom_command(
            OUTPUT "${source_output}" "${header_output}"
            COMMAND host_protoc "--proto_path=${AOSP_SOURCE}" "--cpp_out=lite:${proto_output}" "${proto}"
            DEPENDS ${protos}
            VERBATIM
        )
        list(APPEND generated_protos "${source_output}" "${header_output}")
    endforeach()
    add_library(aapt2_protos STATIC ${generated_protos})
    target_include_directories(aapt2_protos PUBLIC "${proto_output}"
        "${AOSP_SOURCE}/external/protobuf/third_party/utf8_range"
        "${proto_output}/frameworks/base/tools/aapt2")
    target_link_libraries(aapt2_protos PUBLIC protobuf::libprotobuf-lite)
    add_executable(aapt2 ${AAPT2} ${ANDROIDFW} ${flag_sources})
    target_include_directories(aapt2 PRIVATE "${AOSP_SOURCE}/frameworks/native/include")
    target_compile_options(aapt2 PRIVATE -fno-exceptions -fno-rtti -Wno-deprecated-declarations)
    target_link_options(aapt2 PRIVATE -Wl,--gc-sections)
    target_link_libraries(aapt2 PRIVATE aapt2_host_support aapt2_protos PNG::PNG EXPAT::EXPAT)
endif()

