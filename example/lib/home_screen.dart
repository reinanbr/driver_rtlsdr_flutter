import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'about_panel.dart';

/// USB permission flow ([UsbStatusBanner]) until the dongle reaches
/// `deviceReady`, then [RtlSdrImmersiveScreen] wired to every controller
/// through [RtlSdrSettingsSection]s — resize this on a tablet (or a
/// foldable) to see settings switch from drill-down subscreens to a
/// side-by-side master-detail split.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _gainListRequested = false;

  @override
  void initState() {
    super.initState();
    // Covers the case where the dongle is already plugged in when the app
    // opens (no ATTACHED intent to catch in that case).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UsbChannel>().refreshConnectedDevices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final usb = context.watch<UsbState>();

    if (usb.status != UsbConnectionStatus.deviceReady) {
      final theme = RtlSdrTheme.of(context);
      return Scaffold(
        backgroundColor: theme.background,
        appBar: AppBar(
          backgroundColor: theme.surface,
          foregroundColor: theme.textPrimary,
          title: const Text('driver_rtlsdr example'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: UsbStatusBanner(
              usb: usb,
              onRequestPermission: () =>
                  context.read<UsbChannel>().requestPermission(),
            ),
          ),
        ),
      );
    }

    if (!_gainListRequested) {
      _gainListRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<RadioController>().refreshGainList();
      });
    }

    final radio = context.watch<RadioController>();
    final recording = context.read<RecordingController>();
    final scan = context.read<ScanController>();
    final presets = context.read<PresetsController>();

    return RtlSdrImmersiveScreen(
      radio: radio,
      settingsSections: _buildSections(radio, recording, scan, presets),
    );
  }

  List<RtlSdrSettingsSection> _buildSections(
    RadioController radio,
    RecordingController recording,
    ScanController scan,
    PresetsController presets,
  ) {
    return [
      RtlSdrSettingsSection(
        id: 'gain',
        title: 'Gain',
        icon: Icons.tune,
        builder: (context) => GainPanel(radio: radio),
      ),
      if (radio.demodMode.supportsSquelch)
        RtlSdrSettingsSection(
          id: 'squelch',
          title: 'Squelch',
          icon: Icons.volume_off,
          builder: (context) => SquelchPanel(radio: radio),
        ),
      if (radio.demodMode.supportsStereoAndRds)
        RtlSdrSettingsSection(
          id: 'stereo_rds',
          title: 'Stereo / RDS',
          icon: Icons.surround_sound,
          builder: (context) => StereoRdsPanel(radio: radio),
        ),
      RtlSdrSettingsSection(
        id: 'recording',
        title: 'Recording',
        icon: Icons.fiber_manual_record,
        builder: (context) =>
            RecordingPanel(radio: radio, recording: recording),
      ),
      RtlSdrSettingsSection(
        id: 'scan',
        title: 'Band scan',
        icon: Icons.search,
        builder: (context) =>
            ScanPanel(radio: radio, scan: scan, presets: presets),
      ),
      RtlSdrSettingsSection(
        id: 'presets',
        title: 'Presets',
        icon: Icons.star,
        builder: (context) => PresetsPanel(radio: radio, presets: presets),
      ),
      RtlSdrSettingsSection(
        id: 'stats',
        title: 'Statistics',
        icon: Icons.bar_chart,
        builder: (context) => StatsPanel(radio: radio),
      ),
      RtlSdrSettingsSection(
        id: 'about',
        title: 'About',
        icon: Icons.info_outline,
        builder: (context) => const AboutPanel(),
      ),
    ];
  }
}
