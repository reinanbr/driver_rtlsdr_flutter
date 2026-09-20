import 'package:flutter/material.dart';

import '../theme/rtlsdr_theme_data.dart';

/// Paints [SignalMeter]'s horizontal dBFS bar: a tri-color fill (safe →
/// warning → hot) up to the current level, plus a squelch threshold tick
/// when [squelchDb] is given — the same "meter + squelch tick" gqrx shows
/// above its spectrum view.
class SignalMeterPainter extends CustomPainter {
  SignalMeterPainter({
    required this.valueDb,
    required this.minDb,
    required this.maxDb,
    required this.theme,
    this.squelchDb,
  });

  final double valueDb;
  final double minDb;
  final double maxDb;
  final RtlSdrThemeData theme;
  final double? squelchDb;

  double _fractionFor(double db) =>
      ((db - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(3),
    );
    canvas.drawRRect(track, Paint()..color = theme.surface);

    final fraction = _fractionFor(valueDb);
    if (fraction > 0) {
      final fillRect = Rect.fromLTWH(0, 0, size.width * fraction, size.height);
      canvas.save();
      canvas.clipRRect(track);
      canvas.drawRect(
        fillRect,
        Paint()
          ..shader = LinearGradient(
            colors: [theme.meterSafe, theme.meterWarning, theme.meterHot],
            stops: const [0.0, 0.75, 1.0],
          ).createShader(Offset.zero & size),
      );
      canvas.restore();
    }

    if (squelchDb case final s?) {
      final x = _fractionFor(s) * size.width;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = theme.cursor
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SignalMeterPainter oldDelegate) {
    return oldDelegate.valueDb != valueDb ||
        oldDelegate.minDb != minDb ||
        oldDelegate.maxDb != maxDb ||
        oldDelegate.squelchDb != squelchDb ||
        oldDelegate.theme != theme;
  }
}
