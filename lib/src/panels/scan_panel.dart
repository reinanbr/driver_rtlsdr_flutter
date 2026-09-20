import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter/material.dart';

/// Band-scan subscreen over [ScanController] — lists hits with quick
/// tune/save-as-preset actions, same as gqrx's bookmark-from-scan flow.
class ScanPanel extends StatelessWidget {
  const ScanPanel({
    super.key,
    required this.radio,
    required this.scan,
    required this.presets,
  });

  final RadioController radio;
  final ScanController scan;
  final PresetsController presets;

  @override
  Widget build(BuildContext context) {
    final theme = RtlSdrTheme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([radio, scan]),
      builder: (context, _) {
        return RtlSdrPanel(
          title: 'BAND SCAN',
          icon: Icons.search,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.accent,
                  foregroundColor: theme.background,
                ),
                onPressed: !radio.isStreaming
                    ? null
                    : scan.isScanning
                    ? scan.stopScan
                    : () => scan.startScan(radio),
                icon: Icon(scan.isScanning ? Icons.stop : Icons.search),
                label: Text(
                  scan.isScanning
                      ? 'Scanning… ${(scan.progress * 100).toStringAsFixed(0)}%'
                      : 'Scan commercial FM band',
                ),
              ),
              if (scan.isScanning) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: scan.progress,
                  color: theme.accent,
                  backgroundColor: theme.grid,
                ),
              ],
              if (scan.lastError != null) ...[
                const SizedBox(height: 8),
                Text(scan.lastError!, style: TextStyle(color: theme.meterHot)),
              ],
              if (scan.results.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final hit in scan.results)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    textColor: theme.textPrimary,
                    title: Text(
                      '${(hit.frequencyHz / 1e6).toStringAsFixed(3)} MHz',
                    ),
                    subtitle: Text(
                      '${hit.rfLevelDbfs.toStringAsFixed(1)} dBFS',
                      style: TextStyle(color: theme.textSecondary),
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          icon: Icon(Icons.tune, color: theme.textSecondary),
                          tooltip: 'Tune',
                          onPressed: () => scan.applyHit(radio, hit),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.star_border,
                            color: theme.textSecondary,
                          ),
                          tooltip: 'Save as preset',
                          onPressed: () => scan.saveHitAsPreset(
                            presets,
                            radio,
                            hit,
                            '${(hit.frequencyHz / 1e6).toStringAsFixed(1)} MHz',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
