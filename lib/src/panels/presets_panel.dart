import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter/material.dart';

/// Saved-station subscreen over [PresetsController].
class PresetsPanel extends StatelessWidget {
  const PresetsPanel({super.key, required this.radio, required this.presets});

  final RadioController radio;
  final PresetsController presets;

  @override
  Widget build(BuildContext context) {
    final theme = RtlSdrTheme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([radio, presets]),
      builder: (context, _) {
        return RtlSdrPanel(
          title: 'PRESETS',
          icon: Icons.star,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.accent,
                  side: BorderSide(color: theme.accent),
                ),
                onPressed: () => _saveCurrent(context),
                icon: const Icon(Icons.add),
                label: const Text('Save current tuning'),
              ),
              const SizedBox(height: 8),
              for (final preset in presets.presets)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  textColor: theme.textPrimary,
                  title: Text(preset.name),
                  subtitle: Text(
                    '${(preset.frequencyHz / 1e6).toStringAsFixed(3)} MHz · '
                    '${preset.mode.shortLabel}',
                    style: TextStyle(color: theme.textSecondary),
                  ),
                  onTap: () => presets.applyTo(radio, preset),
                  trailing: IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: theme.textSecondary,
                    ),
                    tooltip: 'Remove',
                    onPressed: () => presets.remove(preset),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveCurrent(BuildContext context) async {
    final theme = RtlSdrTheme.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NamePresetDialog(
        theme: theme,
        initialName: '${(radio.frequencyHz / 1e6).toStringAsFixed(1)} MHz',
      ),
    );
    if (name == null || name.isEmpty) return;
    await presets.add(
      Preset(
        name: name,
        frequencyHz: radio.frequencyHz,
        mode: radio.demodMode,
        gainAuto: radio.gainAuto,
        gainTenthDb: radio.gainTenthDb,
      ),
    );
  }
}

class _NamePresetDialog extends StatefulWidget {
  const _NamePresetDialog({required this.initialName, required this.theme});

  final String initialName;
  final RtlSdrThemeData theme;

  @override
  State<_NamePresetDialog> createState() => _NamePresetDialogState();
}

class _NamePresetDialogState extends State<_NamePresetDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: widget.theme.surface,
      title: Text(
        'Preset name',
        style: TextStyle(color: widget.theme.textPrimary),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: TextStyle(color: widget.theme.textPrimary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
