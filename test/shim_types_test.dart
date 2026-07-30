import 'dart:ffi' as ffi;

import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests the byte SIZE of the FFI structs mirrored from rtlsdr_shim.h —
/// runs on the host (no Android/dongle needed: dart:ffi computes the
/// struct layout at compile/VM time, without loading any native library).
/// Doesn't prove that every FIELD is at the right offset (dart:ffi doesn't
/// expose a public offsetOf), but catches the most common mistake when
/// evolving the struct: forgetting to mirror a new field (or type) on
/// both sides — the C and Dart sides ending up with a different total
/// size is a near-certain sign that something is out of sync. The sizes
/// below were computed by hand from the expected layout with natural
/// alignment (the same rule Dart and a C compiler use) — see the comment
/// on each test.
void main() {
  group('FFI struct layout (mirrors rtlsdr_shim.h)', () {
    test('ShimStats: 48 bytes', () {
      // uint64(8)@0 + uint32(4)@8 + float(4)@12 + float(4)@16 + int32(4)@20
      // + uint64(8)@24 (realigned to 8) + int32(4)@32 + float(4)@36 +
      // uint64(8)@40 (already 8-aligned, no padding needed) = 48, already a
      // multiple of the strictest alignment (8).
      expect(ffi.sizeOf<ShimStats>(), 48);
    });

    test('ShimRdsInfo: 100 bytes', () {
      // uint16(2)@0 + uint8(1)@2 + [1 byte padding] + int32(4)@4 +
      // int32(4)@8 + char[9]@12 (ends at 21) + char[65]@21 (ends at 86) +
      // [2 bytes padding] + uint32(4)@88 + uint32(4)@92 + int32(4)@96 =
      // 100, already a multiple of the strictest alignment (4).
      expect(ffi.sizeOf<ShimRdsInfo>(), 100);
    });
  });
}
