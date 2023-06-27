set(DRIVER_NAME bme68x)
add_library(${DRIVER_NAME} INTERFACE)

target_sources(${DRIVER_NAME} INTERFACE
  ${CMAKE_CURRENT_LIST_DIR}/BME68x-Sensor-API/bme68x.c
)

target_include_directories(${DRIVER_NAME} INTERFACE ${CMAKE_CURRENT_LIST_DIR}/BME68x-Sensor-API)

# We can't control the uninitialized result variables in the BME68X API
# so demote unitialized to a warning for this target.
target_compile_options(${DRIVER_NAME} INTERFACE -Wno-error=uninitialized)
