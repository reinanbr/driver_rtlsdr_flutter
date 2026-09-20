import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:driver_rtlsdr/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RdsController', () {
    test('refresh copies the RDS snapshot from the driver', () {
      final driver = FakeRtlSdrDriver()
        ..rdsInfo = const RdsInfo(
          syncLocked: true,
          piCode: 0x1234,
          pty: 10,
          tp: true,
          ta: false,
          programService: 'BBC R1',
          radioText: 'Now playing something',
          generation: 3,
        );
      final rds = RdsController(driver);

      rds.refresh();

      expect(rds.info.syncLocked, isTrue);
      expect(rds.info.programService, 'BBC R1');
      expect(rds.info.radioText, 'Now playing something');
    });

    test('setEnabled toggles on success', () {
      final driver = FakeRtlSdrDriver();
      final rds = RdsController(driver);
      rds.setEnabled(false);
      expect(rds.enabled, isFalse);
      expect(driver.rdsEnabled, isFalse);
    });

    test('setEnabled does not change state on failure', () {
      final driver = FakeRtlSdrDriver()..failNextCall = true;
      final rds = RdsController(driver);
      rds.setEnabled(false);
      expect(rds.enabled, isTrue); // unchanged
    });

    test('stop resets to RdsInfo.empty', () {
      final driver = FakeRtlSdrDriver()
        ..rdsInfo = const RdsInfo(
          syncLocked: true,
          piCode: 1,
          pty: 1,
          tp: false,
          ta: false,
          programService: 'X',
          radioText: 'Y',
          generation: 1,
        );
      final rds = RdsController(driver);
      rds.refresh();
      expect(rds.info.syncLocked, isTrue);

      rds.stop();
      expect(rds.info, RdsInfo.empty);
    });

    test('start polls periodically until stop', () async {
      final driver = FakeRtlSdrDriver();
      final rds = RdsController(
        driver,
        interval: const Duration(milliseconds: 5),
      );
      var notifications = 0;
      rds.addListener(() => notifications++);

      rds.start();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      rds.stop();

      expect(notifications, greaterThan(1));
    });
  });
}
