add_executable(spdif)

pico_generate_pio_header(spdif ${CMAKE_CURRENT_LIST_DIR}/spdif.pio)

target_sources(spdif PRIVATE main.c)

target_link_libraries(spdif PRIVATE
        pico_stdlib 
        hardware_pio
)
pico_add_extra_outputs(spdif)
pico_enable_stdio_usb(spdif 1)
pico_enable_stdio_uart(spdif 0)
