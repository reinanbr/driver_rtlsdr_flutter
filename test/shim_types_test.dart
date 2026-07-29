import 'dart:ffi' as ffi;

import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter_test/flutter_test.dart';

/// Testa o TAMANHO em bytes dos structs FFI espelhados de rtlsdr_shim.h —
/// roda no host (não precisa de Android/dongle: dart:ffi calcula o layout
/// de struct em tempo de compilação/VM, sem carregar nenhuma biblioteca
/// nativa). Não prova que cada CAMPO está no offset certo (dart:ffi não
/// expõe um offsetOf público), mas pega o erro mais comum ao evoluir o
/// struct: esquecer de espelhar um campo novo (ou tipo) dos dois lados —
/// C e Dart ficando com tamanho total diferente é sinal quase certo de
/// alguma coisa fora de sincronia. Os tamanhos abaixo foram calculados à
/// mão a partir do layout esperado com alinhamento natural (mesma regra
/// que Dart e um compilador C usam) — ver comentário em cada teste.
void main() {
  group('Layout dos structs FFI (espelham rtlsdr_shim.h)', () {
    test('ShimStats: 40 bytes', () {
      // uint64(8)@0 + uint32(4)@8 + float(4)@12 + float(4)@16 + int32(4)@20
      // + uint64(8)@24 (realinhado a 8) + int32(4)@32 + float(4)@36 = 40,
      // já múltiplo do alinhamento mais estrito (8).
      expect(ffi.sizeOf<ShimStats>(), 40);
    });

    test('ShimRdsInfo: 100 bytes', () {
      // uint16(2)@0 + uint8(1)@2 + [1 byte de padding] + int32(4)@4 +
      // int32(4)@8 + char[9]@12 (termina em 21) + char[65]@21 (termina em
      // 86) + [2 bytes de padding] + uint32(4)@88 + uint32(4)@92 +
      // int32(4)@96 = 100, já múltiplo do alinhamento mais estrito (4).
      expect(ffi.sizeOf<ShimRdsInfo>(), 100);
    });
  });
}
