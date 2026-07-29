# librtlsdr 2.1.0 vendorizado (ver tool/setup_native_deps.sh), com o patch
# rtlsdr_open_fd aplicado (vendor/librtlsdr_open_fd.patch) para permitir
# abrir o dongle a partir de um fd USB já obtido pelo Android (sem
# enumeração libusb, que exigiria root). Apenas as fontes da biblioteca —
# sem os utilitários de linha de comando (rtl_sdr.c, rtl_fm.c etc.), que
# não fazem parte do que compilamos aqui.
# Licença: GPLv2 (vendor/librtlsdr/COPYING.GPLv2) — ver docs/native_build.md.

add_library(rtlsdr_core STATIC
    ${CMAKE_CURRENT_LIST_DIR}/librtlsdr/src/librtlsdr.c
    ${CMAKE_CURRENT_LIST_DIR}/librtlsdr/src/tuner_e4k.c
    ${CMAKE_CURRENT_LIST_DIR}/librtlsdr/src/tuner_fc0012.c
    ${CMAKE_CURRENT_LIST_DIR}/librtlsdr/src/tuner_fc0013.c
    ${CMAKE_CURRENT_LIST_DIR}/librtlsdr/src/tuner_fc2580.c
    ${CMAKE_CURRENT_LIST_DIR}/librtlsdr/src/tuner_r82xx.c
)

target_include_directories(rtlsdr_core
    PUBLIC ${CMAKE_CURRENT_LIST_DIR}/librtlsdr/include
    PRIVATE ${CMAKE_CURRENT_LIST_DIR}/librtlsdr/src
)

target_compile_options(rtlsdr_core PRIVATE -Wno-unused-parameter -Wno-unused-variable)
target_link_libraries(rtlsdr_core PUBLIC rtlsdr_libusb PRIVATE m)
