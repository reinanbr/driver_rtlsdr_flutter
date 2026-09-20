import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:driver_rtlsdr/driver_rtlsdr.dart';

void main() {
  List<RtlSdrSettingsSection> sections() => [
    RtlSdrSettingsSection(
      id: 'a',
      title: 'Section A',
      icon: Icons.tune,
      builder: (context) => const Text('Content A'),
    ),
    RtlSdrSettingsSection(
      id: 'b',
      title: 'Section B',
      icon: Icons.search,
      builder: (context) => const Text('Content B'),
    ),
  ];

  testWidgets('narrow window drills down into a full-screen subscreen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: RtlSdrSettingsScreen(sections: sections())),
    );

    // Only the section list is visible — content isn't rendered inline.
    expect(find.text('Section A'), findsOneWidget);
    expect(find.text('Content A'), findsNothing);

    await tester.tap(find.text('Section A'));
    await tester.pumpAndSettle();

    // Pushed as its own subscreen.
    expect(find.text('Content A'), findsOneWidget);
  });

  testWidgets('wide window shows a master-detail split with no navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: RtlSdrSettingsScreen(sections: sections())),
    );

    // Both the section list and the first section's content are visible at
    // once — no push needed.
    expect(find.text('Section A'), findsOneWidget);
    expect(find.text('Content A'), findsOneWidget);

    await tester.tap(find.text('Section B'));
    await tester.pumpAndSettle();

    expect(find.text('Content B'), findsOneWidget);
    expect(find.text('Content A'), findsNothing);
  });
}
