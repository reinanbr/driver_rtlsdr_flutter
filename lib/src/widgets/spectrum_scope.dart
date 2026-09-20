import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter/material.dart';

import '../painters/spectrum_painter.dart';
import '../spectrum_geometry.dart';

/// Live FFT view (gqrx's top "Hist" plot) driven directly by a
/// [SpectrumController] — listens to it internally, so just drop this in
/// and it updates itself at the controller's polling rate.
///
/// Drag horizontally to retune: [onFrequencyChanged] receives the
/// frequency under the pointer, computed from [centerFrequencyHz] and
/// [spanHz] (pass `radio.frequencyHz` and `radio.sampleRateHz`), clamped to
/// [minFrequencyHz]/[maxFrequencyHz] (defaulting to [RtlSdrFrequencyRange]'s
/// R820T/R820T2 bounds) so this never reports a frequency the tuner can't
/// lock to. Pass [passbandHz] (see [defaultPassbandHzFor]) to shade the
/// current demod filter's passband around the tuned frequency, the same
/// cue gqrx/CubicSDR both show.
class SpectrumScope extends StatelessWidget {
  const SpectrumScope({
    super.key,
    required this.spectrum,
    required this.centerFrequencyHz,
    required this.spanHz,
    this.passbandHz,
    this.minDb = -100,
    this.maxDb = -10,
    this.minFrequencyHz = RtlSdrFrequencyRange.minHz,
    this.maxFrequencyHz = RtlSdrFrequencyRange.maxHz,
    this.showCursor = true,
    this.showGridLabels = true,
    this.showFrequencyAxis = true,
    this.onFrequencyChanged,
  });

  final SpectrumController spectrum;
  final int centerFrequencyHz;
  final int spanHz;
  final int? passbandHz;
  final double minDb;
  final double maxDb;

  /// Drag-to-tune clamp — [onFrequencyChanged] never reports below this.
  final int minFrequencyHz;

  /// Drag-to-tune clamp — [onFrequencyChanged] never reports above this.
  final int maxFrequencyHz;
  final bool showCursor;
  final bool showGridLabels;
  final bool showFrequencyAxis;
  final ValueChanged<int>? onFrequencyChanged;

  int _frequencyAt(double dx, double width) {
    final frequencyHz = frequencyAtFraction(
      centerFrequencyHz: centerFrequencyHz,
      spanHz: spanHz,
      fraction: dx / width,
    );
    return frequencyHz.clamp(minFrequencyHz, maxFrequencyHz);
  }

  @override
  Widget build(BuildContext context) {
    final theme = RtlSdrTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapUp: onFrequencyChanged == null
              ? null
              : (details) => onFrequencyChanged!(
                  _frequencyAt(details.localPosition.dx, constraints.maxWidth),
                ),
          onHorizontalDragUpdate: onFrequencyChanged == null
              ? null
              : (details) => onFrequencyChanged!(
                  _frequencyAt(details.localPosition.dx, constraints.maxWidth),
                ),
          child: ListenableBuilder(
            listenable: spectrum,
            builder: (context, _) {
              return CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: SpectrumPainter(
                  bins: spectrum.bins,
                  minDb: minDb,
                  maxDb: maxDb,
                  theme: theme,
                  centerFrequencyHz: centerFrequencyHz,
                  spanHz: spanHz,
                  passbandHz: passbandHz,
                  cursorFraction: showCursor ? 0.5 : null,
                  showGridLabels: showGridLabels,
                  showFrequencyAxis: showFrequencyAxis,
                ),
              );
            },
          ),
        );
      },
    );
  }
}
