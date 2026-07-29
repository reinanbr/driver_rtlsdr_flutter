import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NativeLibrary', () {
    test('throws UnsupportedError when opened on a non-Android host', () {
      // The test host is Linux/macOS/Windows, never Android, so touching
      // NativeLibrary.instance must fail fast with a clear error instead
      // of attempting to dlopen a library that doesn't exist here.
      expect(() => NativeLibrary.instance, throwsUnsupportedError);
    });
  });
}
