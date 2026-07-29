// Teste de integração: roda num device/emulador Android de verdade (ao
// contrário dos testes em test/, que rodam no host). Não precisa de um
// dongle RTL-SDR fisicamente conectado — só prova que libnative_rtlsdr.so
// compilou, linkou e carrega corretamente nesse device (ABI certo, Oboe/
// librtlsdr/libusb resolvidos), e que uma chamada FFI real de ida e volta
// funciona. Validação contra hardware de verdade (abrir o dongle, sintonizar,
// decodificar RDS) foi feita manualmente — ver docs/how-it-was-built.md no
// app rtl-sdr mobile (irmão deste pacote) pros resultados dessa validação.
import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('libnative_rtlsdr.so carrega e responde a uma chamada FFI', (tester) async {
    // Só o dlopen já falharia aqui (UnsupportedError/erro de link) se o
    // .so não tivesse sido empacotado pro ABI do device.
    expect(NativeLibrary.instance, isNotNull);

    // shim_is_open() é seguro chamar sem nenhum dongle conectado — deve
    // sempre voltar 0 (fechado) nesse estado.
    expect(NativeBindings.shimIsOpen(), 0);
  });
}
