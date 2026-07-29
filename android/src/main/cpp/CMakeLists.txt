cmake_minimum_required(VERSION 3.22.1)
project(rtlsdr_mobile_native C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(${CMAKE_CURRENT_SOURCE_DIR}/vendor/libusb.cmake)
include(${CMAKE_CURRENT_SOURCE_DIR}/vendor/librtlsdr.cmake)

# Oboe (AAR via Gradle, exposto ao CMake via Prefab — buildFeatures.prefab
# em android/build.gradle.kts deste plugin). Usado só por audio/audio_sink_oboe.cpp.
find_package(oboe REQUIRED CONFIG)

add_library(native_rtlsdr SHARED
    rtlsdr_shim.c
    jni_bridge.cpp
    dsp/ring_buffer.c
    dsp/fir_decimator.c
    dsp/demod_fm.c
    dsp/demod_am.c
    dsp/spectrum_fft.c
    dsp/wav_writer.c
    dsp/deemphasis.c
    dsp/fm_stereo_pilot.c
    dsp/rds_decoder.c
    vendor/kissfft/kiss_fft.c
    audio/audio_sink_oboe.cpp
)

# Permite #include "dsp/ring_buffer.h" etc. a partir de rtlsdr_shim.c.
target_include_directories(native_rtlsdr PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(native_rtlsdr
    PRIVATE rtlsdr_core
    PRIVATE oboe::oboe
    PRIVATE log
)

# O snap do Flutter exporta CPLUS_INCLUDE_PATH/LIBRARY_PATH apontando pro
# libstdc++ 9 empacotado nele (usado internamente pro build do target
# desktop Linux) — o Gradle repassa o ambiente do processo cliente (`flutter
# build`/`flutter run`, sempre poluído por causa do snap) pra CADA build,
# mesmo com um daemon já rodando iniciado com ambiente limpo. Isso vaza pro
# clang ao compilar audio_sink_oboe.cpp (que inclui <oboe/Oboe.h> e, por
# tabela, <memory>/<cstring>/etc. da STL) — erros bizarros tipo
# "redefinition of 'sigaction'" ou "memset não declarado" — e também afeta o
# PRÓPRIO processo cmake durante o configure, quebrando a resolução do
# find_package(oboe) via Prefab logo acima (por isso o build inicial precisa
# rodar com ambiente limpo — ver tool/build_apk.sh e docs/native_build.md;
# depois de cacheado em .cxx/, builds incrementais via `flutter run`/`flutter
# build` funcionam normalmente mesmo com o ambiente poluído).
# tool/cxx_env_wrapper.sh remove essas variáveis antes de cada invocação
# real do compilador (tentar vencer isso só com ordem de -isystem virou
# caça a header poluído sem fim; e um CMAKE_<LANG>_COMPILER_LAUNCHER global,
# antes do project()/find_package(), também acaba interferindo na resolução
# do find_package acima — por isso aplicado só neste target, depois).
# Nota: este plugin usa android/src/main/cpp (sem o nível extra "app/" que o
# app host tem em android/app/src/main/cpp) — só 4 "../" até a raiz do
# pacote, não 5.
set(RTLSDR_CXX_ENV_WRAPPER "${CMAKE_CURRENT_SOURCE_DIR}/../../../../tool/cxx_env_wrapper.sh")
set_target_properties(native_rtlsdr PROPERTIES
    C_COMPILER_LAUNCHER "${RTLSDR_CXX_ENV_WRAPPER}"
    CXX_COMPILER_LAUNCHER "${RTLSDR_CXX_ENV_WRAPPER}"
)
