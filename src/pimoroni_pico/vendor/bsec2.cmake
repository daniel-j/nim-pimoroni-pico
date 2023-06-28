set(DRIVER_NAME bsec2)
add_library(${DRIVER_NAME} INTERFACE)

target_link_libraries(${DRIVER_NAME} INTERFACE
  bme68x
  ${CMAKE_CURRENT_LIST_DIR}/Bosch-BSEC2-Library/src/cortex-m0plus/libalgobsec.a
)

target_include_directories(${DRIVER_NAME} INTERFACE ${CMAKE_CURRENT_LIST_DIR}/Bosch-BSEC2-Library/src/inc)

# We can't control the uninitialized result variables in the BME68X API
# so demote unitialized to a warning for this target.
target_compile_options(${DRIVER_NAME} INTERFACE -Wno-error=uninitialized)
