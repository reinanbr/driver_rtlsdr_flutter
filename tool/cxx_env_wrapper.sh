#!/usr/bin/env bash
# Compiler/linker wrapper used via CMAKE_<LANG>_COMPILER_LAUNCHER and
# CMAKE_<LANG>_LINKER_LAUNCHER (see cpp/CMakeLists.txt).
#
# The Flutter snap exports CPLUS_INCLUDE_PATH/LIBRARY_PATH pointing at the
# libstdc++ 9 bundled with it (used internally to build the Linux desktop
# target) — this leaks into the Gradle process and from there into the
# native Android build's ninja/clang, making clang find incompatible
# Linux host C++ headers/libs instead of the NDK's libc++/bionic (bizarre
# errors like "redefinition of 'sigaction'" or "memset not declared").
#
# Since this wrapper runs as a brand-new CHILD process on every ninja
# invocation, it can strip these variables from its own environment before
# actually executing the real compiler/linker — unlike trying to beat the
# search order with flags, which turns into an endless chase of polluted
# headers.
unset CPLUS_INCLUDE_PATH C_INCLUDE_PATH CPATH LIBRARY_PATH
exec "$@"
