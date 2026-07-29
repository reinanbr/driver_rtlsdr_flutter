#include <jni.h>

#include "rtlsdr_shim.h"

/*
 * Ponte JNI mínima: existe só porque a permissão/abertura USB só pode ser
 * feita a partir do Kotlin (android.hardware.usb.UsbManager). Tudo o mais
 * (sintonia, streaming, stats) é chamado pelo Dart via FFI direto nas
 * funções shim_* — ver rtlsdr_shim.h.
 *
 * Usa RegisterNatives em JNI_OnLoad em vez de depender do name-mangling
 * estático (Java_com_..._UsbBridge_nativeXxx), que fica frágil com o
 * underscore no nome do pacote "driver_rtlsdr" (underscore vira "_1" no
 * mangling — fácil de errar na mão).
 */

namespace {

jint JniOpenWithFd(JNIEnv *env, jobject thiz, jint fd, jint vendorId, jint productId) {
    (void)env;
    (void)thiz;
    return shim_open_with_fd(fd, vendorId, productId);
}

jint JniClose(JNIEnv *env, jobject thiz) {
    (void)env;
    (void)thiz;
    return shim_close();
}

jboolean JniIsOpen(JNIEnv *env, jobject thiz) {
    (void)env;
    (void)thiz;
    return shim_is_open() ? JNI_TRUE : JNI_FALSE;
}

const JNINativeMethod kUsbBridgeMethods[] = {
    {const_cast<char *>("nativeOpenWithFd"), const_cast<char *>("(III)I"), reinterpret_cast<void *>(JniOpenWithFd)},
    {const_cast<char *>("nativeClose"), const_cast<char *>("()I"), reinterpret_cast<void *>(JniClose)},
    {const_cast<char *>("nativeIsOpen"), const_cast<char *>("()Z"), reinterpret_cast<void *>(JniIsOpen)},
};

}  // namespace

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
    (void)reserved;
    JNIEnv *env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6) != JNI_OK) {
        return JNI_ERR;
    }

    jclass clazz = env->FindClass("com/rtlsdrmobile/driver_rtlsdr/UsbBridge");
    if (clazz == nullptr) {
        return JNI_ERR;
    }

    jint result = env->RegisterNatives(
        clazz, kUsbBridgeMethods, static_cast<jint>(sizeof(kUsbBridgeMethods) / sizeof(kUsbBridgeMethods[0])));
    env->DeleteLocalRef(clazz);

    if (result != JNI_OK) {
        return JNI_ERR;
    }

    return JNI_VERSION_1_6;
}
