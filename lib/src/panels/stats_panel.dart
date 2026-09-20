import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter/material.dart';

/// Read-only throughput/level statistics subscreen over [RadioController].
class StatsPanel extends StatelessWidget {
  const StatsPanel({super.key, required this.radio});

  final RadioController radio;

  @override
  Widget build(BuildContext context) {
    final theme = RtlSdrTheme.of(context);
    return ListenableBuilder(
      listenable: radio,
      builder: (context, _) {
        return RtlSdrPanel(
          title: 'STATISTICS',
          icon: Icons.bar_chart,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _row(
                theme,
                'IQ throughput',
                '${(radio.bytesPerSecond / 1e6).toStringAsFixed(2)} MB/s',
              ),
              _row(
                theme,
                'Total received',
                '${(radio.iqBytesReceived / 1e6).toStringAsFixed(2)} MB',
              ),
              _row(theme, 'Ring buffer overflow', '${radio.ringOverflowCount}'),
              _row(
                theme,
                'RF level',
                '${radio.rfLevelDbfs.toStringAsFixed(1)} dBFS',
              ),
              _row(
                theme,
                'Audio level',
                '${radio.audioLevelDbfs.toStringAsFixed(1)} dBFS',
              ),
              if (radio.lastError != null) ...[
                const SizedBox(height: 8),
                Text(radio.lastError!, style: TextStyle(color: theme.meterHot)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _row(RtlSdrThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: theme.textSecondary)),
          Text(
            value,
            style: TextStyle(
              color: theme.textPrimary,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
