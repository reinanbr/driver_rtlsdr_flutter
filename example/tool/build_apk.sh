#!/usr/bin/env bash
# Faz o primeiro build (ou um build pós-`flutter clean`) do APK do app de
# exemplo com ambiente limpo — mesmo motivo/mecanismo do
# tool/build_apk.sh do app rtl-sdr mobile (irmão deste pacote): o snap do
# Flutter polui CPLUS_INCLUDE_PATH/LIBRARY_PATH, o que quebra o configure
# nativo (CMake/find_package(oboe) via Prefab) na primeira vez. Depois de
# cacheado em android/app/.cxx/, builds incrementais via `flutter run`/
# `flutter build apk` funcionam normalmente mesmo com o ambiente poluído.
#
# Uso: tool/build_apk.sh [tarefa do Gradle, default assembleDebug]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK="${1:-assembleDebug}"

cd "$ROOT_DIR/android"
env -u CPLUS_INCLUDE_PATH -u LIBRARY_PATH -u C_INCLUDE_PATH -u CPATH \
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ./gradlew "$TASK"
