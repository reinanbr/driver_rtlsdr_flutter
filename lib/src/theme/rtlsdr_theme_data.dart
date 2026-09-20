import 'package:flutter/material.dart';

/// Visual language for every widget in this package: the near-black
/// "receiver bezel" background, the spectrum trace/fill, the grid, and the
/// waterfall colormap — the same visual family as gqrx/SDR# so a screen
/// built from these widgets reads as one immersive instrument, not a stack
/// of generic Material cards.
///
/// Get one via [RtlSdrTheme.of] inside any widget under an [RtlSdrTheme],
/// or construct [RtlSdrThemeData.dark]/[RtlSdrThemeData.light] directly for
/// a one-off widget (e.g. inside a test).
@immutable
class RtlSdrThemeData {
  const RtlSdrThemeData({
    required this.background,
    required this.surface,
    required this.grid,
    required this.gridStrong,
    required this.trace,
    required this.traceFill,
    required this.cursor,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.digitBackground,
    required this.digitActiveBackground,
    required this.digitText,
    required this.meterSafe,
    required this.meterWarning,
    required this.meterHot,
    required this.waterfallColormap,
    this.monospaceFontFamily,
  });

  /// The overall panel/screen background — near-black, so the trace,
  /// waterfall and digit readout are the brightest things on screen.
  final Color background;

  /// Slightly-raised background for cards/panels sitting on [background].
  final Color surface;

  /// Faint grid lines (dB/frequency ticks).
  final Color grid;

  /// Grid lines at meaningful marks (0 dBFS, band edges) — brighter than
  /// [grid].
  final Color gridStrong;

  /// The FFT trace line color.
  final Color trace;

  /// Fill color under the FFT trace (usually [trace] at low opacity).
  final Color traceFill;

  /// The vertical line marking the tuned frequency on the scope/waterfall.
  final Color cursor;

  /// General accent for interactive controls (buttons, active toggles).
  final Color accent;

  final Color textPrimary;
  final Color textSecondary;

  /// Background of an inactive frequency digit cell.
  final Color digitBackground;

  /// Background of the digit cell currently being dragged/scrolled.
  final Color digitActiveBackground;

  final Color digitText;

  /// Signal meter color while comfortably below the squelch/clip zone.
  final Color meterSafe;

  /// Signal meter color in the middle zone (approaching squelch/clip).
  final Color meterWarning;

  /// Signal meter color at the top of the range (near 0 dBFS / clipping).
  final Color meterHot;

  /// Maps a normalized power value (0.0 = noise floor, 1.0 = strongest
  /// signal in view) to a waterfall pixel color. Defaults to a "jet"-style
  /// ramp (dark blue → cyan → green → yellow → red), the same family gqrx
  /// and SDR# use by default.
  final Color Function(double t) waterfallColormap;

  /// Optional monospace font for the frequency readout and numeric labels
  /// (falls back to the platform default monospace when null).
  final String? monospaceFontFamily;

  static const _defaultAccent = Color(0xFF00E5D1);

  factory RtlSdrThemeData.dark() {
    return RtlSdrThemeData(
      background: const Color(0xFF05080A),
      surface: const Color(0xFF0D1418),
      grid: const Color(0x33FFFFFF),
      gridStrong: const Color(0x66FFFFFF),
      trace: const Color(0xFF39FF88),
      traceFill: const Color(0x2639FF88),
      cursor: const Color(0xFFFFC13B),
      accent: _defaultAccent,
      textPrimary: const Color(0xFFECF3F2),
      textSecondary: const Color(0xFF8AA0A0),
      digitBackground: const Color(0xFF10191C),
      digitActiveBackground: const Color(0xFF163634),
      digitText: const Color(0xFF39FF88),
      meterSafe: const Color(0xFF39FF88),
      meterWarning: const Color(0xFFFFC13B),
      meterHot: const Color(0xFFFF4D4D),
      waterfallColormap: defaultWaterfallColormap,
    );
  }

  /// A lighter variant for apps that otherwise run a light theme — still
  /// dark enough that the waterfall/scope keep good contrast (an all-white
  /// spectrum display is unreadable), just less black than [dark].
  factory RtlSdrThemeData.light() {
    return RtlSdrThemeData(
      background: const Color(0xFF1B2426),
      surface: const Color(0xFF25302F),
      grid: const Color(0x33FFFFFF),
      gridStrong: const Color(0x66FFFFFF),
      trace: const Color(0xFF00BFA5),
      traceFill: const Color(0x2600BFA5),
      cursor: const Color(0xFFFFA000),
      accent: const Color(0xFF00897B),
      textPrimary: const Color(0xFFF2F7F6),
      textSecondary: const Color(0xFFB0C4C2),
      digitBackground: const Color(0xFF2A3634),
      digitActiveBackground: const Color(0xFF354442),
      digitText: const Color(0xFFE0F2F1),
      meterSafe: const Color(0xFF00BFA5),
      meterWarning: const Color(0xFFFFA000),
      meterHot: const Color(0xFFE53935),
      waterfallColormap: defaultWaterfallColormap,
    );
  }

  RtlSdrThemeData copyWith({
    Color? background,
    Color? surface,
    Color? grid,
    Color? gridStrong,
    Color? trace,
    Color? traceFill,
    Color? cursor,
    Color? accent,
    Color? textPrimary,
    Color? textSecondary,
    Color? digitBackground,
    Color? digitActiveBackground,
    Color? digitText,
    Color? meterSafe,
    Color? meterWarning,
    Color? meterHot,
    Color Function(double t)? waterfallColormap,
    String? monospaceFontFamily,
  }) {
    return RtlSdrThemeData(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      grid: grid ?? this.grid,
      gridStrong: gridStrong ?? this.gridStrong,
      trace: trace ?? this.trace,
      traceFill: traceFill ?? this.traceFill,
      cursor: cursor ?? this.cursor,
      accent: accent ?? this.accent,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      digitBackground: digitBackground ?? this.digitBackground,
      digitActiveBackground:
          digitActiveBackground ?? this.digitActiveBackground,
      digitText: digitText ?? this.digitText,
      meterSafe: meterSafe ?? this.meterSafe,
      meterWarning: meterWarning ?? this.meterWarning,
      meterHot: meterHot ?? this.meterHot,
      waterfallColormap: waterfallColormap ?? this.waterfallColormap,
      monospaceFontFamily: monospaceFontFamily ?? this.monospaceFontFamily,
    );
  }
}

/// The default "jet-ish" waterfall colormap: dark blue (quiet) → cyan →
/// green → yellow → red (hot), the same ramp family gqrx ships by default.
/// [t] is clamped to `[0, 1]`.
Color defaultWaterfallColormap(double t) {
  final v = t.clamp(0.0, 1.0);
  const stops = <Color>[
    Color(0xFF000020),
    Color(0xFF000090),
    Color(0xFF0060C0),
    Color(0xFF00C0C0),
    Color(0xFF00E000),
    Color(0xFFE0E000),
    Color(0xFFE06000),
    Color(0xFFFF0000),
  ];
  final scaled = v * (stops.length - 1);
  final index = scaled.floor().clamp(0, stops.length - 2);
  final localT = scaled - index;
  return Color.lerp(stops[index], stops[index + 1], localT)!;
}
