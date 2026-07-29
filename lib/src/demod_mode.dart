/// Espelha `demod_mode_t` de rtlsdr_shim.h — os valores numéricos importam
/// (passados direto pra `shim_set_demod_mode` via FFI).
enum DemodMode {
  wfm(0, 'FM comercial', 'WFM'),
  nfm(1, 'FM banda estreita', 'NFM'),
  am(2, 'AM', 'AM');

  const DemodMode(this.nativeValue, this.label, this.shortLabel);

  final int nativeValue;
  final String label;
  final String shortLabel;

  static DemodMode fromNativeValue(int value) {
    return DemodMode.values.firstWhere((m) => m.nativeValue == value, orElse: () => DemodMode.wfm);
  }

  /// Squelch só faz sentido pra NFM/AM — rádio comercial (WFM) não usa.
  bool get supportsSquelch => this != DemodMode.wfm;
}
