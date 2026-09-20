import 'preset.dart';

/// Persists the list of user [Preset]s. [PresetsController] depends on this
/// interface rather than a concrete storage mechanism, so it can be
/// unit-tested with [InMemoryPresetsRepository] and swapped for a different
/// backend (e.g. a database) without touching controller code.
abstract interface class PresetsRepository {
  Future<List<Preset>> load();
  Future<void> save(List<Preset> presets);
}
