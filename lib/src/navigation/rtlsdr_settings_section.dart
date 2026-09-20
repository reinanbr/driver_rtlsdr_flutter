import 'package:flutter/material.dart';

import '../screens/rtlsdr_setting_section_screen.dart';

/// One settings section (Gain, Squelch, Recording, Scan, Presets, …) as a
/// self-contained, navigation-agnostic unit: an id, a label/icon for
/// whatever list/rail shows it, and a [builder] producing the panel
/// content (typically one of this package's `*Panel` widgets, or a host
/// app's own widget).
///
/// This is the seam that lets settings be "distributed" however the host
/// app wants:
/// - embedded in-place in [RtlSdrSettingsScreen]'s master-detail split;
/// - pushed as its own full screen via [RtlSdrSettingSectionScreen] (what
///   [RtlSdrSettingsScreen] does on narrow/phone layouts);
/// - pushed individually by the host app's own router/navigation, calling
///   [RtlSdrSettingsSection.pageRoute] directly — nothing here assumes
///   Navigator 1.0, Navigator 2.0, or any particular routing package.
@immutable
class RtlSdrSettingsSection {
  const RtlSdrSettingsSection({
    required this.id,
    required this.title,
    required this.icon,
    required this.builder,
  });

  final String id;
  final String title;
  final IconData icon;
  final WidgetBuilder builder;

  /// A ready-made [MaterialPageRoute] for this section alone — for a host
  /// app that wants to place each section as its own subscreen anywhere in
  /// its own navigation stack (drawer item, deep link, wizard step, etc.)
  /// instead of going through [RtlSdrSettingsScreen].
  Route<void> pageRoute() {
    return MaterialPageRoute(
      builder: (context) => RtlSdrSettingSectionScreen(section: this),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RtlSdrSettingsSection && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
