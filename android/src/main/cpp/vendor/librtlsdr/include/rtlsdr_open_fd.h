/*
 * Android-specific extension to librtlsdr: open a device from a
 * libusb_device_handle obtained via libusb_wrap_sys_device() over a file
 * descriptor that Android's UsbManager/UsbDeviceConnection (Java) already
 * opened and granted permission for.
 *
 * This is a small addition on top of the upstream v2.1.0 API (not part of
 * the official librtlsdr headers) — see vendor/librtlsdr_open_fd.patch for
 * the corresponding change in src/librtlsdr.c. Kept in a separate header
 * (rather than editing rtl-sdr.h) so upstream's public header stays
 * untouched and this stays a self-contained, reviewable addition.
 */
#ifndef __RTLSDR_OPEN_FD_H
#define __RTLSDR_OPEN_FD_H

#include <libusb.h>
#include "rtl-sdr.h"

#ifdef __cplusplus
extern "C" {
#endif

RTLSDR_API int rtlsdr_open_fd(rtlsdr_dev_t **out_dev, libusb_context *ctx, libusb_device_handle *devh);

#ifdef __cplusplus
}
#endif

#endif
