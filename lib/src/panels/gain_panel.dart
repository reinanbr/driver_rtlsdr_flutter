import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter/material.dart';

/// AGC/manual gain subscreen — a self-contained panel over
/// [RadioController]'s gain state, meant to be dropped into a settings
/// section (see [RtlSdrSettingsSection.gain]) or embedded directly.
class GainPanel extends StatelessWidget {
  const GainPanel({super.key, required this.radio});

  final RadioController radio;

  @override
  Widget build(BuildContext context) {
    final theme = RtlSdrTheme.of(context);
    return ListenableBuilder(
      listenable: radio,
      builder: (context, _) {
        return RtlSdrPanel(
          title: 'GAIN',
          icon: Icons.tune,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Automatic (AGC)',
                    style: TextStyle(color: theme.textPrimary),
                  ),
                  const Spacer(),
                  Switch(
                    value: radio.gainAuto,
                    activeThumbColor: theme.accent,
                    onChanged: radio.setGainAuto,
                  ),
                ],
              ),
              if (!radio.gainAuto) ...[
                const SizedBox(height: 4),
                if (radio.gainList.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No gain steps yet — call radio.refreshGainList() '
                      'once the device is ready.',
                      style: TextStyle(color: theme.textSecondary),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: theme.accent,
                            thumbColor: theme.accent,
                            inactiveTrackColor: theme.grid,
                          ),
                          child: Slider(
                            value: _nearestIndex().toDouble(),
                            min: 0,
                            max: (radio.gainList.length - 1).toDouble(),
                            divisions: radio.gainList.length > 1
                                ? radio.gainList.length - 1
                                : 1,
                            onChanged: (i) =>
                                radio.setGainTenthDb(radio.gainList[i.round()]),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        child: Text(
                          '${(radio.gainTenthDb / 10).toStringAsFixed(1)} dB',
                          textAlign: TextAlign.end,
                          style: TextStyle(color: theme.textPrimary),
                        ),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  int _nearestIndex() {
    var best = 0;
    var bestDiff = 1 << 30;
    for (var i = 0; i < radio.gainList.length; i++) {
      final diff = (radio.gainList[i] - radio.gainTenthDb).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i;
      }
    }
    return best;
  }
}
