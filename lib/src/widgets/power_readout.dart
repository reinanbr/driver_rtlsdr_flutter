import 'package:flutter/material.dart';

import '../theme/rtlsdr_theme.dart';

/// Compact numeric readout of the spectrum's current power level — pass
/// `radio.rfLevelDbfs` (the same value [SignalMeter] renders as a bar).
/// Meant to sit right beside [FrequencyReadout] (see
/// [RtlSdrImmersiveScreen]) so the tuned frequency and how strong it's
/// coming in read together at a glance, the same pairing gqrx shows above
/// its spectrum view.
class PowerReadout extends StatelessWidget {
  const PowerReadout({
    super.key,
    required this.valueDb,
    this.unit = 'dBFS',
    this.decimals = 1,
  });

  /// Power level in dB — typically `radio.rfLevelDbfs`.
  final double valueDb;

  /// Unit suffix appended after the number, e.g. `'dBFS'`.
  final String unit;

  /// Decimal places shown, e.g. `1` -> `-42.3`.
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final theme = RtlSdrTheme.of(context);
    return Text(
      '${valueDb.toStringAsFixed(decimals)} $unit',
      style: TextStyle(
        color: theme.textSecondary,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
