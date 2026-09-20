import 'package:flutter/foundation.dart';

import '../storage/preset.dart';
import '../storage/presets_repository.dart';
import 'radio_controller.dart';

/// User-managed list of [Preset]s, backed by a [PresetsRepository].
class PresetsController extends ChangeNotifier {
  PresetsController(this._repository);

  final PresetsRepository _repository;
  List<Preset> presets = [];

  Future<void> load() async {
    presets = await _repository.load();
    notifyListeners();
  }

  Future<void> add(Preset preset) async {
    presets = [...presets, preset];
    notifyListeners();
    await _repository.save(presets);
  }

  Future<void> remove(Preset preset) async {
    presets = presets.where((p) => p != preset).toList();
    notifyListeners();
    await _repository.save(presets);
  }

  /// Applies the preset to the radio (tuning, mode, gain).
  void applyTo(RadioController radio, Preset preset) {
    radio.setFrequencyHz(preset.frequencyHz);
    radio.setDemodMode(preset.mode);
    if (preset.gainAuto) {
      radio.setGainAuto(true);
    } else {
      radio.setGainTenthDb(preset.gainTenthDb);
    }
  }
}
