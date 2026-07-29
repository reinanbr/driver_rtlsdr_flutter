import 'dart:ffi' as ffi;
import 'dart:io';

/// Opens `libnative_rtlsdr.so` — the same library Kotlin loads via
/// `System.loadLibrary("native_rtlsdr")` (`DriverRtlsdrPlugin.kt`). Since
/// both sides run in the same Android process and reference the same
/// soname, the system linker resolves them to the same loaded instance —
/// which is why the global state `g_state` in `rtlsdr_shim.c` is
/// effectively shared between the JNI open (which only Kotlin can do,
/// since it needs the `UsbDeviceConnection`'s fd) and the FFI control done
/// here.
class NativeLibrary {
  NativeLibrary._();

  static final ffi.DynamicLibrary instance = _open();

  static ffi.DynamicLibrary _open() {
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libnative_rtlsdr.so');
    }
    throw UnsupportedError('libnative_rtlsdr.so is only available on Android.');
  }
}
