import 'package:flutter/material.dart';

import '../theme/rtlsdr_theme.dart';

/// Themed section container used by every panel in this package (and a
/// good default for a consuming app's own custom subscreens) — a dark
/// surface card with an optional icon + title header, instead of Material's
/// default light `Card`.
class RtlSdrPanel extends StatelessWidget {
  const RtlSdrPanel({
    super.key,
    this.title,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
    required this.child,
  });

  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = RtlSdrTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.grid),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: theme.textSecondary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title!,
                    style: TextStyle(
                      color: theme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}
