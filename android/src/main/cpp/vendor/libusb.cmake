# libusb 1.0.30 vendorizado (ver tool/setup_native_deps.sh) — lista de
# fontes idêntica à usada pelo próprio libusb em android/jni/libusb.mk.
# Licença: LGPL-2.1 (vendor/libusb/COPYING.LGPL-2.1).

add_library(rtlsdr_libusb STATIC
    ${CMAKE_CURRENT_LIST_DIR}/libusb/libusb/core.c
    ${CMAKE_CURRENT_LIST_DIR}/libusb/libusb/descriptor.c
    ${CMAKE_CURRENT_LIST_DIR}/libusb/libusb/hotplug.c
    ${CMAKE_CURRENT_LIST_DIR}/libusb/libusb/io.c
    ${CMAKE_CURRENT_LIST_DIR}/libusb/libusb/sync.c
    ${CMAKE_CURRENT_LIST_DIR}/libusb/libusb/strerror.c
    ${CMAKE_CURRENT_LIST_DIR}/libusb/libusb/os/linux_usbfs.c
    ${CMAKE_CURRENT_LIST_DIR}/libusb/libusb/os/events_posix.c
    ${CMAKE_CURRENT_LIST_DIR}/libusb/libusb/os/threads_posix.c
    ${CMAKE_CURRENT_LIST_DIR}/libusb/libusb/os/linux_netlink.c
)

target_include_directories(rtlsdr_libusb
    PUBLIC ${CMAKE_CURRENT_LIST_DIR}/libusb/libusb
    PRIVATE ${CMAKE_CURRENT_LIST_DIR}/libusb/android_config
)

# android/config.h oficial do projeto libusb já define PLATFORM_POSIX etc.
# para este cenário (ver vendor/libusb/android_config/config.h).
target_compile_options(rtlsdr_libusb PRIVATE -fvisibility=hidden -Wno-unused-parameter)
target_link_libraries(rtlsdr_libusb PUBLIC log)
