# rtlsdr_mobile

App Android (Flutter + DSP nativo em C/C++) para dongles RTL-SDR via USB-OTG:
sintonia WFM/NFM/AM, estéreo e RDS em WFM, waterfall, scan automático de
frequências, presets e gravação/exportação de áudio. Ver `docs/native_build.md`
pra detalhes do build nativo (libusb + librtlsdr vendorizados).

## Licença

GPLv2, ou (a seu critério) qualquer versão posterior — ver [`LICENSE`](LICENSE).

O app vincula `librtlsdr` (GPLv2-or-later, vendorizada em
`android/app/src/main/cpp/vendor/librtlsdr/`), o que exige que o app inteiro
seja distribuído sob GPL. `libusb` (LGPL-2.1, `vendor/libusb/`) e KissFFT
(BSD-3-Clause, `vendor/kissfft/`) são compatíveis; ambas mantêm seus próprios
arquivos `COPYING*` nos respectivos diretórios. Oboe (áudio, via Gradle/Prefab)
é Apache-2.0.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
