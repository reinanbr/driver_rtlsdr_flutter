#!/usr/bin/env bash
# Wrapper de compilador/linker usado via CMAKE_<LANG>_COMPILER_LAUNCHER e
# CMAKE_<LANG>_LINKER_LAUNCHER (ver cpp/CMakeLists.txt).
#
# O snap do Flutter exporta CPLUS_INCLUDE_PATH/LIBRARY_PATH apontando pro
# libstdc++ 9 empacotado nele (usado internamente pro build do target
# desktop Linux) — isso vaza pro processo do Gradle e daí pro ninja/clang do
# build nativo Android, fazendo o clang encontrar headers/libs C++ do
# host Linux incompatíveis em vez do libc++/bionic do NDK (erros bizarros
# tipo "redefinition of 'sigaction'" ou "memset não declarado").
#
# Como esse wrapper roda como um processo FILHO novo a cada invocação do
# ninja, ele pode remover essas variáveis do seu próprio ambiente antes de
# de fato executar o compilador/linker real — diferente de tentar vencer a
# ordem de busca via flags, que vira caça a header poluído sem fim.
unset CPLUS_INCLUDE_PATH C_INCLUDE_PATH CPATH LIBRARY_PATH
exec "$@"
