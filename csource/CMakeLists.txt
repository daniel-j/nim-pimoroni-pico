cmake_minimum_required(VERSION 3.13)

SET(CMAKE_BUILD_TYPE MinSizeRel)

if(NOT DEFINED OUTPUT_NAME)
  set(OUTPUT_NAME pimoroni_pico)
endif()

# initialize pico-sdk from GIT
# (note this can come from environment, CMake cache etc)
#set(PICO_SDK_FETCH_FROM_GIT on)

# Set board type here
set(PICO_BOARD pico_w)

# Support C++ exceptions with Nim
set(PICO_CXX_ENABLE_EXCEPTIONS 1)

# Uncomment to disable picotool binary info
# set(PICO_NO_BINARY_INFO 1)

# pico_sdk_import.cmake is a single file copied from this SDK
# note: this must happen before project()
include(pico_sdk_import.cmake)

# Set standards
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

project(${OUTPUT_NAME})

# initialize the Raspberry Pi Pico SDK
pico_sdk_init()

# hide a warning in lwip
set_source_files_properties(
  "${PICO_LWIP_PATH}/src/apps/altcp_tls/altcp_tls_mbedtls.c"
  PROPERTIES COMPILE_OPTIONS "-Wno-unused-result"
)

# # fetch and initialize FreeRTOS-Kernel
# include(FetchContent)
# FetchContent_Declare( freertos_kernel
#   GIT_REPOSITORY https://github.com/FreeRTOS/FreeRTOS-Kernel.git
#   GIT_TAG        V10.5.1
# )
# FetchContent_Populate(freertos_kernel)
# set(FREERTOS_KERNEL_PATH ${freertos_kernel_SOURCE_DIR})
# include(${FREERTOS_KERNEL_PATH}/portable/ThirdParty/GCC/RP2040/FreeRTOS_Kernel_import.cmake)

set(NIMCACHE_DIR "${CMAKE_CURRENT_BINARY_DIR}/nimcache")
set(NIMCACHE_JSON_FILE "${NIMCACHE_DIR}/${OUTPUT_NAME}.cached.json")

# add_custom_target(nimble DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/imports.cmake)

# Get the Nim include path to get nimbase.h
execute_process(
  COMMAND nim dump --dump.format:json --hints:off -
  OUTPUT_VARIABLE NIM_DUMP_JSON
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
string(JSON NIM_LIB_PATH GET "${NIM_DUMP_JSON}" libpath)

set_directory_properties(PROPERTIES CMAKE_CONFIGURE_DEPENDS ${NIMCACHE_JSON_FILE})

if(EXISTS ${NIMCACHE_JSON_FILE})
  # Read the nimcache JSON file to get the source files
  set(NimSources "")
  file(READ "${NIMCACHE_JSON_FILE}" NIMCACHE_JSON_DATA)
  if(NIMCACHE_JSON_DATA)
    string(JSON cfilelength LENGTH "${NIMCACHE_JSON_DATA}" compile)
    math(EXPR cfilelength "${cfilelength} - 1")
    foreach(IDX RANGE ${cfilelength})
        string(JSON CUR_FILE GET "${NIMCACHE_JSON_DATA}" compile ${IDX} 0)
        string(REPLACE "\\" "/" CUR_FILE "${CUR_FILE}")
        list(APPEND NimSources ${CUR_FILE})
    endforeach()
  endif()
  # Suppress gcc warnings for nim-generated files
  set_source_files_properties(${NimSources} PROPERTIES COMPILE_OPTIONS "-w")
endif()


add_executable(${OUTPUT_NAME} ${NimSources})

set_target_properties(${OUTPUT_NAME} PROPERTIES LINKER_LANGUAGE CXX)

if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/imports.cmake)
  include(imports.cmake) # Include our generated file
  link_imported_libs(${OUTPUT_NAME}) # call our generated function to import all libs we're using
else()
  # fallback to something
  target_link_libraries(${OUTPUT_NAME} pico_stdlib)
endif()

# Add directory containing this CMakeLists file to include search path.
# This is required so that the lwipopts.h file is found. Other headers
# required for a project can also be placed here.
target_include_directories(${OUTPUT_NAME} PUBLIC
  ${CMAKE_CURRENT_LIST_DIR}
  ${NIM_LIB_PATH}
  ${PICO_LWIP_PATH}/src/include/compat/posix
  #${FREERTOS_KERNEL_PATH}/include
  #${FREERTOS_KERNEL_PATH}/portable/ThirdParty/GCC/RP2040/include
)

add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../src/pimoroni_pico/vendor vendor)

# Add additional libraries, such as the wifi package. It's not automatically loaded
target_link_libraries(${OUTPUT_NAME}
  pico_cyw43_arch_lwip_threadsafe_background
  pico_lwip_mbedtls pico_mbedtls
  sdcard
  # ${CMAKE_CURRENT_SOURCE_DIR}/../example
)
# pico_cyw43_arch_lwip_sys_freertos FreeRTOS-Kernel-Heap3

target_compile_definitions(${OUTPUT_NAME} PRIVATE
  # CYW43_HOST_NAME="PicoW"
  #PICO_STDIO_USB_CONNECT_WAIT_TIMEOUT_MS=2000
  _POSIX_MONOTONIC_CLOCK=1
  # PING_USE_SOCKETS=1
)

target_compile_options(${OUTPUT_NAME} PRIVATE "-fshort-enums")

# enable usb output, disable uart output
pico_enable_stdio_usb(${OUTPUT_NAME} 1)
pico_enable_stdio_uart(${OUTPUT_NAME} 0)

# create map/bin/hex/uf2 file etc.
pico_add_extra_outputs(${OUTPUT_NAME})

# add url via pico_set_program_url
#pico_set_program_url(${OUTPUT_NAME} "")

