import 'dart:ffi' as ffi;

/// Mirrors `shim_stats_t` from rtlsdr_shim.h (layout must match the C side 1:1).
final class ShimStats extends ffi.Struct {
  @ffi.Uint64()
  external int iqBytesReceived;

  @ffi.Uint32()
  external int ringOverflowCount;

  @ffi.Float()
  external double rfLevelDbfs;

  @ffi.Float()
  external double audioLevelDbfs;

  @ffi.Int32()
  external int squelchOpen;

  @ffi.Uint64()
  external int recordingBytesWritten;

  @ffi.Int32()
  external int stereoLocked;

  @ffi.Float()
  external double pilotLevel;
}

/// Mirrors `shim_rds_info_t` from rtlsdr_shim.h (layout must match the C
/// side 1:1 — same field order/types, including implicit alignment
/// padding, which Dart FFI resolves on its own as long as the order matches).
final class ShimRdsInfo extends ffi.Struct {
  @ffi.Uint16()
  external int piCode;

  @ffi.Uint8()
  external int pty;

  @ffi.Int32()
  external int tp;

  @ffi.Int32()
  external int ta;

  @ffi.Array(9)
  external ffi.Array<ffi.Uint8> ps;

  @ffi.Array(65)
  external ffi.Array<ffi.Uint8> radiotext;

  @ffi.Uint32()
  external int generation;

  @ffi.Uint32()
  external int validGroupCount;

  @ffi.Int32()
  external int syncLocked;
}
