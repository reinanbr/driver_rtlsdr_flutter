/// Mirrors `demod_mode_t` from rtlsdr_shim.h — the numeric values matter
/// (passed directly to `shim_set_demod_mode` via FFI).
enum DemodMode {
  wfm(0, 'Commercial FM', 'WFM'),
  nfm(1, 'Narrowband FM', 'NFM'),
  am(2, 'AM', 'AM');

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

  /// Squelch only makes sense for NFM/AM — commercial broadcast (WFM) doesn't use it.
  bool get supportsSquelch => this != DemodMode.wfm;
}
