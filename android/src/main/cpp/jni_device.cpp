#include <jni.h>
#include <cstdint>
#include "CCapsuleAPI.h"

// ─── Error helper (defined in jni_device_locator.cpp) ─────────────────────────

extern void throw_sdk_error(JNIEnv* env, const clCError* error);

// ─── JNI functions ────────────────────────────────────────────────────────────

extern "C" {

// ── Lifecycle ─────────────────────────────────────────────────────────────────

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeConnectDevice(
    JNIEnv* env, jobject, jlong handle, jboolean bipolarChannels)
{
    clCDevice dev = (clCDevice)(uintptr_t)handle;
    clCError error = {};
    clCDevice_Connect(dev, (bool)bipolarChannels, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
    }
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeDisconnectDevice(
    JNIEnv* env, jobject, jlong handle)
{
    clCDevice dev = (clCDevice)(uintptr_t)handle;
    clCError error = {};
    clCDevice_Disconnect(dev, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
    }
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeStartDevice(
    JNIEnv* env, jobject, jlong handle)
{
    clCDevice dev = (clCDevice)(uintptr_t)handle;
    clCError error = {};
    clCDevice_Start(dev, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
    }
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeStopDevice(
    JNIEnv* env, jobject, jlong handle)
{
    clCDevice dev = (clCDevice)(uintptr_t)handle;
    clCError error = {};
    clCDevice_Stop(dev, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
    }
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeReleaseDevice(
    JNIEnv* /*env*/, jobject, jlong handle)
{
    if (handle == 0) return;
    clCDevice dev = (clCDevice)(uintptr_t)handle;
    clCDevice_Release(dev);
}

// ── Getters ───────────────────────────────────────────────────────────────────

JNIEXPORT jint JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeGetBatteryCharge(
    JNIEnv* env, jobject, jlong handle)
{
    clCDevice dev = (clCDevice)(uintptr_t)handle;
    clCError error = {};
    uint8_t result = clCDevice_GetBatteryCharge(dev, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }
    return (jint)result;
}

JNIEXPORT jint JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeGetMode(
    JNIEnv* /*env*/, jobject, jlong handle)
{
    if (handle == 0) return -1;
    clCDevice dev = (clCDevice)(uintptr_t)handle;
    clCDevice_Mode result = clCDevice_GetMode(dev);
    return (jint)result;
}

JNIEXPORT jfloat JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeGetEEGSampleRate(
    JNIEnv* env, jobject, jlong handle)
{
    clCDevice dev = (clCDevice)(uintptr_t)handle;
    clCError error = {};
    float result = clCDevice_GetEEGSampleRate(dev, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }
    return (jfloat)result;
}

JNIEXPORT jfloat JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeGetPPGSampleRate(
    JNIEnv* env, jobject, jlong handle)
{
    clCDevice dev = (clCDevice)(uintptr_t)handle;
    clCError error = {};
    float result = clCDevice_GetPPGSampleRate(dev, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }
    return (jfloat)result;
}

JNIEXPORT jfloat JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeGetMEMSSampleRate(
    JNIEnv* env, jobject, jlong handle)
{
    clCDevice dev = (clCDevice)(uintptr_t)handle;
    clCError error = {};
    float result = clCDevice_GetMEMSSampleRate(dev, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }
    return (jfloat)result;
}

JNIEXPORT jint JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeGetPPGIrAmplitude(
    JNIEnv* env, jobject, jlong handle)
{
    clCDevice dev = (clCDevice)(uintptr_t)handle;
    clCError error = {};
    int32_t result = clCDevice_GetPPGIrAmplitude(dev, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }
    return (jint)result;
}

JNIEXPORT jint JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeGetPPGRedAmplitude(
    JNIEnv* env, jobject, jlong handle)
{
    clCDevice dev = (clCDevice)(uintptr_t)handle;
    clCError error = {};
    int32_t result = clCDevice_GetPPGRedAmplitude(dev, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }
    return (jint)result;
}

// ── Channel names ─────────────────────────────────────────────────────────────

JNIEXPORT jobject JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeGetChannelNames(
    JNIEnv* env, jobject, jlong deviceHandle)
{
    clCDevice dev = (clCDevice)(uintptr_t)deviceHandle;
    clCError error = {};
    clCDevice_ChannelNames names = clCDevice_GetChannelNames(dev, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return nullptr;
    }

    error = {};
    int32_t count = clCDevice_ChannelNames_GetChannelsCount(names, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return nullptr;
    }

    jclass    alClass = env->FindClass("java/util/ArrayList");
    jmethodID alCtor  = env->GetMethodID(alClass, "<init>", "()V");
    jmethodID alAdd   = env->GetMethodID(alClass, "add", "(Ljava/lang/Object;)Z");
    jobject   result  = env->NewObject(alClass, alCtor);
    env->DeleteLocalRef(alClass);

    for (int32_t i = 0; i < count; ++i) {
        clCError nameError = {};
        const char* name = clCDevice_ChannelNames_GetChannelNameByIndex(names, i, &nameError);
        if (!nameError.success) {
            throw_sdk_error(env, &nameError);
            env->DeleteLocalRef(result);
            return nullptr;
        }
        jstring jName = env->NewStringUTF(name ? name : "");
        env->CallBooleanMethod(result, alAdd, jName);
        env->DeleteLocalRef(jName);
    }

    return result;
}

JNIEXPORT jint JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeGetChannelsCount(
    JNIEnv* env, jobject, jlong deviceHandle)
{
    clCDevice dev = (clCDevice)(uintptr_t)deviceHandle;
    clCError error = {};
    clCDevice_ChannelNames names = clCDevice_GetChannelNames(dev, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }
    error = {};
    int32_t count = clCDevice_ChannelNames_GetChannelsCount(names, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }
    return (jint)count;
}

JNIEXPORT jint JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeGetChannelIndexByName(
    JNIEnv* env, jobject, jlong deviceHandle, jstring channelName)
{
    clCDevice dev = (clCDevice)(uintptr_t)deviceHandle;
    clCError error = {};
    clCDevice_ChannelNames names = clCDevice_GetChannelNames(dev, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }
    const char* nameStr = env->GetStringUTFChars(channelName, nullptr);
    error = {};
    int32_t index = clCDevice_ChannelNames_GetChannelIndexByName(names, nameStr, &error);
    env->ReleaseStringUTFChars(channelName, nameStr);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }
    return (jint)index;
}

JNIEXPORT jstring JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeGetChannelNameByIndex(
    JNIEnv* env, jobject, jlong deviceHandle, jint index)
{
    clCDevice dev = (clCDevice)(uintptr_t)deviceHandle;
    clCError error = {};
    clCDevice_ChannelNames names = clCDevice_GetChannelNames(dev, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return nullptr;
    }
    error = {};
    const char* name = clCDevice_ChannelNames_GetChannelNameByIndex(names, (int32_t)index, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return nullptr;
    }
    return env->NewStringUTF(name ? name : "");
}

JNIEXPORT jlong JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeGetRawChannelNamesHandle(
    JNIEnv* env, jobject, jlong deviceHandle)
{
    clCDevice dev = (clCDevice)(uintptr_t)deviceHandle;
    clCError error = {};
    clCDevice_ChannelNames names = clCDevice_GetChannelNames(dev, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }
    return (jlong)(uintptr_t)names;
}

JNIEXPORT jint JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeGetChannelsCountFromHandle(
    JNIEnv* env, jobject, jlong namesHandle)
{
    clCDevice_ChannelNames names = (clCDevice_ChannelNames)(uintptr_t)namesHandle;
    clCError error = {};
    int32_t count = clCDevice_ChannelNames_GetChannelsCount(names, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }
    return (jint)count;
}

JNIEXPORT jstring JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeGetChannelNameByIndexFromHandle(
    JNIEnv* env, jobject, jlong namesHandle, jint index)
{
    clCDevice_ChannelNames names = (clCDevice_ChannelNames)(uintptr_t)namesHandle;
    clCError error = {};
    const char* name = clCDevice_ChannelNames_GetChannelNameByIndex(names, (int32_t)index, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return nullptr;
    }
    return env->NewStringUTF(name ? name : "");
}

JNIEXPORT jint JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeGetChannelIndexByNameFromHandle(
    JNIEnv* env, jobject, jlong namesHandle, jstring channelName)
{
    clCDevice_ChannelNames names = (clCDevice_ChannelNames)(uintptr_t)namesHandle;
    const char* nameStr = env->GetStringUTFChars(channelName, nullptr);
    clCError error = {};
    int32_t index = clCDevice_ChannelNames_GetChannelIndexByName(names, nameStr, &error);
    env->ReleaseStringUTFChars(channelName, nameStr);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }
    return (jint)index;
}

} // extern "C"
