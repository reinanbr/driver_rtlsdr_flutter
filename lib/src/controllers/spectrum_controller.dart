import 'dart:async';

import 'package:flutter/foundation.dart';

import '../driver/rtlsdr_driver.dart';

/// Polls [RtlSdrDriver.getSpectrumDb] at a higher rate than
/// [RadioController]'s general stats (~25fps vs ~2fps) — kept as its own
/// [ChangeNotifier] so a waterfall/spectrum widget can listen to just this
/// and avoid rebuilding the rest of a radio panel every frame.
///
/// Owned by [RadioController] (`radio.spectrumController`) and started/
/// stopped together with streaming, but can also be used standalone.
class SpectrumController extends ChangeNotifier {
  SpectrumController(
    this.driver, {
    this.numBins = 256,
    this.interval = const Duration(milliseconds: 40),
  });

  final RtlSdrDriver driver;
  final int numBins;
  final Duration interval;

  List<double> bins = const [];
  bool hasData = false;

  Timer? _timer;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => refresh());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    hasData = false;
    notifyListeners();
  }

  /// Polls one snapshot immediately, outside the periodic timer.
  void refresh() {
    final values = driver.getSpectrumDb(numBins);
    if (values.isEmpty) return;
    bins = values;
    hasData = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
