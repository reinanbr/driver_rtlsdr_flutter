import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:driver_rtlsdr/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:driver_rtlsdr/src/spectrum_geometry.dart';

/// A fixed 300x200 host so pixel-fraction math in the tests below has a
/// known width to work against.
Widget _harness({
  int centerFrequencyHz = 100000000,
  int spanHz = 1000000,
  int? passbandHz,
  int? maxSpanHz,
  int minFrequencyHz = RtlSdrFrequencyRange.minHz,
  int maxFrequencyHz = RtlSdrFrequencyRange.maxHz,
  ValueChanged<int>? onFrequencyChanged,
  ValueChanged<int>? onPassbandChanged,
  ValueChanged<int>? onSpanChanged,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 300,
        height: 200,
        child: SpectrumTuner(
          spectrum: SpectrumController(FakeRtlSdrDriver()),
          centerFrequencyHz: centerFrequencyHz,
          spanHz: spanHz,
          passbandHz: passbandHz,
          maxSpanHz: maxSpanHz,
          minFrequencyHz: minFrequencyHz,
          maxFrequencyHz: maxFrequencyHz,
          onFrequencyChanged: onFrequencyChanged,
          onPassbandChanged: onPassbandChanged,
          onSpanChanged: onSpanChanged,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('tap retunes to the exact frequency under the tap', (
    tester,
  ) async {
    int? tuned;
    await tester.pumpWidget(_harness(onFrequencyChanged: (f) => tuned = f));

    await tester.tapAt(const Offset(225, 100)); // fraction 0.75 of 300px
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

  testWidgets(
    'dragging from the middle pans by the drag delta, does not resize passband',
    (tester) async {
      int? tuned;
      int? passband;
      await tester.pumpWidget(
        _harness(
          passbandHz: 200000,
          onFrequencyChanged: (f) => tuned = f,
          onPassbandChanged: (p) => passband = p,
        ),
      );

      // Center of the widget (150,100) is far from either passband edge
      // (at x=120/180 for a 200kHz band over a 1MHz span) — should tune.
      final gesture = await tester.startGesture(const Offset(150, 100));
      await gesture.moveTo(const Offset(210, 100));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // Panning is relative to the drag delta, not the finger's absolute
      // position — dragging right by 60px (a fifth of the 300px width)
      // "pulls" lower frequencies toward the center, same direction as
      // panning a horizontal list, so the frequency goes *down*.
      expect(tuned, 100000000 - (60 / 300 * 1000000).round());
      expect(passband, isNull);
    },
  );

  testWidgets('a drag under the tune slop still resolves as a tap on release', (
    tester,
  ) async {
    int? tuned;
    await tester.pumpWidget(_harness(onFrequencyChanged: (f) => tuned = f));

    // Real-world finger jitter: moves a few px (well under the 18px tune
    // slop) before lifting — should tune to the release point, not pan.
    final gesture = await tester.startGesture(const Offset(225, 100));
    await gesture.moveTo(const Offset(228, 100));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(
      tuned,
      frequencyAtFraction(
        centerFrequencyHz: 100000000,
        spanHz: 1000000,
        fraction: 228 / 300,
      ),
    );
  });

  testWidgets('dragging a passband edge resizes it, does not retune', (
    tester,
  ) async {
    int? tuned;
    int? passband;
    // 200kHz passband over a 1MHz span, 300px wide -> edges at x=120/180.
    await tester.pumpWidget(
      _harness(
        passbandHz: 200000,
        onFrequencyChanged: (f) => tuned = f,
        onPassbandChanged: (p) => passband = p,
      ),
    );

    final gesture = await tester.startGesture(const Offset(180, 100));
    await gesture.moveTo(const Offset(210, 100));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    // Grabbed the right edge and dragged it out to x=210: new half-width
    // fraction is (210/300 - 0.5) = 0.2, so the new passband is 2*0.2*1MHz.
    expect(passband, 400000);
    expect(tuned, isNull);
  });

  testWidgets('passband resize is clamped between minPassbandHz and spanHz', (
    tester,
  ) async {
    int? passband;
    await tester.pumpWidget(
      _harness(passbandHz: 200000, onPassbandChanged: (p) => passband = p),
    );

    // Drag the right edge (x=180) far past the right side of the widget.
    final gesture = await tester.startGesture(const Offset(180, 100));
    await gesture.moveTo(const Offset(1000, 100));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(passband, 1000000); // clamped to spanHz
  });

  testWidgets('spreading two fingers apart zooms in (smaller span)', (
    tester,
  ) async {
    int? span;
    await tester.pumpWidget(_harness(onSpanChanged: (s) => span = s));

    final g1 = await tester.startGesture(const Offset(140, 100));
    final g2 = await tester.startGesture(const Offset(160, 100));
    await tester.pump();
    await g1.moveTo(const Offset(100, 100));
    await g2.moveTo(const Offset(200, 100));
    await tester.pump();
    await g1.up();
    await g2.up();

    // Base distance 20px -> 100px: scale = 5x -> span = 1MHz / 5 = 200kHz.
    expect(span, 200000);
  });

  testWidgets('pinching two fingers together zooms out up to maxSpanHz', (
    tester,
  ) async {
    int? span;
    await tester.pumpWidget(
      _harness(maxSpanHz: 4000000, onSpanChanged: (s) => span = s),
    );

    final g1 = await tester.startGesture(const Offset(100, 100));
    final g2 = await tester.startGesture(const Offset(200, 100));
    await tester.pump();
    await g1.moveTo(const Offset(140, 100));
    await g2.moveTo(const Offset(160, 100));
    await tester.pump();
    await g1.up();
    await g2.up();

    // Base distance 100px -> 20px: scale = 0.2x -> span = 1MHz / 0.2 = 5MHz,
    // clamped to maxSpanHz (4MHz).
    expect(span, 4000000);
  });

  testWidgets(
    'tap-to-tune is clamped to minFrequencyHz near the low band edge',
    (tester) async {
      int? tuned;
      // Center 30 MHz, 20 MHz span -> left edge would be 20 MHz, below the
      // default 24 MHz R820T/R820T2 floor.
      await tester.pumpWidget(
        _harness(
          centerFrequencyHz: 30000000,
          spanHz: 20000000,
          onFrequencyChanged: (f) => tuned = f,
        ),
      );

      await tester.tapAt(const Offset(0, 100)); // fraction 0.0 -> 20 MHz raw
      await tester.pump();

      expect(tuned, RtlSdrFrequencyRange.minHz);
    },
  );

  testWidgets(
    'tap-to-tune is clamped to maxFrequencyHz near the high band edge',
    (tester) async {
      int? tuned;
      // Center 1760 MHz, 20 MHz span -> right edge would be 1770 MHz, above
      // the default 1766 MHz R820T/R820T2 ceiling.
      await tester.pumpWidget(
        _harness(
          centerFrequencyHz: 1760000000,
          spanHz: 20000000,
          onFrequencyChanged: (f) => tuned = f,
        ),
      );

      await tester.tapAt(const Offset(299, 100)); // fraction ~1.0 -> ~1770 MHz
      await tester.pump();

      expect(tuned, RtlSdrFrequencyRange.maxHz);
    },
  );

  testWidgets('lifting one finger during a pinch resumes single-finger tune', (
    tester,
  ) async {
    int? tuned;
    int? span;
    await tester.pumpWidget(
      _harness(
        onFrequencyChanged: (f) => tuned = f,
        onSpanChanged: (s) => span = s,
      ),
    );

    final g1 = await tester.startGesture(const Offset(140, 100));
    final g2 = await tester.startGesture(const Offset(160, 100));
    await tester.pump();
    await g1.moveTo(const Offset(120, 100));
    await g2.moveTo(const Offset(180, 100));
    await tester.pump();
    expect(span, isNotNull);

    await g2.up();
    await tester.pump();
    await g1.moveTo(const Offset(90, 100));
    await tester.pump();
    await g1.up();

    expect(tuned, isNotNull);
  });
}
