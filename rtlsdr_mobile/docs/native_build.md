# Build nativo (libusb + librtlsdr)

## Licenciamento

- `android/app/src/main/cpp/vendor/libusb/` — libusb 1.0.30, **LGPL-2.1**.
- `android/app/src/main/cpp/vendor/librtlsdr/` — librtlsdr 2.1.0, **GPLv2**
  ("or (at your option) any later version" — ver cabeçalho de `src/librtlsdr.c`).

**Resolvido**: vincular librtlsdr (GPLv2-or-later) ao binário do app cria uma
obra combinada sujeita ao copyleft da GPL. O app inteiro agora é licenciado
como GPLv2-ou-posterior (cobre GPLv2 e GPLv3) — ver `LICENSE` na raiz do
repo e a seção "Licença" do `README.md`. libusb (LGPL-2.1) e KissFFT
(BSD-3-Clause, `vendor/kissfft/`) são compatíveis sem exigir mudança de
licenciamento; Oboe (Apache-2.0, via Gradle/Prefab) idem.

## Como as libs foram vendorizadas

`tool/setup_native_deps.sh` documenta/reproduz o processo: baixa as tags
fixas (`libusb v1.0.30`, `librtlsdr v2.1.0`), copia apenas os arquivos
necessários (lista idêntica à que o próprio libusb usa em
`android/jni/libusb.mk`, e só as fontes da biblioteca do librtlsdr — sem
`rtl_sdr.c`/`rtl_fm.c`/etc., que são ferramentas de linha de comando com
`main()` próprio) e aplica `vendor/librtlsdr_open_fd.patch`.

As fontes já estão commitadas em `vendor/` — só rode o script se precisar
re-vendorizar (upgrade de versão, ou setup em outra máquina caso os
diretórios tenham sido removidos). Requer rede (github.com/codeload.github.com).

## O patch `rtlsdr_open_fd`

librtlsdr upstream só abre dispositivos enumerando via
`libusb_get_device_list()`/`libusb_open()`, o que exige acesso direto a
`/dev/bus/usb/*` — impossível em Android sem root. O patch adiciona
`rtlsdr_open_fd(dev, ctx, devh)`, que reaproveita toda a lógica de
inicialização de `rtlsdr_open()` (claim da interface, reset, init do
baseband, probe do tuner) mas pula a enumeração: recebe um
`libusb_device_handle` já obtido via `libusb_wrap_sys_device()` sobre um fd
que o Android (`UsbManager`/`UsbDeviceConnection`, em Kotlin) já abriu e
autorizou. Esse é o padrão documentado pelo próprio libusb para Android sem
root (`vendor/libusb/android/README` no libusb original).

O patch foi gerado mecanicamente (script, não editado à mão) para preservar
byte-a-byte a lógica de inicialização de tuner (valores de registrador etc.)
e foi validado: reaplicado contra uma cópia pristina do v2.1.0, reproduz
exatamente o arquivo vendorizado, e o resultado compila limpo (`gcc
-fsyntax-only` com libusb-1.0 do sistema, e depois via NDK real).

## Arquitetura FFI + JNI compartilhando um só `.so`

`libnative_rtlsdr.so` é carregada dos dois lados:

- Kotlin (`UsbBridge.kt`) via `System.loadLibrary("native_rtlsdr")`, só
  para o handoff do fd USB (`nativeOpenWithFd`/`nativeClose`, via JNI —
  `jni_bridge.cpp`), porque só o Android consegue obter esse fd.
- Dart (`lib/ffi/native_library.dart`) via
  `DynamicLibrary.open('libnative_rtlsdr.so')`, para tudo mais (sintonia,
  streaming, stats) — chamado direto nas funções `shim_*` de
  `rtlsdr_shim.h`.

Como os dois carregam o mesmo soname no mesmo processo, o linker resolve
para a mesma instância — o estado global `g_state` em `rtlsdr_shim.c` é
efetivamente compartilhado entre as duas pontes.

