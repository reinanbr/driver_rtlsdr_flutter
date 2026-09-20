import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:driver_rtlsdr/testing.dart';
import 'package:flutter_test/flutter_test.dart';

const _wjfk = Preset(
  name: 'WJFK',
  frequencyHz: 106700000,
  mode: DemodMode.wfm,
  gainAuto: true,
  gainTenthDb: 0,
);

void main() {
  group('Preset', () {
    test('toJson/fromJson round-trip', () {
      final decoded = Preset.fromJson(_wjfk.toJson());
      expect(decoded, _wjfk);
    });

    test('equality is value-based', () {
      const same = Preset(
        name: 'WJFK',
        frequencyHz: 106700000,
        mode: DemodMode.wfm,
        gainAuto: true,
        gainTenthDb: 0,
      );
      expect(same, _wjfk);
      expect(same.hashCode, _wjfk.hashCode);
    });
  });

  group('PresetsController', () {
    test('load reads from the repository', () async {
      final repo = InMemoryPresetsRepository([_wjfk]);
      final presets = PresetsController(repo);
      await presets.load();
      expect(presets.presets, [_wjfk]);
    });

    test('add appends and persists', () async {
      final repo = InMemoryPresetsRepository();
      final presets = PresetsController(repo);
      await presets.add(_wjfk);

      expect(presets.presets, [_wjfk]);
      expect(await repo.load(), [_wjfk]);
    });

    test('remove drops a matching preset and persists', () async {
      final repo = InMemoryPresetsRepository([_wjfk]);
      final presets = PresetsController(repo);
      await presets.load();

      await presets.remove(_wjfk);

      expect(presets.presets, isEmpty);
      expect(await repo.load(), isEmpty);
    });

    test('applyTo tunes frequency/mode and manual gain', () {
      final driver = FakeRtlSdrDriver();
      final radio = RadioController(driver);
      final presets = PresetsController(InMemoryPresetsRepository());
      const preset = Preset(
        name: 'Local NFM',
        frequencyHz: 462562500,
        mode: DemodMode.nfm,
        gainAuto: false,
        gainTenthDb: 280,
      );

      presets.applyTo(radio, preset);

      expect(radio.frequencyHz, 462562500);
      expect(radio.demodMode, DemodMode.nfm);
      expect(radio.gainAuto, isFalse);
      expect(radio.gainTenthDb, 280);
    });

    test('applyTo with gainAuto true sets automatic gain', () {
      final driver = FakeRtlSdrDriver();
      final radio = RadioController(driver);
      radio.setGainTenthDb(197); // start on manual gain
      final presets = PresetsController(InMemoryPresetsRepository());
      const preset = Preset(
        name: 'Commercial FM',
        frequencyHz: 101500000,
        mode: DemodMode.wfm,
        gainAuto: true,
        gainTenthDb: 0,
      );

      presets.applyTo(radio, preset);

      expect(radio.gainAuto, isTrue);
    });
  });
}
