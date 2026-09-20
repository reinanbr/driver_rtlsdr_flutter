#!/usr/bin/env bash
# Faz o primeiro build (ou um build pós-`flutter clean`) do APK Android com
# ambiente limpo, contornando `flutter build`/`flutter run` diretamente.
#
# Por quê: o snap do Flutter exporta CPLUS_INCLUDE_PATH/LIBRARY_PATH
# apontando pro libstdc++ 9 empacotado nele (usado internamente pro build do
# target desktop Linux). O Gradle repassa o ambiente do processo cliente pra
# cada build — mesmo com um daemon já rodando — então isso vaza pro `cmake`
# durante o configure nativo e quebra a resolução do Oboe via Prefab
# (find_package(oboe) não acha oboeConfig.cmake). Rodando o Gradle
# diretamente (sem passar pelo wrapper `flutter` do snap) com essas
# variáveis removidas, o configure roda limpo uma vez e fica cacheado em
# android/app/.cxx/ — depois disso, `flutter run`/`flutter build apk`
# funcionam normalmente mesmo com o ambiente poluído (só reusam o cache).
#
# Uso: tool/build_apk.sh [tarefa do Gradle, default assembleDebug]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK="${1:-assembleDebug}"

cd "$ROOT_DIR/android"
# JAVA_HOME explícito: sem passar pelo `flutter` (que normalmente aponta o
# Gradle pro JDK 17 configurado via `flutter config --jdk-dir`), o gradlew
# direto pega o JDK default do sistema, que pode ser incompatível com o AGP.
env -u CPLUS_INCLUDE_PATH -u LIBRARY_PATH -u C_INCLUDE_PATH -u CPATH \
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ./gradlew "$TASK"
