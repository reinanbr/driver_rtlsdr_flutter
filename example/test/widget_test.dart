// Teste de widget básico do app de exemplo — roda no host, sem Android/
// dongle: só verifica que a UI monta e mostra o estado inicial "sem
// dispositivo" sem tentar nenhuma chamada FFI de verdade (NativeBindings só
// é tocado a partir de _TunerDemo, que só aparece quando o status USB vira
// deviceReady — impossível de simular sem uma implementação real do
// MethodChannel/EventChannel, então este teste propositalmente não chega lá).
import 'package:driver_rtlsdr_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mostra o estado inicial sem dispositivo USB', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();

    expect(find.text('driver_rtlsdr example'), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) => widget is Text && (widget.data ?? '').startsWith('Status:')),
      findsOneWidget,
    );
  });
}
