import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../rtlsdr_frequency_range.dart';
import '../theme/rtlsdr_theme.dart';
import '../theme/rtlsdr_theme_data.dart';

/// Big odometer-style frequency display, gqrx's signature tuning control:
/// each digit is its own place value — drag a digit up/down, scroll over it
/// with a mouse, or tap the small up/down arrow above/below it, to change
/// just that place, with carries cascading into its neighbors automatically
/// since it's all done by adding/subtracting from the underlying
/// [frequencyHz] and re-rendering.
///
/// [digitCount] fixes how many decimal digits are shown (10 by default —
/// 1 Hz resolution up to 9.999.999.999 Hz, comfortably above any RTL-SDR
/// tuner range); digits with no significant value yet (leading zeros) are
/// dimmed, exactly like gqrx.
///
/// [minHz]/[maxHz] default to [RtlSdrFrequencyRange]'s R820T/R820T2 bounds,
/// so dragging/scrolling/stepping a digit can never ask the tuner for a
/// frequency it can't lock to — pass a different tuner's range (or `null`
/// to disable clamping) if the host app targets different hardware.
class FrequencyReadout extends StatefulWidget {
  const FrequencyReadout({
    super.key,
    required this.frequencyHz,
    required this.onChanged,
    this.digitCount = 10,
    this.minHz = RtlSdrFrequencyRange.minHz,
    this.maxHz = RtlSdrFrequencyRange.maxHz,
    this.fontSize = 36,
  });

  final int frequencyHz;
  final ValueChanged<int> onChanged;
  final int digitCount;
  final int? minHz;
  final int? maxHz;
  final double fontSize;

  @override
  State<FrequencyReadout> createState() => _FrequencyReadoutState();
}

class _FrequencyReadoutState extends State<FrequencyReadout> {
  late List<double> _dragAccumulator = List.filled(widget.digitCount, 0);
  int? _hoveredDigit;

  static const double _pixelsPerStep = 10;

  @override
  void didUpdateWidget(covariant FrequencyReadout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.digitCount != widget.digitCount) {
      _dragAccumulator = List.filled(widget.digitCount, 0);
    }
  }

  int _placeValue(int digitIndex) {
    final exponent = widget.digitCount - 1 - digitIndex;
    var value = 1;
    for (var i = 0; i < exponent; i++) {
      value *= 10;
    }
    return value;
  }

  void _adjust(int digitIndex, int steps) {
    if (steps == 0) return;
    final delta = steps * _placeValue(digitIndex);
    var next = widget.frequencyHz + delta;
    if (widget.minHz case final min?) {
      next = next < min ? min : next;
    }
    if (widget.maxHz case final max?) {
      next = next > max ? max : next;
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = RtlSdrTheme.of(context);
    final digitChars = widget.frequencyHz
        .clamp(0, _maxRepresentable())
        .toString()
        .padLeft(widget.digitCount, '0')
        .split('');
    final firstSignificant = digitChars.indexWhere((d) => d != '0');
    final significantFrom = firstSignificant == -1
        ? widget.digitCount - 1
        : firstSignificant;

    final children = <Widget>[];
    for (var i = 0; i < widget.digitCount; i++) {
      final fromRight = widget.digitCount - i;
      if (i > 0 && fromRight % 3 == 0) {
        children.add(_Separator(theme: theme, fontSize: widget.fontSize));
      }
      children.add(
        _DigitCell(
          digit: digitChars[i],
          dim: i < significantFrom,
          hovered: _hoveredDigit == i,
          fontSize: widget.fontSize,
          theme: theme,
          onHover: (hovering) =>
              setState(() => _hoveredDigit = hovering ? i : null),
          onDragStart: () => _dragAccumulator[i] = 0,
          onDragUpdate: (dy) {
            _dragAccumulator[i] -= dy;
            final steps = (_dragAccumulator[i] / _pixelsPerStep).truncate();
            if (steps != 0) {
              _dragAccumulator[i] -= steps * _pixelsPerStep;
              _adjust(i, steps);
            }
          },
          onScroll: (steps) => _adjust(i, steps),
          onStepUp: () => _adjust(i, 1),
          onStepDown: () => _adjust(i, -1),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  int _maxRepresentable() {
    var value = 1;
    for (var i = 0; i < widget.digitCount; i++) {
      value *= 10;
    }
    return value - 1;
  }
}

class _DigitCell extends StatelessWidget {
  const _DigitCell({
    required this.digit,
    required this.dim,
    required this.hovered,
    required this.fontSize,
    required this.theme,
    required this.onHover,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onScroll,
    required this.onStepUp,
    required this.onStepDown,
  });

  final String digit;
  final bool dim;
  final bool hovered;
  final double fontSize;
  final RtlSdrThemeData theme;
  final ValueChanged<bool> onHover;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<int> onScroll;
  final VoidCallback onStepUp;
  final VoidCallback onStepDown;

  @override
  Widget build(BuildContext context) {
    final arrowSize = fontSize * 0.5;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          icon: Icons.keyboard_arrow_up,
          size: arrowSize,
          theme: theme,
          onPressed: onStepUp,
        ),
        MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          onEnter: (_) => onHover(true),
          onExit: (_) => onHover(false),
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                onScroll(event.scrollDelta.dy < 0 ? 1 : -1);
              }
            },
            child: GestureDetector(
              onVerticalDragStart: (_) => onDragStart(),
              onVerticalDragUpdate: (details) => onDragUpdate(details.delta.dy),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: hovered
                      ? theme.digitActiveBackground
                      : theme.digitBackground,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  digit,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: dim
                        ? theme.textSecondary.withValues(alpha: 0.35)
                        : theme.digitText,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ),
        ),
        _StepButton(
          icon: Icons.keyboard_arrow_down,
          size: arrowSize,
          theme: theme,
          onPressed: onStepDown,
        ),
      ],
    );
  }
}

/// Small tap target above/below each [_DigitCell] to increment/decrement
/// that digit's place value by one step — an explicit alternative to the
/// drag/scroll gesture, easier to hit precisely on a touchscreen.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.size,
    required this.theme,
    required this.onPressed,
  });

  final IconData icon;
  final double size;
  final RtlSdrThemeData theme;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Icon(icon, size: size, color: theme.textSecondary),
        ),
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator({required this.theme, required this.fontSize});

  final RtlSdrThemeData theme;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Text(
        '.',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: theme.textSecondary,
        ),
      ),
    );
  }
}
