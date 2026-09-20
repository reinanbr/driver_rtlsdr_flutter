import 'preset.dart';
import 'presets_repository.dart';

/// Non-persistent [PresetsRepository] — presets live only for the process
/// lifetime. Useful for tests, and for apps that don't want persistence.
class InMemoryPresetsRepository implements PresetsRepository {
  InMemoryPresetsRepository([List<Preset> initial = const []])
    : _presets = List.of(initial);

  List<Preset> _presets;

  @override
  Future<List<Preset>> load() async => List.of(_presets);

  @override
  Future<void> save(List<Preset> presets) async {
    _presets = List.of(presets);
  }
}
