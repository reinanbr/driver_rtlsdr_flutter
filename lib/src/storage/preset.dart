import 'package:driver_rtlsdr/driver_rtlsdr.dart' show DemodMode;
import 'package:flutter/foundation.dart';

/// A saved frequency/mode/gain combination, for quick recall.
@immutable
class Preset {
  const Preset({
    required this.name,
    required this.frequencyHz,
    required this.mode,
    required this.gainAuto,
    required this.gainTenthDb,
  });

  final String name;
  final int frequencyHz;
  final DemodMode mode;
  final bool gainAuto;
  final int gainTenthDb;

  Map<String, Object?> toJson() => {
    'name': name,
    'frequencyHz': frequencyHz,
    'mode': mode.nativeValue,
    'gainAuto': gainAuto,
    'gainTenthDb': gainTenthDb,
  };

  factory Preset.fromJson(Map<String, Object?> json) => Preset(
    name: json['name']! as String,
    frequencyHz: json['frequencyHz']! as int,
    mode: DemodMode.fromNativeValue(json['mode']! as int),
    gainAuto: json['gainAuto']! as bool,
    gainTenthDb: json['gainTenthDb']! as int,
  );

  @override
  bool operator ==(Object other) =>
      other is Preset &&
      other.name == name &&
      other.frequencyHz == frequencyHz &&
      other.mode == mode &&
      other.gainAuto == gainAuto &&
      other.gainTenthDb == gainTenthDb;

  @override
  int get hashCode =>
      Object.hash(name, frequencyHz, mode, gainAuto, gainTenthDb);
}
