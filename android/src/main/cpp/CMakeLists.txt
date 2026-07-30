cmake_minimum_required(VERSION 3.22.1)
project(rtlsdr_mobile_native C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(${CMAKE_CURRENT_SOURCE_DIR}/vendor/libusb.cmake)
include(${CMAKE_CURRENT_SOURCE_DIR}/vendor/librtlsdr.cmake)

# Oboe (AAR via Gradle, exposed to CMake via Prefab — buildFeatures.prefab
# in this plugin's android/build.gradle.kts). Used only by audio/audio_sink_oboe.cpp.
find_package(oboe REQUIRED CONFIG)

add_library(native_rtlsdr SHARED
    rtlsdr_shim.c
    jni_bridge.cpp
    dsp/ring_buffer.c
    dsp/fir_decimator.c
    dsp/demod_fm.c
    dsp/demod_am.c
    dsp/demod_ssb.c
    dsp/spectrum_fft.c
    dsp/wav_writer.c
    dsp/iq_writer.c
    dsp/deemphasis.c
    dsp/fm_stereo_pilot.c
    dsp/rds_decoder.c
    vendor/kissfft/kiss_fft.c
    audio/audio_sink_oboe.cpp
)

# Allows #include "dsp/ring_buffer.h" etc. from rtlsdr_shim.c.
target_include_directories(native_rtlsdr PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(native_rtlsdr
    PRIVATE rtlsdr_core
    PRIVATE oboe::oboe
    PRIVATE log
)

# The Flutter snap exports CPLUS_INCLUDE_PATH/LIBRARY_PATH pointing at the
# libstdc++ 9 bundled with it (used internally to build the Linux desktop
# target) — Gradle forwards the client process environment (`flutter
# build`/`flutter run`, always polluted because of the snap) to EVERY
# build, even with a daemon already running that was started with a clean
# environment. This leaks into clang when compiling audio_sink_oboe.cpp
# (which includes <oboe/Oboe.h> and, transitively, <memory>/<cstring>/etc.
# from the STL) — bizarre errors like "redefinition of 'sigaction'" or
# "memset not declared" — and also affects the cmake process ITSELF during
# configure, breaking find_package(oboe) resolution via Prefab just above
# (which is why the initial build needs to run with a clean environment —
# see tool/build_apk.sh and docs/native_build.md; once cached in .cxx/,
# incremental builds via `flutter run`/`flutter build` work normally even
# with the polluted environment).
# tool/cxx_env_wrapper.sh strips these variables before every actual
# compiler invocation (trying to beat this with -isystem ordering alone
# turned into an endless chase of polluted headers; and a global
# CMAKE_<LANG>_COMPILER_LAUNCHER, before project()/find_package(), also
# ends up interfering with the find_package resolution above — hence it's
# applied only to this target, afterward).
# Note: this plugin uses android/src/main/cpp (without the extra "app/"
# level that the host app has under android/app/src/main/cpp) — only 4
# "../" up to the package root, not 5.
set(RTLSDR_CXX_ENV_WRAPPER "${CMAKE_CURRENT_SOURCE_DIR}/../../../../tool/cxx_env_wrapper.sh")
set_target_properties(native_rtlsdr PROPERTIES
    C_COMPILER_LAUNCHER "${RTLSDR_CXX_ENV_WRAPPER}"
    CXX_COMPILER_LAUNCHER "${RTLSDR_CXX_ENV_WRAPPER}"
)
