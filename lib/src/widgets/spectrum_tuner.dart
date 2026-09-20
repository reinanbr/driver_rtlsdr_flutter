import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter/material.dart';

import '../painters/spectrum_painter.dart';
import '../spectrum_geometry.dart';

enum _DragTarget { tune, leftEdge, rightEdge }

/// gqrx/CubicSDR-style combined tuner: an FFT scope stacked over a
/// [WaterfallView], driven by one shared gesture surface instead of
/// [SpectrumScope] and [WaterfallView] tuned independently:
///
/// - Tap anywhere to retune exactly there ([onFrequencyChanged]); drag
///   horizontally to pan instead — same feel as panning a horizontal list
///   (drag right "pulls" lower frequencies toward the center) rather than
///   jumping straight to the finger's position, so a sweep can keep panning
///   past the edge of the visible span instead of pinning at it.
/// - Drag either edge of the shaded passband band to resize the demod
///   filter width live ([onPassbandChanged]) — the same grab-the-band
///   gesture gqrx's own combined view supports. Display/interaction hook
///   only: neither `driver_rtlsdr` nor `core_rtlsdr` expose a native
///   filter-bandwidth setter today, so nothing actually captured changes
///   unless the host app wires the callback to something itself.
/// - Pinch with two fingers to zoom the visible span ([onSpanChanged]),
///   clamped to [minSpanHz]/[maxSpanHz].
///
/// Tap/drag-to-tune is clamped to [minFrequencyHz]/[maxFrequencyHz],
/// defaulting to [RtlSdrFrequencyRange]'s R820T/R820T2 bounds, so this
/// widget can never report a frequency the tuner can't lock to even when
/// the visible span (center ± half the span) extends past the edge of the
/// supported range.
///
/// Fully controlled, like [SpectrumScope]/[FrequencyReadout] — owns no
/// frequency/span/passband state itself, only the transient "which gesture
/// is this" bookkeeping for the pointer sequence currently in progress.
class SpectrumTuner extends StatefulWidget {
  const SpectrumTuner({
    super.key,
    required this.spectrum,
    required this.centerFrequencyHz,
    required this.spanHz,
    this.passbandHz,
    this.minDb = -100,
    this.maxDb = -10,
    this.minSpanHz = 20000,
    this.maxSpanHz,
    this.minPassbandHz = 500,
    this.minFrequencyHz = RtlSdrFrequencyRange.minHz,
    this.maxFrequencyHz = RtlSdrFrequencyRange.maxHz,
    this.waterfallHistoryRows = 120,
    this.scopeFlex = 4,
    this.waterfallFlex = 5,
    this.showCursor = true,
    this.showGridLabels = true,
    this.showFrequencyAxis = true,
    this.onFrequencyChanged,
    this.onPassbandChanged,
    this.onSpanChanged,
  });

  final SpectrumController spectrum;
  final int centerFrequencyHz;
  final int spanHz;

  /// Width (Hz) of the shaded passband band, see
  /// [SpectrumScope.passbandHz]/[defaultPassbandHzFor]. Null hides it (and
  /// disables the edge-drag-to-resize gesture).
  final int? passbandHz;
  final double minDb;
  final double maxDb;

  /// Pinch-zoom clamp — the visible span can't be zoomed narrower than this.
  final int minSpanHz;

  /// Pinch-zoom clamp — the visible span can't be zoomed wider than this;
  /// defaults to [spanHz] itself (zoom in freely, never past the actually
  /// captured bandwidth).
  final int? maxSpanHz;

  /// Edge-drag clamp — the passband can't be resized narrower than this.
  final int minPassbandHz;

  /// Tap/drag-to-tune clamp — [onFrequencyChanged] never reports below this.
  final int minFrequencyHz;

  /// Tap/drag-to-tune clamp — [onFrequencyChanged] never reports above this.
  final int maxFrequencyHz;

  final int waterfallHistoryRows;

  /// Relative height of the FFT scope vs. the waterfall below it, as
  /// `Expanded` flex factors.
  final int scopeFlex;
  final int waterfallFlex;

  final bool showCursor;
  final bool showGridLabels;
  final bool showFrequencyAxis;

  final ValueChanged<int>? onFrequencyChanged;
  final ValueChanged<int>? onPassbandChanged;
  final ValueChanged<int>? onSpanChanged;

