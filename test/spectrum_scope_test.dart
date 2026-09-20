import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:driver_rtlsdr/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:driver_rtlsdr/src/spectrum_geometry.dart';

/// A fixed 300x150 host so pixel-fraction math in the tests below has a
/// known width to work against. [SpectrumScope] is fully controlled (owns
/// no frequency state itself), so — like a real consuming app wiring
/// [onFrequencyChanged] back into `radio.frequencyHz` — this harness feeds
/// each reported frequency back into [centerFrequencyHz] via `setState`.
/// That matters for the pan tests below: `WidgetTester.drag` delivers a
/// drag as several incremental move events, and each one computes its delta
/// relative to whatever `centerFrequencyHz` the widget was last built with.
class _Harness extends StatefulWidget {
  const _Harness({
    this.centerFrequencyHz = 100000000,
    this.spanHz = 1000000,
    this.onFrequencyChanged,
  });

  final int centerFrequencyHz;
  final int spanHz;
  final ValueChanged<int>? onFrequencyChanged;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late int _centerFrequencyHz = widget.centerFrequencyHz;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 150,
          child: SpectrumScope(
            spectrum: SpectrumController(FakeRtlSdrDriver()),
            centerFrequencyHz: _centerFrequencyHz,
            spanHz: widget.spanHz,
            onFrequencyChanged: (f) {
              setState(() => _centerFrequencyHz = f);
              widget.onFrequencyChanged?.call(f);
            },
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('tap retunes to the exact frequency under the tap', (
    tester,
  ) async {
    int? tuned;
    await tester.pumpWidget(_Harness(onFrequencyChanged: (f) => tuned = f));

    await tester.tapAt(const Offset(225, 75)); // fraction 0.75 of 300px
    await tester.pump();

    expect(
      tuned,
      frequencyAtFraction(
        centerFrequencyHz: 100000000,
        spanHz: 1000000,
        fraction: 0.75,
      ),
    );
  });

  testWidgets('dragging pans by the drag delta, not the absolute position', (
    tester,
  ) async {
    int? tuned;
    await tester.pumpWidget(_Harness(onFrequencyChanged: (f) => tuned = f));

    // Dragging right "pulls" lower frequencies toward the center, same
    // direction as panning a horizontal list, so the frequency goes down.
    // `WidgetTester.drag` (rather than a raw `startGesture`/`moveBy`) is
    // what actually engages `GestureDetector`'s HorizontalDragGestureRecognizer
    // in a widget test — but (with `touchSlopX` left at its default) it
    // silently eats `kDragSlopDefault` of the requested offset getting the
    // recognizer to accept the gesture, so only the remainder is reported
    // as the delta.
    const dragOffset = 60.0;
    await tester.drag(find.byType(SpectrumScope), const Offset(dragOffset, 0));
    await tester.pump();

    expect(
      tuned,
      100000000 - ((dragOffset - kDragSlopDefault) / 300 * 1000000).round(),
    );
  });

  testWidgets('panning is clamped to minFrequencyHz/maxFrequencyHz', (
    tester,
  ) async {
    int? tuned;
    await tester.pumpWidget(
      _Harness(
        centerFrequencyHz: 30000000,
        spanHz: 1000000,
        onFrequencyChanged: (f) => tuned = f,
      ),
    );

    // A big rightward pan would drive the frequency well below the default
    // 24 MHz R820T/R820T2 floor.
    await tester.drag(find.byType(SpectrumScope), const Offset(5000, 0));
    await tester.pump();

    expect(tuned, RtlSdrFrequencyRange.minHz);
  });
}
