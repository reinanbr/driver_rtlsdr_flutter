import 'package:flutter/material.dart';

import '../navigation/rtlsdr_settings_section.dart';
import '../theme/rtlsdr_theme.dart';

/// How [RtlSdrSettingsScreen] spreads its sections across screen space.
enum RtlSdrSettingsLayout {
  /// [masterDetail] above [masterDetailBreakpoint], [drillDown] below it —
  /// the same responsive rule most two-pane settings UIs use (tablet/
  /// desktop vs. phone).
  auto,

  /// A single list; tapping a section pushes it as its own full-screen
  /// subscreen (via [RtlSdrSettingsSection.pageRoute]). Right for narrow/
  /// phone layouts.
  drillDown,

  /// A section list alongside the selected section's content, both on
  /// screen at once — no navigation needed to see another section. Right
  /// for wide/tablet/desktop layouts.
  masterDetail,
}

/// Adaptive settings screen distributing [sections] either as full-screen
/// subscreens (phone) or as an in-place master-detail split (tablet/
/// desktop) — the "settings can be spread across screens and subscreens"
/// piece of this package. Each [RtlSdrSettingsSection] is just a builder,
/// so the same section list works in both layouts unchanged.
class RtlSdrSettingsScreen extends StatefulWidget {
  const RtlSdrSettingsScreen({
    super.key,
    required this.sections,
    this.layout = RtlSdrSettingsLayout.auto,
    this.masterDetailBreakpoint = 700,
    this.title = 'Settings',
  });

  final List<RtlSdrSettingsSection> sections;
  final RtlSdrSettingsLayout layout;
  final double masterDetailBreakpoint;
  final String title;

  @override
  State<RtlSdrSettingsScreen> createState() => _RtlSdrSettingsScreenState();
}

class _RtlSdrSettingsScreenState extends State<RtlSdrSettingsScreen> {
  late RtlSdrSettingsSection _selected = widget.sections.first;

  @override
  Widget build(BuildContext context) {
    final theme = RtlSdrTheme.of(context);
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.surface,
        foregroundColor: theme.textPrimary,
        title: Text(widget.title),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useMasterDetail = switch (widget.layout) {
              RtlSdrSettingsLayout.masterDetail => true,
              RtlSdrSettingsLayout.drillDown => false,
              RtlSdrSettingsLayout.auto =>
                constraints.maxWidth >= widget.masterDetailBreakpoint,
            };
            return useMasterDetail
                ? _MasterDetail(
                    sections: widget.sections,
                    selected: _selected,
                    onSelect: (s) => setState(() => _selected = s),
                  )
                : _DrillDownList(sections: widget.sections);
          },
        ),
      ),
    );
  }
}

class _DrillDownList extends StatelessWidget {
  const _DrillDownList({required this.sections});

  final List<RtlSdrSettingsSection> sections;

  @override
  Widget build(BuildContext context) {
    final theme = RtlSdrTheme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sections.length,
      separatorBuilder: (context, _) => Divider(height: 1, color: theme.grid),
      itemBuilder: (context, index) {
        final section = sections[index];
        return ListTile(
          leading: Icon(section.icon, color: theme.textSecondary),
          title: Text(
            section.title,
            style: TextStyle(color: theme.textPrimary),
          ),
          trailing: Icon(Icons.chevron_right, color: theme.textSecondary),
          onTap: () => Navigator.of(context).push(section.pageRoute()),
        );
      },
    );
  }
}

class _MasterDetail extends StatelessWidget {
  const _MasterDetail({
    required this.sections,
    required this.selected,
    required this.onSelect,
  });

  final List<RtlSdrSettingsSection> sections;
  final RtlSdrSettingsSection selected;
  final ValueChanged<RtlSdrSettingsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = RtlSdrTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 240,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final section in sections)
                ListTile(
                  selected: section == selected,
                  selectedTileColor: theme.surface,
                  leading: Icon(
                    section.icon,
                    color: section == selected
                        ? theme.accent
                        : theme.textSecondary,
                  ),
                  title: Text(
                    section.title,
                    style: TextStyle(
                      color: section == selected
                          ? theme.accent
                          : theme.textPrimary,
                      fontWeight: section == selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  onTap: () => onSelect(section),
                ),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: theme.grid),
        Expanded(
          child: SingleChildScrollView(
            key: ValueKey(selected.id),
            padding: const EdgeInsets.all(16),
            child: selected.builder(context),
          ),
        ),
      ],
    );
  }
}
