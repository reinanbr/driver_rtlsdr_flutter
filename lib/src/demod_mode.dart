/// Mirrors `demod_mode_t` from rtlsdr_shim.h — the numeric values matter
/// (passed directly to `shim_set_demod_mode` via FFI).
enum DemodMode {
  wfm(0, 'Commercial FM', 'WFM'),
  nfm(1, 'Narrowband FM', 'NFM'),
  am(2, 'AM', 'AM'),
  usb(3, 'Upper Sideband', 'USB'),
  lsb(4, 'Lower Sideband', 'LSB');

  const DemodMode(this.nativeValue, this.label, this.shortLabel);

  final int nativeValue;
  final String label;
  final String shortLabel;

  static DemodMode fromNativeValue(int value) {
    return DemodMode.values.firstWhere(
      (m) => m.nativeValue == value,
      orElse: () => DemodMode.wfm,
    );
  }

  /// Squelch only makes sense for NFM/AM/USB/LSB — commercial broadcast
  /// (WFM) doesn't use it.
  bool get supportsSquelch => this != DemodMode.wfm;

  /// Only WFM carries a stereo pilot/RDS — SSB and AM/NFM never do.
  bool get supportsStereoAndRds => this == DemodMode.wfm;
}
