import 'dart:async';

import 'package:flutter/foundation.dart';

import '../driver/rtlsdr_driver.dart';

/// Polls [RtlSdrDriver.getRdsInfo] (PI/PTY/TP/TA/PS/RadioText) — only
/// meaningful when [info]'s `syncLocked` is true (WFM, stereo pilot locked,
/// RDS enabled — see [RadioController.setStereoEnabled]/[setEnabled]).
///
/// Owned by [RadioController] (`radio.rdsController`) and started/stopped
/// together with streaming, but can also be used standalone.
class RdsController extends ChangeNotifier {
  RdsController(
    this.driver, {
    this.interval = const Duration(milliseconds: 500),
  });

  final RtlSdrDriver driver;
  final Duration interval;

  bool _enabled = true;
  bool get enabled => _enabled;

  RdsInfo info = RdsInfo.empty;

  Timer? _timer;

  void setEnabled(bool value) {
    final status = driver.setRdsEnabled(value);
    if (status == 0) {
      _enabled = value;
      notifyListeners();
    }
  }

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => refresh());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    info = RdsInfo.empty;
    notifyListeners();
  }

  /// Polls one snapshot immediately, outside the periodic timer.
  void refresh() {
    info = driver.getRdsInfo();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
