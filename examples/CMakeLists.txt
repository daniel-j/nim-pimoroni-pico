cmake_minimum_required(VERSION 3.13)

# Set CMake build type. Debug, Release, MinSizeRel, RelWithDebInfo
set(CMAKE_BUILD_TYPE Debug)

# Set standards
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

# initialize pico-sdk from GIT
# (note this can come from environment, CMake cache etc)
#set(PICO_SDK_FETCH_FROM_GIT on)
#set(PICO_SDK_PATH ENV{PICO_SDK_PATH}) # Set by piconim

# Set board type here
if(NOT DEFINED PICO_BOARD)
  set(PICO_BOARD pico)
endif()

# Support C++ exceptions with Nim
set(PICO_CXX_ENABLE_EXCEPTIONS 1)

# Uncomment to disable picotool binary info
# set(PICO_NO_BINARY_INFO 1)

# Uncomment to enable fastest supported clock speed
set(PICO_USE_FASTEST_SUPPORTED_CLOCK 1)

execute_process(
  COMMAND nimble path picostdlib
  OUTPUT_VARIABLE PICOSTDLIB_DIR
  OUTPUT_STRIP_TRAILING_WHITESPACE
)

set(pico_generate_pio_header_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")

# note: this must happen before project()
include(${PICOSTDLIB_DIR}/picostdlib/cmake/pico_sdk_import.cmake)

project(examples C CXX ASM)


include(FetchContent)

FetchContent_Declare(mbedtls
  GIT_REPOSITORY https://github.com/Mbed-TLS/mbedtls.git
  GIT_TAG        v2.28.6
)

FetchContent_Declare(lwip
  GIT_REPOSITORY https://git.savannah.gnu.org/git/lwip.git
  GIT_TAG        STABLE-2_2_0_RELEASE
)

FetchContent_Declare(freertos_kernel
  GIT_REPOSITORY https://github.com/FreeRTOS/FreeRTOS-Kernel.git
  GIT_TAG        V11.0.1
)

# fetch and use alternative mbedtls version
#FetchContent_MakeAvailable(mbedtls)
#set(PICO_MBEDTLS_PATH ${mbedtls_SOURCE_DIR})

# fetch and use alternative lwip version
#FetchContent_MakeAvailable(lwip)
#set(PICO_LWIP_PATH ${lwip_SOURCE_DIR})

# fetch and initialize FreeRTOS-Kernel
#FetchContent_MakeAvailable(freertos_kernel)
#include(${freertos_kernel_SOURCE_DIR}/portable/ThirdParty/GCC/RP2040/FreeRTOS_Kernel_import.cmake)


# initialize the Raspberry Pi Pico SDK
pico_sdk_init()

include(${PICOSTDLIB_DIR}/picostdlib/cmake/picostdlib.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/../src/pimoroni_pico/cmake/pimoroni_pico.cmake)

function(add_example target name)
  add_executable(${target})

  picostdlib_target(${target} ${name})

  # set_target_properties(${target} PROPERTIES LINKER_LANGUAGE CXX)

  target_include_directories(${target} PRIVATE
    ${CMAKE_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/../csource
  )

  target_link_libraries(${target}
    # Additional libraries
  )

  target_compile_definitions(${target} PRIVATE
    # CYW43_HOST_NAME="PicoW"
    PICO_STDIO_USB_CONNECT_WAIT_TIMEOUT_MS=2000
    PICO_VFS_NO_RTC=0
    _POSIX_TIMERS=200809L
    _POSIX_MONOTONIC_CLOCK=200809L
    _POSIX_CPUTIME=200809L
    _POSIX_THREAD_CPUTIME=200809L
  )

  # enable usb output, disable uart output
  pico_enable_stdio_usb(${target} 1)
  pico_enable_stdio_uart(${target} 0)

  # create map/bin/hex/uf2 file etc.
  pico_add_extra_outputs(${target})

  # add url via pico_set_program_url
  # pico_set_program_url(${target} "")
endfunction()

if(NOT PICO_CYW43_SUPPORTED)

else()
  # Galaxy Unicorn
  add_example(galactic_unicorn_lightmeter lightmeter)
  add_example(galactic_unicorn_rainbow rainbow)
  add_example(galactic_unicorn_simple simple)

  # Inky Frame
  add_example(inky_frame_slideshow slideshow)
  add_example(inky_frame_slideshow_gphotos slideshow_gphotos)
  # pico_startup_pinmask(inky_frame_slideshow "((0b1 << 2) | (0b1 << 6))")
  add_example(inky_frame_sleepy_head sleepy_head)
  # pico_startup_pinmask(inky_frame_sleepy_head "((0b1 << 2) | (0b1 << 6))")
endif()