  @override
  State<SpectrumTuner> createState() => _SpectrumTunerState();
}

class _SpectrumTunerState extends State<SpectrumTuner> {
  // Deliberately raw `Listener` pointer events instead of a `GestureDetector`
  // combining Tap+Scale: `onScaleStart`'s `localFocalPoint` only reflects
  // where the pointer *currently* is once the recognizer wins the gesture
  // arena — which happens after touch-slop is consumed, i.e. already a
  // dozen-plus logical pixels away from where the finger actually went
  // down. That's fine for a coarse "which direction did you drag" gesture,
  // but not for precisely grabbing a ~2px-wide passband edge line — by the
  // time the callback fires, the reported position may already have
  // drifted past the edge's hit-tolerance zone. Tracking pointers directly
  // gets the true down position with no slop delay.
  static const double _edgeHitToleranceLogicalPx = 18;

  /// How far the finger has to move before a touch-down on the tune area
  /// commits to a pan-drag instead of resolving as a tap on release — mirrors
  /// [kTouchSlop], which is what `GestureDetector`'s Tap-vs-Drag arena uses.
  static const double _tuneDragSlopLogicalPx = 18;

  final Map<int, Offset> _pointers = {};
  _DragTarget? _dragTarget;
  Offset? _tuneDownPosition;
  bool _tuneDragging = false;
  double? _zoomBaseDistance;
  int _zoomBaseSpanHz = 0;

  _DragTarget _dragTargetAt(double dx, double width) {
    final passband = widget.passbandHz;
    if (passband != null && widget.spanHz > 0) {
      final widthFraction = (passband / widget.spanHz).clamp(0.0, 1.0);
      final leftX = (0.5 - widthFraction / 2) * width;
      final rightX = (0.5 + widthFraction / 2) * width;
      if ((dx - leftX).abs() <= _edgeHitToleranceLogicalPx) {
        return _DragTarget.leftEdge;
      }
      if ((dx - rightX).abs() <= _edgeHitToleranceLogicalPx) {
        return _DragTarget.rightEdge;
      }
    }
    return _DragTarget.tune;
  }

