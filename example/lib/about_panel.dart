import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter/material.dart';

/// Official "who built this and why" subscreen for the example app — the
/// one piece of content that's specific to this app rather than to
/// `driver_rtlsdr` the package, so it lives here in `example/` instead of
/// in the package itself.
class AboutPanel extends StatelessWidget {
  const AboutPanel({super.key});

  static const _repositoryUrl =
      'https://github.com/reinanbr/driver_rtlsdr_flutter';

  @override
  Widget build(BuildContext context) {
    final theme = RtlSdrTheme.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RtlSdrPanel(
            title: 'ABOUT',
            icon: Icons.info_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'driver_rtlsdr example',
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Official reference app for the driver_rtlsdr package — '
                  'native driver, radio engine and an immersive, '
                  'gqrx-inspired RTL-SDR receiver UI, all built with '
                  'Flutter and merged into one package.',
                  style: TextStyle(color: theme.textSecondary),
                ),
                const SizedBox(height: 16),
                _label(theme, 'Developed by'),
                Text('reinanbr', style: TextStyle(color: theme.textPrimary)),
                const SizedBox(height: 12),
                _label(theme, 'Why this app exists'),
                Text(
                  'A personal, educational project: a hands-on way to learn '
                  'Flutter UI engineering together with RF/DSP fundamentals '
                  '(RTL-SDR tuning, FFT spectrum analysis, FM demodulation) '
                  '— and to publish the result as an open-source Flutter '
                  'package and example app for the wider SDR/Flutter '
                  'community to build on.',
                  style: TextStyle(color: theme.textPrimary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          RtlSdrPanel(
            title: 'PROJECT',
            icon: Icons.link,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label(theme, 'Source & issues'),
                SelectableText(
                  _repositoryUrl,
                  style: TextStyle(color: theme.textPrimary),
                ),
                const SizedBox(height: 12),
                _label(theme, 'License'),
                Text(
                  'GPL-2.0-or-later',
                  style: TextStyle(color: theme.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(RtlSdrThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        text,
        style: TextStyle(
          color: theme.textSecondary,
          fontWeight: FontWeight.w600,
          fontSize: 12,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
