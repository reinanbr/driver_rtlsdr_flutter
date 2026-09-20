import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:driver_rtlsdr/driver_rtlsdr.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('renders grouped digits for a tuned frequency', (tester) async {
    await tester.pumpWidget(
      wrap(FrequencyReadout(frequencyHz: 91900000, onChanged: (_) {})),
    );

    // 91900000 padded to 10 digits is "0091900000" — '9' appears twice
    // (the 10-million and 100-thousand places).
    expect(find.text('9'), findsNWidgets(2));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('.'), findsNWidgets(3));
  });

  testWidgets('dragging a digit upward reports an increased frequency', (
    tester,
  ) async {
    int? changed;
    await tester.pumpWidget(
      wrap(
        FrequencyReadout(
          frequencyHz: 91900000,
          onChanged: (hz) => changed = hz,
        ),
      ),
    );

    // Drag the rightmost (1 Hz place) digit upward — a drag-up should
    // increase the value at that place.
    final lastDigit = find.text('0').last;
    await tester.drag(lastDigit, const Offset(0, -40));
    await tester.pumpAndSettle();

    expect(changed, isNotNull);
    expect(changed! > 91900000, isTrue);
  });

  testWidgets('tapping the up-arrow above the last digit steps +1 Hz', (
    tester,
  ) async {
    int? changed;
    await tester.pumpWidget(
      wrap(
        FrequencyReadout(
          frequencyHz: 91900000,
          onChanged: (hz) => changed = hz,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.keyboard_arrow_up).last);
    await tester.pump();

    expect(changed, 91900001);
  });

  testWidgets('tapping the down-arrow below the last digit steps -1 Hz', (
    tester,
  ) async {
    int? changed;
    await tester.pumpWidget(
      wrap(
        FrequencyReadout(
          frequencyHz: 91900000,
          onChanged: (hz) => changed = hz,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down).last);
    await tester.pump();

    expect(changed, 91899999);
  });

  testWidgets(
    'tapping the up-arrow above a leading digit steps by its place value',
    (tester) async {
      int? changed;
      await tester.pumpWidget(
        wrap(
          FrequencyReadout(
            frequencyHz: 91900000,
            onChanged: (hz) => changed = hz,
          ),
        ),
      );

      // First digit is the 1e9 (billions) place.
      await tester.tap(find.byIcon(Icons.keyboard_arrow_up).first);
      await tester.pump();

      expect(changed, 91900000 + 1000000000);
    },
  );

  testWidgets('clamps to minHz/maxHz', (tester) async {
    int? changed;
    await tester.pumpWidget(
      wrap(
        FrequencyReadout(
          frequencyHz: 24000000,
          minHz: 24000000,
          maxHz: 1766000000,
          onChanged: (hz) => changed = hz,
        ),
      ),
    );

    final firstDigit = find.text('0').first;
    await tester.drag(firstDigit, const Offset(0, 400));
    await tester.pumpAndSettle();

    expect(changed, 24000000);
  });

  testWidgets(
    'defaults to the R820T/R820T2 tuning range with no minHz/maxHz set',
    (tester) async {
      int? changed;
      await tester.pumpWidget(
        wrap(
          FrequencyReadout(
            frequencyHz: RtlSdrFrequencyRange.minHz,
            onChanged: (hz) => changed = hz,
          ),
        ),
      );

      final firstDigit = find.text('0').first;
      await tester.drag(firstDigit, const Offset(0, 400));
      await tester.pumpAndSettle();

      expect(changed, RtlSdrFrequencyRange.minHz);
    },
  );
}
