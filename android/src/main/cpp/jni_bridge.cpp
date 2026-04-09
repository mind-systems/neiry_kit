#include <jni.h>
#include "CCapsuleAPI.h"

extern "C" JNIEXPORT jstring JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeGetVersion(JNIEnv* env, jobject) {
    return env->NewStringUTF(clCCapsule_GetVersionString());
}
