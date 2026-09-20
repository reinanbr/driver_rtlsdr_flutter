import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter/material.dart';

/// Stereo pilot + RDS decode subscreen — only meaningful in WFM.
class StereoRdsPanel extends StatelessWidget {
  const StereoRdsPanel({super.key, required this.radio});

  final RadioController radio;

  @override
  Widget build(BuildContext context) {
    final theme = RtlSdrTheme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([radio, radio.rdsController]),
      builder: (context, _) {
        final rds = radio.rdsController;
        final info = rds.info;
        return RtlSdrPanel(
          title: 'STEREO / RDS',
          icon: Icons.surround_sound,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    radio.stereoLocked ? Icons.surround_sound : Icons.hearing,
                    size: 18,
                    color: radio.stereoLocked
                        ? theme.meterSafe
                        : theme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    radio.stereoLocked ? 'Stereo (locked)' : 'Mono',
                    style: TextStyle(color: theme.textPrimary),
                  ),
                  const Spacer(),
                  Switch(
                    value: radio.stereoEnabled,
                    activeThumbColor: theme.accent,
                    onChanged: radio.setStereoEnabled,
                  ),
                ],
              ),
              const Divider(height: 20),
              Row(
                children: [
                  Icon(
                    info.syncLocked ? Icons.radio : Icons.radio_outlined,
                    size: 18,
                    color: info.syncLocked
                        ? theme.meterSafe
                        : theme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    info.syncLocked ? 'RDS locked' : 'RDS not locked',
                    style: TextStyle(color: theme.textPrimary),
                  ),
                  const Spacer(),
                  Switch(
                    value: rds.enabled,
                    activeThumbColor: theme.accent,
                    onChanged: rds.setEnabled,
                  ),
                ],
              ),
              if (info.syncLocked) ...[
                const SizedBox(height: 8),
                if (info.programService.isNotEmpty)
                  Text(
                    info.programService,
                    style: TextStyle(
                      color: theme.digitText,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                if (info.radioText.isNotEmpty)
                  Text(
                    info.radioText,
                    style: TextStyle(color: theme.textSecondary),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
