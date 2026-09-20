import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:driver_rtlsdr/driver_rtlsdr.dart';

void main() {
  group('defaultWaterfallColormap', () {
    test('endpoints match the first/last stop', () {
      expect(defaultWaterfallColormap(0), const Color(0xFF000020));
      expect(defaultWaterfallColormap(1), const Color(0xFFFF0000));
    });

    test('clamps out-of-range input instead of throwing', () {
      expect(defaultWaterfallColormap(-5), defaultWaterfallColormap(0));
      expect(defaultWaterfallColormap(5), defaultWaterfallColormap(1));
    });

    test(
      'is monotonically increasing in perceived brightness-ish red channel near the hot end',
      () {
        final mid = defaultWaterfallColormap(0.9);
        final hot = defaultWaterfallColormap(1.0);
        expect(hot.r, greaterThanOrEqualTo(mid.r));
      },
    );
  });

  group('RtlSdrThemeData', () {
    test('dark() and light() both produce distinct, non-null palettes', () {
      final dark = RtlSdrThemeData.dark();
      final light = RtlSdrThemeData.light();
      expect(dark.background, isNot(light.background));
    });

    test('copyWith overrides only the given fields', () {
      final base = RtlSdrThemeData.dark();
      final copy = base.copyWith(accent: const Color(0xFF123456));
      expect(copy.accent, const Color(0xFF123456));
      expect(copy.background, base.background);
    });
  });
}
