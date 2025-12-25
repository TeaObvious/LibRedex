set(LIBREDEX_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}")

if(NOT DEFINED LIBREDEX_LIBRARY_SUFFIX)
    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
        set(LIBREDEX_LIBRARY_SUFFIX "_x64")
    else()
        set(LIBREDEX_LIBRARY_SUFFIX "")
    endif()
endif()

file(GLOB_RECURSE LIBREDEX_SOURCES
    CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/*.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/*.cpp"
)
list(FILTER LIBREDEX_SOURCES EXCLUDE REGEX "/TestApps/")

if(WIN32)
    list(APPEND LIBREDEX_SOURCES "${LIBREDEX_SOURCE_DIR}/redex.rc")
endif()

add_library(libredex SHARED ${LIBREDEX_SOURCES})
add_library(LibRedex::libredex ALIAS libredex)

string(TIMESTAMP LIBREDEX_BUILD_TIME "%Y%m%d%H%M")

set_target_properties(libredex PROPERTIES
    OUTPUT_NAME "redex${LIBREDEX_LIBRARY_SUFFIX}"
    POSITION_INDEPENDENT_CODE ON
)

target_compile_features(libredex PRIVATE cxx_std_14)

target_compile_definitions(libredex PRIVATE
    BUILD_TIME=\"${LIBREDEX_BUILD_TIME}\"
    $<$<CONFIG:Debug>:DEBUG>
)

target_include_directories(libredex PRIVATE
    "${LIBREDEX_SOURCE_DIR}"
    "${MARIADB_CONNECTOR_SOURCE_DIR}/include"
    "${MARIADB_CONNECTOR_BINARY_DIR}/include"
    "${BOOST_INCLUDEDIR}"
)

find_package(Threads REQUIRED)

set(platform_libs "")
if(WIN32)
    list(APPEND platform_libs rpcrt4 wsock32 ws2_32)
else()
    list(APPEND platform_libs uuid dl)
endif()

if(WIN32)
    set(platform_dir "Windows")
else()
    set(platform_dir "Linux")
endif()

set(output_dir "${LIBREDEX_OUTPUT_BASE}/${platform_dir}/$<CONFIG>")

set_target_properties(libredex PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${output_dir}"
    LIBRARY_OUTPUT_DIRECTORY "${output_dir}"
    ARCHIVE_OUTPUT_DIRECTORY "${output_dir}"
)

target_link_libraries(libredex PRIVATE
    ${platform_libs}
    Threads::Threads
    mariadbclient
    Boost::filesystem
    Boost::thread
    Boost::system
    Boost::random
    Boost::regex
    Boost::chrono
    Boost::date_time
    Boost::atomic
)

add_dependencies(libredex boost_ep)
