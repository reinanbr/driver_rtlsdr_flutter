import 'dart:ffi' as ffi;
import 'dart:io';

/// Abre `libnative_rtlsdr.so` — a mesma biblioteca que o Kotlin carrega via
/// `System.loadLibrary("native_rtlsdr")` (`DriverRtlsdrPlugin.kt`). Como os
/// dois lados rodam no mesmo processo Android e referenciam o mesmo soname,
/// o linker do sistema resolve pra mesma instância carregada — por isso o
/// estado global `g_state` em `rtlsdr_shim.c` é efetivamente compartilhado
/// entre a abertura via JNI (que só o Kotlin pode fazer, por precisar do fd
/// da `UsbDeviceConnection`) e o controle via FFI feito aqui.
class NativeLibrary {
  NativeLibrary._();

  static final ffi.DynamicLibrary instance = _open();

  static ffi.DynamicLibrary _open() {
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libnative_rtlsdr.so');
    }
    throw UnsupportedError('libnative_rtlsdr.so só está disponível no Android.');
  }
}
