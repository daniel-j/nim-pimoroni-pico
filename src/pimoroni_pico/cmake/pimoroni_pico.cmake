set(PIMORONI_PICO_DIR ${CMAKE_CURRENT_LIST_DIR})

add_subdirectory(${PIMORONI_PICO_DIR}/../vendor pimoroni_pico_vendor)

function(pico_sdk_patch_source filename patch_file target)
  # Patch source file
  add_custom_command(
    COMMAND ${CMAKE_COMMAND}
    -Din_file:FILEPATH=${PICO_SDK_PATH}/${filename}
    -Dpatch_file:FILEPATH=${patch_file}
    -Dout_file:FILEPATH=${CMAKE_CURRENT_BINARY_DIR}/pico-sdk/${filename}
    -Dwork_dir:FILEPATH=${PICO_SDK_PATH}
    -P ${PIMORONI_PICO_DIR}/PatchFile.cmake
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/pico-sdk/${filename}
    DEPENDS ${PIMORONI_PICO_DIR}/PatchFile.cmake ${PICO_SDK_PATH}/${filename} ${patch_file}
  )

  # Add patched source
  target_sources(${target} INTERFACE
    ${CMAKE_CURRENT_BINARY_DIR}/pico-sdk/${filename}
  )

  # Disable source
  set_source_files_properties(${PICO_SDK_PATH}/${filename}
    PROPERTIES HEADER_FILE_ONLY ON)

endfunction()


function(pico_startup_pinmask target mask)
  target_compile_definitions(${target} PRIVATE
    PICO_WAKEUP_PIN_MASK=${mask}
    PICO_WAKEUP_PIN_DIR=${mask}
    PICO_WAKEUP_PIN_VALUE=${mask}
  )
endfunction()
