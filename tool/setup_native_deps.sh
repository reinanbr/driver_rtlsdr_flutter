#!/usr/bin/env bash
# Vendoriza libusb e librtlsdr em android/src/main/cpp/vendor/.
#
# As fontes já estão commitadas no repositório — este script existe para
# re-vendorizar/atualizar as libs no futuro (nova tag, ou setup em outra
# máquina caso os diretórios vendor/ tenham sido removidos), reproduzindo
# exatamente o processo usado para gerar o estado atual.
#
# Tags fixas (não branches) para reprodutibilidade. licença: libusb é
# LGPL-2.1, librtlsdr é GPLv2 — ver docs/native_build.md.
set -euo pipefail

LIBUSB_TAG="v1.0.30"
LIBRTLSDR_TAG="v2.1.0"
KISSFFT_TAG="v131"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CPP_DIR="$ROOT_DIR/android/src/main/cpp"
VENDOR_DIR="$CPP_DIR/vendor"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Baixando libusb $LIBUSB_TAG"
curl -sL "https://codeload.github.com/libusb/libusb/tar.gz/refs/tags/${LIBUSB_TAG}" -o "$WORK_DIR/libusb.tar.gz"
mkdir -p "$WORK_DIR/libusb-src"
tar xzf "$WORK_DIR/libusb.tar.gz" -C "$WORK_DIR/libusb-src" --strip-components=1

echo "==> Baixando librtlsdr $LIBRTLSDR_TAG"
curl -sL "https://codeload.github.com/librtlsdr/librtlsdr/tar.gz/refs/tags/${LIBRTLSDR_TAG}" -o "$WORK_DIR/librtlsdr.tar.gz"
mkdir -p "$WORK_DIR/librtlsdr-src"
tar xzf "$WORK_DIR/librtlsdr.tar.gz" -C "$WORK_DIR/librtlsdr-src" --strip-components=1

echo "==> Vendorizando libusb (arquivos listados em android/jni/libusb.mk do próprio libusb)"
LIBUSB_DST="$VENDOR_DIR/libusb"
rm -rf "$LIBUSB_DST"
mkdir -p "$LIBUSB_DST/libusb/os" "$LIBUSB_DST/android_config"
SRC="$WORK_DIR/libusb-src"
for f in core.c descriptor.c hotplug.c io.c sync.c strerror.c; do
  cp "$SRC/libusb/$f" "$LIBUSB_DST/libusb/$f"
done
for f in linux_usbfs.c events_posix.c threads_posix.c linux_netlink.c linux_usbfs.h events_posix.h threads_posix.h; do
  cp "$SRC/libusb/os/$f" "$LIBUSB_DST/libusb/os/$f"
done
cp "$SRC/libusb/libusb.h" "$SRC/libusb/libusbi.h" "$SRC/libusb/version.h" "$SRC/libusb/version_nano.h" "$LIBUSB_DST/libusb/"
cp "$SRC/android/config.h" "$LIBUSB_DST/android_config/config.h"
cp "$SRC/COPYING" "$LIBUSB_DST/COPYING.LGPL-2.1"

echo "==> Vendorizando librtlsdr (apenas fontes da biblioteca, sem os utilitários rtl_*.c)"
RTLSDR_DST="$VENDOR_DIR/librtlsdr"
rm -rf "$RTLSDR_DST"
mkdir -p "$RTLSDR_DST/src" "$RTLSDR_DST/include"
SRC="$WORK_DIR/librtlsdr-src"
for f in librtlsdr.c tuner_e4k.c tuner_fc0012.c tuner_fc0013.c tuner_fc2580.c tuner_r82xx.c; do
  cp "$SRC/src/$f" "$RTLSDR_DST/src/$f"
done
for f in rtl-sdr.h rtl-sdr_export.h rtlsdr_i2c.h rtlsdr_rpc.h tuner_e4k.h tuner_fc0012.h tuner_fc0013.h tuner_fc2580.h tuner_r82xx.h reg_field.h; do
  cp "$SRC/include/$f" "$RTLSDR_DST/include/$f"
done
cp "$SRC/COPYING" "$RTLSDR_DST/COPYING.GPLv2"

# rtl_app_ver.h normalmente é gerado pelo CMake do projeto a partir do .in;
# como não usamos o build system deles, geramos um fixo aqui.
cat > "$RTLSDR_DST/src/rtl_app_ver.h" <<EOF
#ifndef __RTL_APP_VER_H
#define __RTL_APP_VER_H

#define APP_VER_MAJOR	2
#define APP_VER_MINOR	1
#define APP_VER_ID	"github.com/librtlsdr (vendored, Android)"

#define VER_TO_STRING(x)	#x
#define VAL_VER_TO_STR(x)	VER_TO_STRING(x)

#endif
EOF

echo "==> Aplicando patch rtlsdr_open_fd (fd handoff Android, sem enumeração libusb)"
patch "$RTLSDR_DST/src/librtlsdr.c" < "$VENDOR_DIR/librtlsdr_open_fd.patch"

# rtlsdr_open_fd.h declara a função nova (não é uma modificação de arquivo
# existente, então não aparece no .patch acima) — gerado diretamente aqui.
cat > "$RTLSDR_DST/include/rtlsdr_open_fd.h" <<'HEADER_EOF'
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
HEADER_EOF

echo "==> Baixando KissFFT $KISSFFT_TAG"
curl -sL "https://codeload.github.com/mborgerding/kissfft/tar.gz/refs/tags/${KISSFFT_TAG}" -o "$WORK_DIR/kissfft.tar.gz"
mkdir -p "$WORK_DIR/kissfft-src"
tar xzf "$WORK_DIR/kissfft.tar.gz" -C "$WORK_DIR/kissfft-src" --strip-components=1

echo "==> Vendorizando KissFFT (só o core complex-to-complex, sem kiss_fftr/backends extras)"
KISSFFT_DST="$VENDOR_DIR/kissfft"
rm -rf "$KISSFFT_DST"
mkdir -p "$KISSFFT_DST"
SRC="$WORK_DIR/kissfft-src"
cp "$SRC/kiss_fft.c" "$SRC/kiss_fft.h" "$SRC/_kiss_fft_guts.h" "$KISSFFT_DST/"
cp "$SRC/COPYING" "$KISSFFT_DST/COPYING.BSD-3-Clause"

echo "==> Pronto. Revise 'git diff' em android/app/src/main/cpp/vendor/ antes de commitar."
