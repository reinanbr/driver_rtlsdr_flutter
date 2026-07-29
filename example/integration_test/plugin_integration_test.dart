// Integration test: runs on a real Android device/emulator (unlike the
// tests in test/, which run on the host). Doesn't need an RTL-SDR dongle
// physically connected — it only proves that libnative_rtlsdr.so compiled,
// linked and loads correctly on this device (right ABI, Oboe/librtlsdr/
// libusb resolved), and that a real round-trip FFI call works. Validation
// against real hardware (opening the dongle, tuning, decoding RDS) was
// done manually — see docs/how-it-was-built.md in the rtl-sdr mobile app
// (this package's sibling) for the results of that validation.
import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('libnative_rtlsdr.so loads and responds to an FFI call', (
    tester,
  ) async {
    // The dlopen alone would already fail here (UnsupportedError/link
    // error) if the .so hadn't been packaged for the device's ABI.
    expect(NativeLibrary.instance, isNotNull);

    // shim_is_open() is safe to call with no dongle connected — it should
    // always return 0 (closed) in this state.
    expect(NativeBindings.shimIsOpen(), 0);
  });
}
