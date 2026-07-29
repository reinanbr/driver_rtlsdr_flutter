## 0.0.1

- Extração inicial do driver nativo (USB, sintonia, streaming, demodulação
  WFM/NFM/AM com estéreo e RDS, espectro, gravação, ganho/squelch) do app
  `rtl-sdr mobile` como plugin Flutter Android reutilizável.
- Núcleo nativo (C, GPLv2) idêntico ao do app de origem — ver
  `../rtl-sdr mobile/docs/how-it-was-built.md` pra como foi projetado e
  validado contra hardware real.
- API pública Dart: `UsbState`/`UsbChannel` (permissão/attach USB),
  `NativeBindings` (FFI direto pra `rtlsdr_shim.h`), `DemodMode`,
  `ShimStats`, `ShimRdsInfo`.
- `example/` com um app mínimo funcional (permissão → sintonia → streaming
  → estatísticas ao vivo).
