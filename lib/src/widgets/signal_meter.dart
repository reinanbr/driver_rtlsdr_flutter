import 'package:flutter/material.dart';

import '../painters/signal_meter_painter.dart';
import '../theme/rtlsdr_theme.dart';

/// Horizontal dBFS level bar — pass `radio.rfLevelDbfs` or
/// `radio.audioLevelDbfs` directly; this widget doesn't listen to anything
/// itself; wrap it in a `ListenableBuilder`/`AnimatedBuilder` on
/// `RadioController` to update it live (see [RtlSdrImmersiveScreen] for the
/// pattern).
class SignalMeter extends StatelessWidget {
  const SignalMeter({
    super.key,
    required this.valueDb,
    this.minDb = -100,
    this.maxDb = 0,
    this.squelchDb,
    this.height = 14,
  });

  final double valueDb;
  final double minDb;
  final double maxDb;

  /// Optional squelch threshold to draw as a tick mark on the bar.
  final double? squelchDb;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = RtlSdrTheme.of(context);
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: SignalMeterPainter(
          valueDb: valueDb,
          minDb: minDb,
          maxDb: maxDb,
          theme: theme,
          squelchDb: squelchDb,
        ),
      ),
    );
  }
}
