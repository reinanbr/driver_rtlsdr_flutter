#!/usr/bin/env bash
# Does the first build (or a build right after `flutter clean`) of the
# example app's APK with a clean environment — same reason/mechanism as
# tool/build_apk.sh in the rtl-sdr mobile app (sibling of this package):
# the Flutter snap pollutes CPLUS_INCLUDE_PATH/LIBRARY_PATH, which breaks
# the native configure step (CMake/find_package(oboe) via Prefab) the
# first time. Once cached in android/app/.cxx/, incremental builds via
# `flutter run`/`flutter build apk` work normally even with the polluted
# environment.
#
# Usage: tool/build_apk.sh [Gradle task, default assembleDebug]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK="${1:-assembleDebug}"

cd "$ROOT_DIR/android"
env -u CPLUS_INCLUDE_PATH -u LIBRARY_PATH -u C_INCLUDE_PATH -u CPATH \
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ./gradlew "$TASK"
