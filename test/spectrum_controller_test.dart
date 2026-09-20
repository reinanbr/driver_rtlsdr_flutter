import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:driver_rtlsdr/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpectrumController', () {
    test('refresh copies bins from the driver and sets hasData', () {
      final driver = FakeRtlSdrDriver()
        ..spectrumDb = List<double>.generate(256, (i) => -100.0 + i);
      final spectrum = SpectrumController(driver);

      expect(spectrum.hasData, isFalse);
      spectrum.refresh();

      expect(spectrum.hasData, isTrue);
      expect(spectrum.bins.length, 256);
      expect(spectrum.bins.first, -100.0);
    });

    test('refresh ignores empty snapshots', () {
      final driver = FakeRtlSdrDriver();
      final spectrum = SpectrumController(driver, numBins: 0);
      spectrum.refresh();
      expect(spectrum.hasData, isFalse);
    });

    test('stop clears hasData', () {
      final driver = FakeRtlSdrDriver();
      final spectrum = SpectrumController(driver);
      spectrum.refresh();
      expect(spectrum.hasData, isTrue);
      spectrum.stop();
      expect(spectrum.hasData, isFalse);
    });

    test('start polls periodically until stop', () async {
      final driver = FakeRtlSdrDriver();
      final spectrum = SpectrumController(
        driver,
        interval: const Duration(milliseconds: 5),
      );
      var notifications = 0;
      spectrum.addListener(() => notifications++);

      spectrum.start();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      spectrum.stop();

      expect(notifications, greaterThan(1));
    });
  });
}
