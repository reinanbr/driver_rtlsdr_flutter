#include <jni.h>

#include "rtlsdr_shim.h"

/*
 * Minimal JNI bridge: it exists only because USB permission/opening can
 * only be done from Kotlin (android.hardware.usb.UsbManager). Everything
 * else (tuning, streaming, stats) is called by Dart via direct FFI into
 * the shim_* functions — see rtlsdr_shim.h.
 *
 * Uses RegisterNatives in JNI_OnLoad instead of relying on static
 * name-mangling (Java_com_..._DriverRtlsdrPlugin_nativeXxx), which is
 * fragile with the underscore in the package name "driver_rtlsdr"
 * (underscore becomes "_1" in mangling — easy to get wrong by hand).
 *
 * The 3 native functions (nativeOpenWithFd/nativeClose/nativeIsOpen) are
 * declared as `external fun` in DriverRtlsdrPlugin.kt — the class name
 * below (FindClass) has to match that exactly. A mismatch here doesn't
 * cause a compile error (it's a string, not checked at build time) — it
 * causes a native crash at runtime as soon as the app loads the lib
 * (FindClass throws a ClassNotFoundException; any subsequent JNI call
 * without clearing that pending exception becomes a fatal "JNI DETECTED
 * ERROR" in strict JNI mode). This is exactly the bug that showed up when
 * extracting this plugin from the original app (there the class was
 * called UsbBridge) — now covered by the defensive env->ExceptionClear()
 * below, but the name still has to match.
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

    jclass clazz = env->FindClass("com/rtlsdrmobile/driver_rtlsdr/DriverRtlsdrPlugin");
    if (clazz == nullptr) {
        // FindClass failing leaves a PENDING ClassNotFoundException on the
        // env — any subsequent JNI call without clearing it first is fatal
        // in strict JNI mode ("JNI DETECTED ERROR ... NewGlobalRef called
        // with pending exception"), even though the caller (the JVM,
        // processing the return of JNI_OnLoad) has nothing to do with
        // FindClass itself. Clear it here to fail predictably (JNI_ERR, no
        // crash) instead of propagating the pending exception.
        env->ExceptionClear();
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
