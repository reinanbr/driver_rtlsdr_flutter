import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter/material.dart';

/// Demodulation mode segmented control (WFM/NFM/AM), styled to sit on the
/// dark immersive background instead of Material's default surface colors.
class ModeSelector extends StatelessWidget {
  const ModeSelector({super.key, required this.radio});

  final RadioController radio;

  @override
  Widget build(BuildContext context) {
    final theme = RtlSdrTheme.of(context);
    return ListenableBuilder(
      listenable: radio,
      builder: (context, _) {
        return SegmentedButton<DemodMode>(
          style: SegmentedButton.styleFrom(
            backgroundColor: theme.surface,
            foregroundColor: theme.textSecondary,
            selectedForegroundColor: theme.background,
            selectedBackgroundColor: theme.accent,
          ),
          segments: [
            for (final mode in DemodMode.values)
              ButtonSegment(value: mode, label: Text(mode.shortLabel)),
          ],
          selected: {radio.demodMode},
          onSelectionChanged: (selection) =>
              radio.setDemodMode(selection.first),
        );
      },
    );
  }
}