  void _onPointerDown(PointerDownEvent event, double width) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 1) {
      _dragTarget = _dragTargetAt(event.localPosition.dx, width);
      switch (_dragTarget) {
        case _DragTarget.tune:
          // Don't tune yet — wait for either a pan past the slop (handled
          // in _onPointerMove) or a release within it, which resolves as a
          // tap (_onPointerUp).
          _tuneDownPosition = event.localPosition;
          _tuneDragging = false;
        case _DragTarget.leftEdge:
        case _DragTarget.rightEdge:
          _resizePassbandAt(event.localPosition.dx, width);
        case null:
          break;
      }
    } else if (_pointers.length == 2) {
      _dragTarget = null;
      _tuneDownPosition = null;
      final positions = _pointers.values.toList();
      _zoomBaseDistance = (positions[0].dx - positions[1].dx).abs().clamp(
        1.0,
        double.infinity,
      );
      _zoomBaseSpanHz = widget.spanHz;
    }
  }

  void _onPointerMove(PointerMoveEvent event, double width) {
    if (!_pointers.containsKey(event.pointer)) return;
    final previous = _pointers[event.pointer]!;
    _pointers[event.pointer] = event.localPosition;

    if (_pointers.length >= 2) {
      final positions = _pointers.values.toList();
      final distance = (positions[0].dx - positions[1].dx).abs().clamp(
        1.0,
        double.infinity,
      );
      _zoom(distance / (_zoomBaseDistance ?? distance));
      return;
    }

    switch (_dragTarget) {
      case _DragTarget.tune:
        final down = _tuneDownPosition;
        if (!_tuneDragging) {
          if (down == null ||
              (event.localPosition.dx - down.dx).abs() <
                  _tuneDragSlopLogicalPx) {
            return;
          }
          _tuneDragging = true;
        }
        _panByDelta(event.localPosition.dx - previous.dx, width);
      case _DragTarget.leftEdge:
      case _DragTarget.rightEdge:
        _resizePassbandAt(event.localPosition.dx, width);
      case null:
        break;
    }
  }

  void _onPointerUp(PointerEvent event, double width) {
    final resolvesAsTap = _dragTarget == _DragTarget.tune && !_tuneDragging;
    final tapPosition = _pointers[event.pointer];
    _pointers.remove(event.pointer);
    if (resolvesAsTap && tapPosition != null) {
      _tuneAt(tapPosition.dx, width);
    }
    if (_pointers.length == 1) {
      final remaining = _pointers.values.single;
      _dragTarget = _dragTargetAt(remaining.dx, width);
      _tuneDownPosition = remaining;
      _tuneDragging = false;
    } else if (_pointers.isEmpty) {
      _dragTarget = null;
      _tuneDownPosition = null;
      _tuneDragging = false;
      _zoomBaseDistance = null;
    }
  }

  /// Absolute tap-to-tune: sets the frequency exactly under the finger.
  void _tuneAt(double dx, double width) {
    final onFrequencyChanged = widget.onFrequencyChanged;
    if (onFrequencyChanged == null) return;
    final frequencyHz = frequencyAtFraction(
      centerFrequencyHz: widget.centerFrequencyHz,
      spanHz: widget.spanHz,
      fraction: dx / width,
    );
    onFrequencyChanged(
      frequencyHz.clamp(widget.minFrequencyHz, widget.maxFrequencyHz),
    );
  }

  /// Relative pan-to-tune: advances by the incremental pointer delta since
  /// the last move, not by the finger's absolute position — dragging right
  /// "pulls" lower frequencies toward the center, same direction as panning
  /// a horizontal list, and a continued drag keeps sweeping past the edge
  /// of the visible span instead of pinning there.
  void _panByDelta(double deltaDx, double width) {
    final onFrequencyChanged = widget.onFrequencyChanged;
    if (onFrequencyChanged == null || widget.spanHz == 0) return;
    final deltaHz = (-deltaDx / width * widget.spanHz).round();
    final newFrequencyHz = widget.centerFrequencyHz + deltaHz;
    onFrequencyChanged(
      newFrequencyHz.clamp(widget.minFrequencyHz, widget.maxFrequencyHz),
    );
  }

  void _resizePassbandAt(double dx, double width) {
    final onPassbandChanged = widget.onPassbandChanged;
    if (onPassbandChanged == null) return;
    final halfWidthFraction = ((dx / width) - 0.5).abs();
    final newPassband = (2 * halfWidthFraction * widget.spanHz).round();
    onPassbandChanged(newPassband.clamp(widget.minPassbandHz, widget.spanHz));
  }

  void _zoom(double scale) {
    final onSpanChanged = widget.onSpanChanged;
    if (onSpanChanged == null || scale <= 0) return;
    final maxSpan = widget.maxSpanHz ?? widget.spanHz;
    final newSpan = (_zoomBaseSpanHz / scale).round().clamp(
      widget.minSpanHz,
      maxSpan,
    );
    onSpanChanged(newSpan);
  }

  @override
  Widget build(BuildContext context) {
    final theme = RtlSdrTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Listener(
          onPointerDown: (event) => _onPointerDown(event, width),
          onPointerMove: (event) => _onPointerMove(event, width),
          onPointerUp: (event) => _onPointerUp(event, width),
          onPointerCancel: (event) => _onPointerUp(event, width),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: widget.scopeFlex,
                child: ListenableBuilder(
                  listenable: widget.spectrum,
                  builder: (context, _) {
                    return CustomPaint(
                      size: Size.infinite,
                      painter: SpectrumPainter(
                        bins: widget.spectrum.bins,
                        minDb: widget.minDb,
                        maxDb: widget.maxDb,
                        theme: theme,
                        centerFrequencyHz: widget.centerFrequencyHz,
                        spanHz: widget.spanHz,
                        passbandHz: widget.passbandHz,
                        cursorFraction: widget.showCursor ? 0.5 : null,
                        showGridLabels: widget.showGridLabels,
                        showFrequencyAxis: widget.showFrequencyAxis,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                flex: widget.waterfallFlex,
                child: WaterfallView(
                  spectrum: widget.spectrum,
                  historyRows: widget.waterfallHistoryRows,
                  minDb: widget.minDb,
                  maxDb: widget.maxDb,
                  spanHz: widget.spanHz,
                  passbandHz: widget.passbandHz,
                  showCursor: widget.showCursor,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
