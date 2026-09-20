import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter/material.dart';

import '../painters/waterfall_painter.dart';

/// Scrolling spectrogram (gqrx's bottom waterfall) fed by a
/// [SpectrumController] — keeps its own rolling history of
/// [historyRows] past FFT frames and repaints as new ones arrive.
class WaterfallView extends StatefulWidget {
  const WaterfallView({
    super.key,
    required this.spectrum,
    this.historyRows = 120,
    this.minDb = -100,
    this.maxDb = -10,
    this.spanHz,
    this.passbandHz,
    this.showCursor = true,
  });

  final SpectrumController spectrum;

  /// How many past FFT frames to keep on screen — taller widget, more
  /// rows, is the usual tradeoff (each row is one polling interval, so
  /// more rows also means a longer time span visible).
  final int historyRows;
  final double minDb;
  final double maxDb;

  /// Captured bandwidth (pass `radio.sampleRateHz`) — needed to size the
  /// passband overlay; the waterfall is always centered on the tuned
  /// frequency, same as [SpectrumScope].
  final int? spanHz;

  /// Width (Hz) of the shaded passband band, see
  /// [SpectrumScope.passbandHz]/[defaultPassbandHzFor]. Null hides it.
  final int? passbandHz;
  final bool showCursor;

  @override
  State<WaterfallView> createState() => _WaterfallViewState();
}

class _WaterfallViewState extends State<WaterfallView> {
  final List<List<double>> _rows = [];

  @override
  void initState() {
    super.initState();
    widget.spectrum.addListener(_onSpectrumUpdate);
  }

  @override
  void didUpdateWidget(covariant WaterfallView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spectrum != widget.spectrum) {
      oldWidget.spectrum.removeListener(_onSpectrumUpdate);
      widget.spectrum.addListener(_onSpectrumUpdate);
    }
  }

  @override
  void dispose() {
    widget.spectrum.removeListener(_onSpectrumUpdate);
    super.dispose();
  }

  void _onSpectrumUpdate() {
    if (!widget.spectrum.hasData) return;
    setState(() {
      _rows.insert(0, List<double>.from(widget.spectrum.bins));
      if (_rows.length > widget.historyRows) {
        _rows.removeRange(widget.historyRows, _rows.length);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = RtlSdrTheme.of(context);
    final span = widget.spanHz;
    final passband = widget.passbandHz;
    return CustomPaint(
      painter: WaterfallPainter(
        rows: _rows,
        historyRows: widget.historyRows,
        minDb: widget.minDb,
        maxDb: widget.maxDb,
        colormap: theme.waterfallColormap,
        background: theme.background,
        cursorColor: theme.cursor,
        cursorFraction: widget.showCursor ? 0.5 : null,
        passbandFraction: (span != null && passband != null && span > 0)
            ? (passband / span).clamp(0.0, 1.0)
            : null,
      ),
      size: Size.infinite,
    );
  }
}
