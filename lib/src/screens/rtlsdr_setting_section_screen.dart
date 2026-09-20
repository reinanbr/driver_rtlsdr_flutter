import 'package:flutter/material.dart';

import '../navigation/rtlsdr_settings_section.dart';
import '../theme/rtlsdr_theme.dart';

/// A single [RtlSdrSettingsSection] as its own full screen — the
/// "subscreen" a phone-sized [RtlSdrSettingsScreen] pushes per section, and
/// also usable standalone if a host app wants to route to one section
/// directly (deep link, drawer entry, wizard step).
class RtlSdrSettingSectionScreen extends StatelessWidget {
  const RtlSdrSettingSectionScreen({super.key, required this.section});

  final RtlSdrSettingsSection section;

  @override
  Widget build(BuildContext context) {
    final theme = RtlSdrTheme.of(context);
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.surface,
        foregroundColor: theme.textPrimary,
        title: Text(section.title),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: section.builder(context),
        ),
      ),
    );
  }
}
