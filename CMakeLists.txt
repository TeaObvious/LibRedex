cmake_minimum_required(VERSION 3.20)

project(LibRedex LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(
    LIBREDEX_OUTPUT_BASE
    "${CMAKE_SOURCE_DIR}/Binaries"
    CACHE PATH
    "Legacy output base directory for libredex artifacts"
)

set(THIRD_PARTY_DIR "${CMAKE_SOURCE_DIR}/third_party")

set(
    BOOST_INCLUDE_LIBRARIES
    "filesystem;system;thread;random;regex;chrono;date_time;atomic"
    CACHE STRING
    "Boost libraries to build"
)

include(ExternalProject)

set(BOOST_SOURCE_DIR "${THIRD_PARTY_DIR}/boost")
set(BOOST_STAGE_DIR "${CMAKE_BINARY_DIR}/third_party/boost/stage")
set(BOOST_BUILD_DIR "${CMAKE_BINARY_DIR}/third_party/boost/build")
set(BOOST_INCLUDEDIR "${BOOST_SOURCE_DIR}")

string(REPLACE ";" "," BOOST_WITH_LIBS_CSV "${BOOST_INCLUDE_LIBRARIES}")
set(BOOST_B2_WITH_LIB_ARGS "")
foreach(boost_lib IN LISTS BOOST_INCLUDE_LIBRARIES)
    list(APPEND BOOST_B2_WITH_LIB_ARGS "--with-${boost_lib}")
endforeach()

if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    set(BOOST_B2_TOOLSET "clang")
else()
    set(BOOST_B2_TOOLSET "gcc")
endif()

if(CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(BOOST_B2_ADDRESS_MODEL "64")
else()
    set(BOOST_B2_ADDRESS_MODEL "32")
endif()

if(CMAKE_BUILD_TYPE)
    string(TOLOWER "${CMAKE_BUILD_TYPE}" BOOST_B2_VARIANT)
else()
    set(BOOST_B2_VARIANT "release")
endif()

set(BOOST_B2_TARGET_OS_ARG "")
if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    set(BOOST_B2_TARGET_OS_ARG "target-os=windows")
endif()

set(BOOST_B2_CXXFLAGS_ARG "")
if(NOT WIN32)
    set(BOOST_B2_CXXFLAGS_ARG "cxxflags=-fPIC")
endif()

if(WIN32 AND NOT MSYS)
    set(BOOST_BOOTSTRAP "${BOOST_SOURCE_DIR}/bootstrap.bat")
    set(BOOST_B2_EXECUTABLE "${BOOST_SOURCE_DIR}/b2.exe")
else()
    set(BOOST_BOOTSTRAP "${BOOST_SOURCE_DIR}/bootstrap.sh")
    set(BOOST_B2_EXECUTABLE "${BOOST_SOURCE_DIR}/b2")
endif()

if(MSVC)
    set(BOOST_LIB_SUFFIX ".lib")
else()
    set(BOOST_LIB_SUFFIX ".a")
endif()

set(BOOST_BYPRODUCTS "")
foreach(boost_lib IN LISTS BOOST_INCLUDE_LIBRARIES)
    if(boost_lib STREQUAL "system")
        continue()
    endif()
    list(APPEND BOOST_BYPRODUCTS "${BOOST_STAGE_DIR}/lib/libboost_${boost_lib}${BOOST_LIB_SUFFIX}")
endforeach()

ExternalProject_Add(
    boost_ep
    SOURCE_DIR "${BOOST_SOURCE_DIR}"
    BUILD_IN_SOURCE 1
    CONFIGURE_COMMAND "${BOOST_BOOTSTRAP}"
    BUILD_COMMAND
        "${BOOST_B2_EXECUTABLE}"
        ${BOOST_B2_WITH_LIB_ARGS}
        "link=static"
        "threading=multi"
        "variant=${BOOST_B2_VARIANT}"
        "address-model=${BOOST_B2_ADDRESS_MODEL}"
        "--layout=system"
        "--build-dir=${BOOST_BUILD_DIR}"
        "--stagedir=${BOOST_STAGE_DIR}"
        "toolset=${BOOST_B2_TOOLSET}"
        ${BOOST_B2_TARGET_OS_ARG}
        ${BOOST_B2_CXXFLAGS_ARG}
    INSTALL_COMMAND ""
    BUILD_BYPRODUCTS ${BOOST_BYPRODUCTS}
)

foreach(boost_lib IN LISTS BOOST_INCLUDE_LIBRARIES)
    set(boost_target "Boost::${boost_lib}")
    if(boost_lib STREQUAL "system")
        add_library(${boost_target} INTERFACE IMPORTED GLOBAL)
        set_target_properties(${boost_target} PROPERTIES
            INTERFACE_INCLUDE_DIRECTORIES "${BOOST_INCLUDEDIR}"
            INTERFACE_COMPILE_DEFINITIONS "BOOST_ERROR_CODE_HEADER_ONLY;BOOST_SYSTEM_NO_LIB"
        )
    else()
        add_library(${boost_target} STATIC IMPORTED GLOBAL)
        set_target_properties(${boost_target} PROPERTIES
            IMPORTED_LOCATION "${BOOST_STAGE_DIR}/lib/libboost_${boost_lib}${BOOST_LIB_SUFFIX}"
            INTERFACE_INCLUDE_DIRECTORIES "${BOOST_INCLUDEDIR}"
        )
        add_dependencies(${boost_target} boost_ep)
    endif()
endforeach()

if(WIN32)
    set(WITH_SSL "SCHANNEL" CACHE STRING "Use Schannel for TLS on Windows" FORCE)
else()
    set(WITH_SSL "OPENSSL" CACHE STRING "Use OpenSSL for TLS on Unix" FORCE)
endif()
set(DEFAULT_SSL_VERIFY_SERVER_CERT OFF CACHE BOOL "Disable SSL verification" FORCE)
set(WITH_UNIT_TESTS OFF CACHE BOOL "Disable MariaDB Connector/C unit tests" FORCE)
set(WITH_MSI OFF CACHE BOOL "Disable MSI packaging" FORCE)
set(WITH_SIGNCODE OFF CACHE BOOL "Disable code signing" FORCE)
set(WITH_RTC OFF CACHE BOOL "Disable /RTC" FORCE)
set(WITH_MYSQLCOMPAT OFF CACHE BOOL "Disable MySQL compatibility symlinks" FORCE)
set(INSTALL_PLUGINDIR "lib/mariadb/plugin" CACHE PATH "Install dir for MariaDB plugins" FORCE)

add_subdirectory("${THIRD_PARTY_DIR}/mariadb-connector-c" EXCLUDE_FROM_ALL)

set(MARIADB_CONNECTOR_SOURCE_DIR "${THIRD_PARTY_DIR}/mariadb-connector-c" CACHE INTERNAL "")
set(MARIADB_CONNECTOR_BINARY_DIR "${CMAKE_BINARY_DIR}/third_party/mariadb-connector-c" CACHE INTERNAL "")

add_subdirectory("${CMAKE_SOURCE_DIR}/libredex/Source")
