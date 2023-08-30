cmake_minimum_required(VERSION 3.13)

# Set CMake build type. Debug, Release, MinSizeRel, RelWithDebInfo
set(CMAKE_BUILD_TYPE Release)

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

execute_process(
  COMMAND nimble path picostdlib
  OUTPUT_VARIABLE PICOSTDLIB_DIR
  OUTPUT_STRIP_TRAILING_WHITESPACE
)

# note: this must happen before project()
include(${PICOSTDLIB_DIR}/picostdlib/cmake/pico_sdk_import.cmake)

project(examples C CXX ASM)

# initialize the Raspberry Pi Pico SDK
pico_sdk_init()

# # fetch and initialize FreeRTOS-Kernel
# include(FetchContent)
# FetchContent_Declare( freertos_kernel
#   GIT_REPOSITORY https://github.com/FreeRTOS/FreeRTOS-Kernel.git
#   GIT_TAG        V10.5.1
# )
# FetchContent_Populate(freertos_kernel)
# include(${freertos_kernel_SOURCE_DIR}/portable/ThirdParty/GCC/RP2040/FreeRTOS_Kernel_import.cmake)

include(${PICOSTDLIB_DIR}/picostdlib/cmake/picostdlib.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/../src/pimoroni_pico/cmake/pimoroni_pico.cmake)

# Pico SDK patches
# pico_sdk_patch_source("src/rp2_common/pico_standard_link/crt0.S" "${PIMORONI_PICO_DIR}/pico_sdk_crt0.patch" pico_standard_link)
# pico_sdk_patch_source("src/rp2_common/pico_runtime/runtime.c" "${PIMORONI_PICO_DIR}/pico_sdk_runtime.patch" pico_runtime)
# pico_sdk_patch_source("src/rp2_common/pico_standard_link/crt0.S" "${PIMORONI_PICO_DIR}/pico_sdk_crt0_startup_overclock.patch" pico_standard_link)


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
    PICO_STDIO_USB_CONNECT_WAIT_TIMEOUT_MS=0
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
  # pico_startup_pinmask(inky_frame_slideshow "((0b1 << 2) | (0b1 << 6))")
  add_example(inky_frame_sleepy_head sleepy_head)
  # pico_startup_pinmask(inky_frame_sleepy_head "((0b1 << 2) | (0b1 << 6))")
endif()
