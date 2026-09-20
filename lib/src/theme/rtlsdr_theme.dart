import 'package:flutter/material.dart';

import 'rtlsdr_theme_data.dart';

/// Makes an [RtlSdrThemeData] available to every widget in this package
/// below it, the same pattern as [Theme]/[Material] — wrap your app (or
/// just the radio screen) once:
///
/// ```dart
/// RtlSdrTheme(
///   data: RtlSdrThemeData.dark(),
///   child: RtlSdrImmersiveScreen(radio: radio),
/// )
/// ```
///
/// Every widget in this package falls back to [RtlSdrThemeData.dark] when
/// used without an ancestor [RtlSdrTheme], so they also work standalone.
class RtlSdrTheme extends InheritedWidget {
  const RtlSdrTheme({super.key, required this.data, required super.child});

  final RtlSdrThemeData data;

  static RtlSdrThemeData of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<RtlSdrTheme>();
    return theme?.data ?? RtlSdrThemeData.dark();
  }

  @override
  bool updateShouldNotify(RtlSdrTheme oldWidget) => data != oldWidget.data;
}
