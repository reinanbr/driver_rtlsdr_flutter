import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter/material.dart';

/// Squelch threshold subscreen — only meaningful for NFM/AM (see
/// `DemodMode.supportsSquelch`); a consuming screen decides whether to show
/// this section at all based on that flag.
class SquelchPanel extends StatelessWidget {
  const SquelchPanel({super.key, required this.radio});

  final RadioController radio;

  @override
  Widget build(BuildContext context) {
    final theme = RtlSdrTheme.of(context);
    return ListenableBuilder(
      listenable: radio,
      builder: (context, _) {
        return RtlSdrPanel(
          title: 'SQUELCH',
          icon: Icons.volume_off,
          trailing: Icon(
            radio.squelchOpen ? Icons.mic : Icons.mic_off,
            size: 18,
            color: radio.squelchOpen ? theme.meterSafe : theme.textSecondary,
          ),
          child: Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: theme.accent,
                    thumbColor: theme.accent,
                    inactiveTrackColor: theme.grid,
                  ),
                  child: Slider(
                    value: radio.squelchThresholdDb.clamp(-100.0, 0.0),
                    min: -100,
                    max: 0,
                    label:
                        '${radio.squelchThresholdDb.toStringAsFixed(0)} dBFS',
                    onChanged: radio.setSquelchThresholdDb,
                  ),
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  '${radio.squelchThresholdDb.toStringAsFixed(0)} dB',
                  textAlign: TextAlign.end,
                  style: TextStyle(color: theme.textPrimary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
