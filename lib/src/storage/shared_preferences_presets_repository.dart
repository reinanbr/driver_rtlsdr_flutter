import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'preset.dart';
import 'presets_repository.dart';

/// Persists the preset list as JSON in a single `shared_preferences` value —
/// a short list of favorites doesn't need a real database.
class SharedPreferencesPresetsRepository implements PresetsRepository {
  const SharedPreferencesPresetsRepository({
    this.key = 'core_rtlsdr_presets_v1',
  });

  final String key;

  @override
  Future<List<Preset>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => Preset.fromJson((e as Map).cast<String, Object?>()))
        .toList();
  }

  @override
  Future<void> save(List<Preset> presets) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(presets.map((p) => p.toJson()).toList());
    await prefs.setString(key, raw);
  }
}