## Riscos conhecidos (Milestone 2)

- O patch `rtlsdr_open_fd` nunca rodou contra hardware real antes deste
  projeto — validado apenas por compilação. A validação real acontece ao
  testar M2 no dongle do usuário. **Atualizado: validado no hardware real do
  usuário (moto g35 5G) — IQ fluindo a ~2 MB/s com overflow em 0.**
- Pode ser necessário `connection.claimInterface()` do lado Kotlin antes do
  handoff, se `libusb_claim_interface()` sozinho não bastar contra um
  handle `wrap_sys_device` — não deveria ser necessário segundo a
  documentação do libusb, mas é o primeiro lugar a olhar se `shim_open_with_fd`
  falhar com `SHIM_ERR_RTLSDR_INIT_FAILED` no dispositivo real.
- Taxa de amostragem padrão é 1.024 Msps (não a máxima de 2.4/3.2 Msps) —
  mais estável em controladores USB de Android; ajustar depois de observar
  `ring_overflow_count` em uso real.

## Gotcha de build: ambiente poluído pelo snap do Flutter (Milestone 3)

Ao integrar o Oboe (primeiro código C++ real do projeto — `jni_bridge.cpp`
não conta, é simples o bastante pra não expor o problema), o build passou a
falhar com erros bizarros e não-determinísticos: `<memory>`/`<cstring>` do
libc++ do NDK resolvendo pra headers de GCC 9 incompatíveis, ou até o
`find_package(oboe REQUIRED CONFIG)` do CMake deixando de achar o
`oboeConfig.cmake` do Prefab mesmo com o arquivo existindo no disco.

**Causa raiz**: o snap do Flutter (`/snap/flutter/current/env.sh`, fonteado
por `flutter.sh` a cada `flutter run`/`flutter build`) exporta
`CPLUS_INCLUDE_PATH`/`LIBRARY_PATH` apontando pro libstdc++ 9 empacotado
dentro do próprio snap (usado internamente pra compilar o target desktop
Linux). O Gradle repassa o ambiente do processo cliente pra cada build —
mesmo com um daemon já rodando, iniciado com ambiente limpo — então essa
poluição vaza tanto pro `clang++` (compilando `audio_sink_oboe.cpp`, que
inclui `<oboe/Oboe.h>` e por tabela boa parte da STL) quanto pro processo do
próprio `cmake` durante o configure (afetando a resolução do
`find_package`).

**Correções aplicadas**:
1. `tool/cxx_env_wrapper.sh` — remove essas variáveis antes de cada
   invocação real do compilador. Aplicado só como propriedade do target
   `native_rtlsdr` (`C_COMPILER_LAUNCHER`/`CXX_COMPILER_LAUNCHER` em
   `cpp/CMakeLists.txt`), **depois** do `find_package(oboe)` — aplicar isso
   globalmente (antes do `project()`/`find_package()`) faz o
   `find_package(oboe)` parar de encontrar o Prefab, por razões não
   totalmente claras mas reproduzíveis.
2. `tool/build_apk.sh` — para o *primeiro* configure nativo (ou depois de
   `flutter clean`/apagar `android/.cxx`), roda o Gradle direto (sem passar
   pelo wrapper `flutter` do snap) com o ambiente limpo. Isso garante que o
   `cmake`/`find_package` rode limpo pelo menos uma vez; o resultado fica
   cacheado em `android/.cxx/` e builds incrementais subsequentes via
   `flutter run`/`flutter build apk` funcionam normalmente mesmo com o
   ambiente poluído (só reusam o cache, não re-rodam o configure).

**Na prática**: se `flutter run`/`flutter build apk` falhar com erros de
header C++ estranhos ou "`find_package(oboe)` não encontrou
`oboeConfig.cmake`" logo após um `flutter clean` ou remoção de
`android/.cxx`, rode `tool/build_apk.sh` uma vez antes de tentar de novo
pelo `flutter`.
