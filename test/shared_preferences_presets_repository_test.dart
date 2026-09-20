import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SharedPreferencesPresetsRepository', () {
    test('load returns empty when nothing was saved', () async {
      const repo = SharedPreferencesPresetsRepository();
      expect(await repo.load(), isEmpty);
    });

    test('save then load round-trips the preset list', () async {
      const repo = SharedPreferencesPresetsRepository();
      const presets = [
        Preset(
          name: 'WJFK',
          frequencyHz: 106700000,
          mode: DemodMode.wfm,
          gainAuto: true,
          gainTenthDb: 0,
        ),
        Preset(
          name: 'PMR ch1',
          frequencyHz: 446006250,
          mode: DemodMode.nfm,
          gainAuto: false,
          gainTenthDb: 280,
        ),
      ];

      await repo.save(presets);
      final loaded = await repo.load();

      expect(loaded, presets);
    });

    test('separate keys do not collide', () async {
      const repoA = SharedPreferencesPresetsRepository(key: 'a');
      const repoB = SharedPreferencesPresetsRepository(key: 'b');
      const preset = Preset(
        name: 'X',
        frequencyHz: 100000000,
        mode: DemodMode.wfm,
        gainAuto: true,
        gainTenthDb: 0,
      );

      await repoA.save([preset]);

      expect(await repoA.load(), [preset]);
      expect(await repoB.load(), isEmpty);
    });
  });
}
