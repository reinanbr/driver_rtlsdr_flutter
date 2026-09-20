import 'package:flutter/material.dart';

import '../theme/rtlsdr_theme_data.dart';

/// Paints the FFT trace + fill + dB grid + frequency axis + passband
/// overlay for [SpectrumScope]. Kept separate from the widget so it stays a
/// pure function of its inputs and is easy to golden-test without a
/// controller/timer involved.
class SpectrumPainter extends CustomPainter {
  SpectrumPainter({
    required this.bins,
    required this.minDb,
    required this.maxDb,
    required this.theme,
    this.centerFrequencyHz,
    this.spanHz,
    this.passbandHz,
    this.cursorFraction,
    this.showGridLabels = true,
    this.showFrequencyAxis = true,
  });

  final List<double> bins;
  final double minDb;
  final double maxDb;
  final RtlSdrThemeData theme;

  /// Tuned center frequency and captured bandwidth — needed to label the
  /// bottom frequency axis and size the passband overlay. Both null hides
  /// the axis regardless of [showFrequencyAxis].
  final int? centerFrequencyHz;
  final int? spanHz;

  /// Width (Hz) of the shaded "filter passband" band drawn around
  /// [cursorFraction] — the same visual cue gqrx/CubicSDR use to show how
  /// much of the spectrum the current demod mode actually captures. Null
  /// hides it.
  final int? passbandHz;

  /// Horizontal position (0..1) of the tuned-frequency cursor line, or null
  /// to hide it.
  final double? cursorFraction;
  final bool showGridLabels;
  final bool showFrequencyAxis;

  static const double _axisHeight = 18;

  double _plotHeight(Size size) => size.height - (_showAxis ? _axisHeight : 0);

  bool get _showAxis =>
      showFrequencyAxis && centerFrequencyHz != null && spanHz != null;

  double _yFor(double db, double plotHeight) {
    final t = ((db - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);
    return plotHeight - t * plotHeight;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plotHeight = _plotHeight(size);
    final plotSize = Size(size.width, plotHeight);

    canvas.drawRect(Offset.zero & size, Paint()..color = theme.background);

    _paintPassband(canvas, plotSize);
    _paintGrid(canvas, plotSize);

    if (bins.isNotEmpty) {
      _paintTrace(canvas, plotSize);
    }

    if (cursorFraction case final f?) {
      final x = f.clamp(0.0, 1.0) * size.width;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, plotHeight),
        Paint()
          ..color = theme.cursor
          ..strokeWidth = 1.5,
      );
    }

    if (_showAxis) {
      _paintFrequencyAxis(canvas, size, plotHeight);
    }
  }

  void _paintPassband(Canvas canvas, Size plotSize) {
    final passband = passbandHz;
    final span = spanHz;
    final center = cursorFraction;
    if (passband == null || span == null || span <= 0 || center == null) {
      return;
    }
    final widthFraction = (passband / span).clamp(0.0, 1.0);
    final left =
        ((center - widthFraction / 2).clamp(0.0, 1.0)) * plotSize.width;
    final right =
        ((center + widthFraction / 2).clamp(0.0, 1.0)) * plotSize.width;
    if (right <= left) return;

    canvas.drawRect(
      Rect.fromLTRB(left, 0, right, plotSize.height),
      Paint()..color = theme.accent.withValues(alpha: 0.12),
    );
    final edgePaint = Paint()
      ..color = theme.accent.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(left, 0), Offset(left, plotSize.height), edgePaint);
    canvas.drawLine(
      Offset(right, 0),
      Offset(right, plotSize.height),
      edgePaint,
    );
  }

  void _paintGrid(Canvas canvas, Size plotSize) {
    final gridPaint = Paint()
      ..color = theme.grid
      ..strokeWidth = 1;
    const step = 20.0;
    var db = (maxDb / step).floor() * step;
    final textStyle = TextStyle(
      color: theme.textSecondary,
      fontSize: 10,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    while (db >= minDb) {
      final y = _yFor(db, plotSize.height);
      canvas.drawLine(Offset(0, y), Offset(plotSize.width, y), gridPaint);
      if (showGridLabels) {
        final tp = TextPainter(
          text: TextSpan(text: db.toStringAsFixed(0), style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(4, (y - tp.height - 2).clamp(0, plotSize.height)),
        );
      }
      db -= step;
    }
  }

  void _paintTrace(Canvas canvas, Size plotSize) {
    final n = bins.length;
    final dx = plotSize.width / (n - 1).clamp(1, n);

    final linePath = Path();
    for (var i = 0; i < n; i++) {
      final x = i * dx;
      final y = _yFor(bins[i], plotSize.height);
      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
    }

    final fillPath = Path.from(linePath)
      ..lineTo((n - 1) * dx, plotSize.height)
      ..lineTo(0, plotSize.height)
      ..close();

    canvas.drawPath(fillPath, Paint()..color = theme.traceFill);
    canvas.drawPath(
      linePath,
      Paint()
        ..color = theme.trace
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// Bottom frequency ruler (gqrx/CubicSDR both show one under the FFT
  /// plot) — five evenly spaced ticks across [centerFrequencyHz] ±
  /// [spanHz]/2, labeled in MHz.
  void _paintFrequencyAxis(Canvas canvas, Size size, double plotHeight) {
    final center = centerFrequencyHz!;
    final span = spanHz!;
    final startHz = center - span ~/ 2;

    final tickPaint = Paint()
      ..color = theme.gridStrong
      ..strokeWidth = 1;
    final textStyle = TextStyle(
      color: theme.textSecondary,
      fontSize: 10,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    const tickCount = 5;
    for (var i = 0; i <= tickCount; i++) {
      final fraction = i / tickCount;
      final x = fraction * size.width;
      final freqHz = startHz + (span * fraction).round();

      canvas.drawLine(
        Offset(x, plotHeight),
        Offset(x, plotHeight + 4),
        tickPaint,
      );

      final label = (freqHz / 1e6).toStringAsFixed(3);
      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      var dx = x - tp.width / 2;
      dx = dx.clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(dx, plotHeight + 5));
    }
  }

  @override
  bool shouldRepaint(covariant SpectrumPainter oldDelegate) {
    return oldDelegate.bins != bins ||
        oldDelegate.minDb != minDb ||
        oldDelegate.maxDb != maxDb ||
        oldDelegate.theme != theme ||
        oldDelegate.centerFrequencyHz != centerFrequencyHz ||
        oldDelegate.spanHz != spanHz ||
        oldDelegate.passbandHz != passbandHz ||
        oldDelegate.cursorFraction != cursorFraction;
  }
}
