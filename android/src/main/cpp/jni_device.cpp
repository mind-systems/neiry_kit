#include <jni.h>
#include <cstdint>
#include <pthread.h>
#include <cstdio>
#include "CCapsuleAPI.h"

// ─── Error helper (defined in jni_device_locator.cpp) ─────────────────────────

extern void throw_sdk_error(JNIEnv* env, const clCError* error);

// ─── Shared globals from jni_device_locator.cpp ───────────────────────────────

extern JavaVM*   g_jvm;
extern jobject   g_handler;
extern jclass    g_dispatcher_class;
extern jmethodID g_postSuccess;

// ─── Stream type enum ─────────────────────────────────────────────────────────

enum DeviceStream {
    STREAM_EEG = 0,
    STREAM_PSD,
    STREAM_ARTIFACTS,
    STREAM_RESISTANCE,
    STREAM_BATTERY,
    STREAM_ERROR,
    STREAM_CONNECTION_STATUS,
    STREAM_MODE,
    STREAM_COUNT
};

// ─── Device registry ──────────────────────────────────────────────────────────

#define MAX_DEVICES 1

struct DeviceSlot {
    clCDevice device;
    jobject   sinks[STREAM_COUNT];
};

static DeviceSlot      g_device_slots[MAX_DEVICES] = {};
static pthread_mutex_t g_device_mutex = PTHREAD_MUTEX_INITIALIZER;

static int find_device_slot(clCDevice dev) {
    for (int i = 0; i < MAX_DEVICES; ++i) {
        if (g_device_slots[i].device == dev) return i;
    }
    return -1;
}

static int register_device_slot(clCDevice dev) {
    int idx = find_device_slot(dev);
    if (idx >= 0) return idx;
    for (int i = 0; i < MAX_DEVICES; ++i) {
        if (!g_device_slots[i].device) {
            g_device_slots[i].device = dev;
            return i;
        }
    }
    return -1;
}

static void unregister_device_slot(int slot) {
    if (slot < 0 || slot >= MAX_DEVICES) return;
    pthread_mutex_lock(&g_device_mutex);
    g_device_slots[slot].device = nullptr;
    pthread_mutex_unlock(&g_device_mutex);
}

// ─── HashMap / boxing JNI caches ─────────────────────────────────────────────

static jclass    s_hmClass       = nullptr;
static jmethodID s_hmCtor        = nullptr;
static jmethodID s_hmPut         = nullptr;
static jclass    s_intClass      = nullptr;
static jmethodID s_intValueOf    = nullptr;
static jclass    s_longClass     = nullptr;
static jmethodID s_longValueOf   = nullptr;
static jclass    s_floatClass    = nullptr;
static jmethodID s_floatValueOf  = nullptr;
static jclass    s_doubleClass   = nullptr;
static jmethodID s_doubleValueOf = nullptr;
static jclass    s_boolClass     = nullptr;
static jmethodID s_boolValueOf   = nullptr;
static jclass    s_stringClass   = nullptr;

static void init_map_cache(JNIEnv* env) {
    if (s_hmClass) return;
    jclass local;

    local = env->FindClass("java/util/HashMap");
    s_hmClass = (jclass)env->NewGlobalRef(local); env->DeleteLocalRef(local);
    s_hmCtor  = env->GetMethodID(s_hmClass, "<init>", "()V");
    s_hmPut   = env->GetMethodID(s_hmClass, "put",
                    "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");

    local = env->FindClass("java/lang/Integer");
    s_intClass   = (jclass)env->NewGlobalRef(local); env->DeleteLocalRef(local);
    s_intValueOf = env->GetStaticMethodID(s_intClass, "valueOf", "(I)Ljava/lang/Integer;");

    local = env->FindClass("java/lang/Long");
    s_longClass   = (jclass)env->NewGlobalRef(local); env->DeleteLocalRef(local);
    s_longValueOf = env->GetStaticMethodID(s_longClass, "valueOf", "(J)Ljava/lang/Long;");

    local = env->FindClass("java/lang/Float");
    s_floatClass   = (jclass)env->NewGlobalRef(local); env->DeleteLocalRef(local);
    s_floatValueOf = env->GetStaticMethodID(s_floatClass, "valueOf", "(F)Ljava/lang/Float;");

    local = env->FindClass("java/lang/Double");
    s_doubleClass   = (jclass)env->NewGlobalRef(local); env->DeleteLocalRef(local);
    s_doubleValueOf = env->GetStaticMethodID(s_doubleClass, "valueOf", "(D)Ljava/lang/Double;");

    local = env->FindClass("java/lang/Boolean");
    s_boolClass   = (jclass)env->NewGlobalRef(local); env->DeleteLocalRef(local);
    s_boolValueOf = env->GetStaticMethodID(s_boolClass, "valueOf", "(Z)Ljava/lang/Boolean;");

    local = env->FindClass("java/lang/String");
    s_stringClass = (jclass)env->NewGlobalRef(local); env->DeleteLocalRef(local);
}

static jobject make_map(JNIEnv* env) {
    return env->NewObject(s_hmClass, s_hmCtor);
}

static void map_put_int(JNIEnv* env, jobject map, const char* key, jint val) {
    jstring jKey  = env->NewStringUTF(key);
    jobject boxed = env->CallStaticObjectMethod(s_intClass, s_intValueOf, val);
    env->CallObjectMethod(map, s_hmPut, jKey, boxed);
    env->DeleteLocalRef(jKey);
    env->DeleteLocalRef(boxed);
}

static void map_put_long(JNIEnv* env, jobject map, const char* key, jlong val) {
    jstring jKey  = env->NewStringUTF(key);
    jobject boxed = env->CallStaticObjectMethod(s_longClass, s_longValueOf, val);
    env->CallObjectMethod(map, s_hmPut, jKey, boxed);
    env->DeleteLocalRef(jKey);
    env->DeleteLocalRef(boxed);
}

static void map_put_float(JNIEnv* env, jobject map, const char* key, jfloat val) {
    jstring jKey  = env->NewStringUTF(key);
    jobject boxed = env->CallStaticObjectMethod(s_floatClass, s_floatValueOf, val);
    env->CallObjectMethod(map, s_hmPut, jKey, boxed);
    env->DeleteLocalRef(jKey);
    env->DeleteLocalRef(boxed);
}

static void map_put_double(JNIEnv* env, jobject map, const char* key, jdouble val) {
    jstring jKey  = env->NewStringUTF(key);
    jobject boxed = env->CallStaticObjectMethod(s_doubleClass, s_doubleValueOf, val);
    env->CallObjectMethod(map, s_hmPut, jKey, boxed);
    env->DeleteLocalRef(jKey);
    env->DeleteLocalRef(boxed);
}

static void map_put_string(JNIEnv* env, jobject map, const char* key, const char* val) {
    jstring jKey = env->NewStringUTF(key);
    jstring jVal = env->NewStringUTF(val ? val : "");
    env->CallObjectMethod(map, s_hmPut, jKey, jVal);
    env->DeleteLocalRef(jKey);
    env->DeleteLocalRef(jVal);
}

static void map_put_bool(JNIEnv* env, jobject map, const char* key, jboolean val) {
    jstring jKey  = env->NewStringUTF(key);
    jobject boxed = env->CallStaticObjectMethod(s_boolClass, s_boolValueOf, val);
    env->CallObjectMethod(map, s_hmPut, jKey, boxed);
    env->DeleteLocalRef(jKey);
    env->DeleteLocalRef(boxed);
}

static void map_put_object(JNIEnv* env, jobject map, const char* key, jobject val) {
    jstring jKey = env->NewStringUTF(key);
    env->CallObjectMethod(map, s_hmPut, jKey, val);
    env->DeleteLocalRef(jKey);
}

// ─── Callback forward declarations ────────────────────────────────────────────

static void on_eeg_data(clCDevice, clCEEGTimedData) noexcept;
static void on_psd_data(clCDevice, clCPSDData) noexcept;
static void on_artifacts_data(clCDevice, clCEEGArtifacts) noexcept;
static void on_resistance_data(clCDevice, clCResistance) noexcept;
static void on_battery_data(clCDevice, uint8_t) noexcept;
static void on_error_data(clCDevice, const char*) noexcept;
static void on_connection_status_changed(clCDevice, clCDevice_ConnectionStatus) noexcept;
static void on_mode_switched(clCDevice, clCDevice_Mode) noexcept;

// ─── JNI functions ────────────────────────────────────────────────────────────

extern "C" {

// ── Library load ──────────────────────────────────────────────────────────────

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* /*reserved*/) {
    JNIEnv* env = nullptr;
    if (vm->GetEnv((void**)&env, JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;
    init_map_cache(env);
    return JNI_VERSION_1_6;
}

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

// ── Stream registration ───────────────────────────────────────────────────────

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeRegisterDeviceCallbacks(
    JNIEnv* env, jobject, jlong handle)
{
    if (handle == 0) return;
    clCDevice dev = (clCDevice)(uintptr_t)handle;
    register_device_slot(dev);
    clCDevice_SetOnEEGDataEvent(dev, on_eeg_data);
    clCDevice_SetOnPSDDataEvent(dev, on_psd_data);
    clCDevice_SetOnEEGArtifactsEvent(dev, on_artifacts_data);
    clCDevice_SetOnResistanceUpdateEvent(dev, on_resistance_data);
    clCDevice_SetOnBatteryChargeUpdateEvent(dev, on_battery_data);
    clCDevice_SetOnErrorEvent(dev, on_error_data);
    clCDevice_SetOnConnectionStatusChangedEvent(dev, on_connection_status_changed);
    clCDevice_SetOnModeSwitchedEvent(dev, on_mode_switched);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeUnregisterDeviceCallbacks(
    JNIEnv* /*env*/, jobject, jlong handle)
{
    if (handle == 0) return;
    clCDevice dev = (clCDevice)(uintptr_t)handle;
    clCDevice_SetOnEEGDataEvent(dev, nullptr);
    clCDevice_SetOnPSDDataEvent(dev, nullptr);
    clCDevice_SetOnEEGArtifactsEvent(dev, nullptr);
    clCDevice_SetOnResistanceUpdateEvent(dev, nullptr);
    clCDevice_SetOnBatteryChargeUpdateEvent(dev, nullptr);
    clCDevice_SetOnErrorEvent(dev, nullptr);
    clCDevice_SetOnConnectionStatusChangedEvent(dev, nullptr);
    clCDevice_SetOnModeSwitchedEvent(dev, nullptr);
    int slot = find_device_slot(dev);
    unregister_device_slot(slot);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetDeviceStreamSink(
    JNIEnv* env, jobject, jint streamType, jobject sink)
{
    if (streamType < 0 || streamType >= STREAM_COUNT) return;
    pthread_mutex_lock(&g_device_mutex);
    // Slot 0 — plugin supports one device at a time
    jobject old = g_device_slots[0].sinks[streamType];
    if (old) {
        env->DeleteGlobalRef(old);
        g_device_slots[0].sinks[streamType] = nullptr;
    }
    if (sink != nullptr) {
        g_device_slots[0].sinks[streamType] = env->NewGlobalRef(sink);
    }
    pthread_mutex_unlock(&g_device_mutex);
}

} // extern "C"

// ─── Callbacks ────────────────────────────────────────────────────────────────

// ── Battery ───────────────────────────────────────────────────────────────────

static void on_battery_data(clCDevice device, uint8_t charge) noexcept {
    if (!g_jvm) return;

    JNIEnv* env         = nullptr;
    bool    attached    = false;
    jobject sink_ref    = nullptr;
    jobject handler_ref = nullptr;
    jobject map         = nullptr;

    jint rc = g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
    if (rc == JNI_EDETACHED) {
        if (g_jvm->AttachCurrentThread(&env, nullptr) != JNI_OK) return;
        attached = true;
    } else if (rc != JNI_OK) {
        return;
    }

    int slot = find_device_slot(device);
    if (slot < 0) goto cleanup;

    pthread_mutex_lock(&g_device_mutex);
    sink_ref    = g_device_slots[slot].sinks[STREAM_BATTERY]
                      ? env->NewLocalRef(g_device_slots[slot].sinks[STREAM_BATTERY]) : nullptr;
    handler_ref = g_handler ? env->NewLocalRef(g_handler) : nullptr;
    pthread_mutex_unlock(&g_device_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    map = make_map(env);
    map_put_int(env, map, "charge", (jint)charge);
    env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map);

cleanup:
    if (map)         env->DeleteLocalRef(map);
    if (sink_ref)    env->DeleteLocalRef(sink_ref);
    if (handler_ref) env->DeleteLocalRef(handler_ref);
    if (attached)    g_jvm->DetachCurrentThread();
}

// ── Error ─────────────────────────────────────────────────────────────────────

static void on_error_data(clCDevice device, const char* message) noexcept {
    if (!g_jvm) return;

    JNIEnv* env         = nullptr;
    bool    attached    = false;
    jobject sink_ref    = nullptr;
    jobject handler_ref = nullptr;
    jobject map         = nullptr;

    jint rc = g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
    if (rc == JNI_EDETACHED) {
        if (g_jvm->AttachCurrentThread(&env, nullptr) != JNI_OK) return;
        attached = true;
    } else if (rc != JNI_OK) {
        return;
    }

    int slot = find_device_slot(device);
    if (slot < 0) goto cleanup;

    pthread_mutex_lock(&g_device_mutex);
    sink_ref    = g_device_slots[slot].sinks[STREAM_ERROR]
                      ? env->NewLocalRef(g_device_slots[slot].sinks[STREAM_ERROR]) : nullptr;
    handler_ref = g_handler ? env->NewLocalRef(g_handler) : nullptr;
    pthread_mutex_unlock(&g_device_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    map = make_map(env);
    map_put_string(env, map, "message", message ? message : "");
    env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map);

cleanup:
    if (map)         env->DeleteLocalRef(map);
    if (sink_ref)    env->DeleteLocalRef(sink_ref);
    if (handler_ref) env->DeleteLocalRef(handler_ref);
    if (attached)    g_jvm->DetachCurrentThread();
}

// ── Connection status ─────────────────────────────────────────────────────────

static void on_connection_status_changed(
    clCDevice device, clCDevice_ConnectionStatus status) noexcept
{
    if (!g_jvm) return;

    JNIEnv* env         = nullptr;
    bool    attached    = false;
    jobject sink_ref    = nullptr;
    jobject handler_ref = nullptr;
    jobject map         = nullptr;

    jint rc = g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
    if (rc == JNI_EDETACHED) {
        if (g_jvm->AttachCurrentThread(&env, nullptr) != JNI_OK) return;
        attached = true;
    } else if (rc != JNI_OK) {
        return;
    }

    int slot = find_device_slot(device);
    if (slot < 0) goto cleanup;

    pthread_mutex_lock(&g_device_mutex);
    sink_ref    = g_device_slots[slot].sinks[STREAM_CONNECTION_STATUS]
                      ? env->NewLocalRef(g_device_slots[slot].sinks[STREAM_CONNECTION_STATUS]) : nullptr;
    handler_ref = g_handler ? env->NewLocalRef(g_handler) : nullptr;
    pthread_mutex_unlock(&g_device_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    map = make_map(env);
    map_put_int(env, map, "state", (jint)status);
    env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map);

cleanup:
    if (map)         env->DeleteLocalRef(map);
    if (sink_ref)    env->DeleteLocalRef(sink_ref);
    if (handler_ref) env->DeleteLocalRef(handler_ref);
    if (attached)    g_jvm->DetachCurrentThread();
}

// ── Mode switched ─────────────────────────────────────────────────────────────

static void on_mode_switched(clCDevice device, clCDevice_Mode mode) noexcept {
    if (!g_jvm) return;

    JNIEnv* env         = nullptr;
    bool    attached    = false;
    jobject sink_ref    = nullptr;
    jobject handler_ref = nullptr;
    jobject map         = nullptr;

    jint rc = g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
    if (rc == JNI_EDETACHED) {
        if (g_jvm->AttachCurrentThread(&env, nullptr) != JNI_OK) return;
        attached = true;
    } else if (rc != JNI_OK) {
        return;
    }

    int slot = find_device_slot(device);
    if (slot < 0) goto cleanup;

    pthread_mutex_lock(&g_device_mutex);
    sink_ref    = g_device_slots[slot].sinks[STREAM_MODE]
                      ? env->NewLocalRef(g_device_slots[slot].sinks[STREAM_MODE]) : nullptr;
    handler_ref = g_handler ? env->NewLocalRef(g_handler) : nullptr;
    pthread_mutex_unlock(&g_device_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    map = make_map(env);
    map_put_int(env, map, "mode", (jint)mode);
    env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map);

cleanup:
    if (map)         env->DeleteLocalRef(map);
    if (sink_ref)    env->DeleteLocalRef(sink_ref);
    if (handler_ref) env->DeleteLocalRef(handler_ref);
    if (attached)    g_jvm->DetachCurrentThread();
}

// ── EEG ───────────────────────────────────────────────────────────────────────

static void on_eeg_data(clCDevice device, clCEEGTimedData data) noexcept {
    if (!g_jvm) return;

    JNIEnv*      env             = nullptr;
    bool         attached        = false;
    jobject      sink_ref        = nullptr;
    jobject      handler_ref     = nullptr;
    jobject      map             = nullptr;
    jobjectArray rawValues       = nullptr;
    jobjectArray processedValues = nullptr;
    jfloat*      buf             = nullptr;

    jint rc = g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
    if (rc == JNI_EDETACHED) {
        if (g_jvm->AttachCurrentThread(&env, nullptr) != JNI_OK) return;
        attached = true;
    } else if (rc != JNI_OK) {
        return;
    }

    int slot = find_device_slot(device);
    if (slot < 0) goto cleanup;

    pthread_mutex_lock(&g_device_mutex);
    sink_ref    = g_device_slots[slot].sinks[STREAM_EEG]
                      ? env->NewLocalRef(g_device_slots[slot].sinks[STREAM_EEG]) : nullptr;
    handler_ref = g_handler ? env->NewLocalRef(g_handler) : nullptr;
    pthread_mutex_unlock(&g_device_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    {
        clCError error = {};
        int32_t channelCount = clCEEGTimedData_GetChannelsCount(data, &error);
        if (!error.success) goto cleanup;

        error = {};
        int32_t sampleCount = clCEEGTimedData_GetSamplesCount(data, &error);
        if (!error.success) goto cleanup;

        error = {};
        uint64_t ts = clCEEGTimedData_GetTimestampMilli(data, 0, &error);
        if (!error.success) goto cleanup;

        jclass floatArrayClass = env->FindClass("[F");
        rawValues       = env->NewObjectArray(channelCount, floatArrayClass, nullptr);
        processedValues = env->NewObjectArray(channelCount, floatArrayClass, nullptr);
        env->DeleteLocalRef(floatArrayClass);

        if (sampleCount > 0) {
            buf = new jfloat[sampleCount];
        }

        bool ok = true;
        for (int ch = 0; ch < channelCount && ok; ++ch) {
            for (int s = 0; s < sampleCount && ok; ++s) {
                error = {};
                buf[s] = clCEEGTimedData_GetRawValue(data, ch, s, &error);
                if (!error.success) { ok = false; }
            }
            if (!ok) break;
            jfloatArray inner = env->NewFloatArray(sampleCount);
            if (sampleCount > 0) env->SetFloatArrayRegion(inner, 0, sampleCount, buf);
            env->SetObjectArrayElement(rawValues, ch, inner);
            env->DeleteLocalRef(inner);

            for (int s = 0; s < sampleCount && ok; ++s) {
                error = {};
                buf[s] = clCEEGTimedData_GetProcessedValue(data, ch, s, &error);
                if (!error.success) { ok = false; }
            }
            if (!ok) break;
            inner = env->NewFloatArray(sampleCount);
            if (sampleCount > 0) env->SetFloatArrayRegion(inner, 0, sampleCount, buf);
            env->SetObjectArrayElement(processedValues, ch, inner);
            env->DeleteLocalRef(inner);
        }
        if (!ok) goto cleanup;

        map = make_map(env);
        map_put_long(env, map, "ts", (jlong)ts);
        map_put_int(env, map, "channelCount", (jint)channelCount);
        map_put_int(env, map, "sampleCount", (jint)sampleCount);
        map_put_object(env, map, "rawValues", rawValues);
        map_put_object(env, map, "processedValues", processedValues);
        env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map);
    }

cleanup:
    delete[] buf;
    if (rawValues)        env->DeleteLocalRef(rawValues);
    if (processedValues)  env->DeleteLocalRef(processedValues);
    if (map)              env->DeleteLocalRef(map);
    if (sink_ref)         env->DeleteLocalRef(sink_ref);
    if (handler_ref)      env->DeleteLocalRef(handler_ref);
    if (attached)         g_jvm->DetachCurrentThread();
}

// ── PSD ───────────────────────────────────────────────────────────────────────

static void on_psd_data(clCDevice device, clCPSDData data) noexcept {
    if (!g_jvm) return;

    JNIEnv*      env         = nullptr;
    bool         attached    = false;
    jobject      sink_ref    = nullptr;
    jobject      handler_ref = nullptr;
    jobject      map         = nullptr;
    jdoubleArray frequencies = nullptr;
    jobjectArray values      = nullptr;
    jdouble*     buf         = nullptr;

    jint rc = g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
    if (rc == JNI_EDETACHED) {
        if (g_jvm->AttachCurrentThread(&env, nullptr) != JNI_OK) return;
        attached = true;
    } else if (rc != JNI_OK) {
        return;
    }

    int slot = find_device_slot(device);
    if (slot < 0) goto cleanup;

    pthread_mutex_lock(&g_device_mutex);
    sink_ref    = g_device_slots[slot].sinks[STREAM_PSD]
                      ? env->NewLocalRef(g_device_slots[slot].sinks[STREAM_PSD]) : nullptr;
    handler_ref = g_handler ? env->NewLocalRef(g_handler) : nullptr;
    pthread_mutex_unlock(&g_device_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    {
        clCError error = {};
        uint64_t ts = clCPSDData_GetTimestampMilli(data, &error);
        if (!error.success) goto cleanup;

        error = {};
        int32_t freqCount = clCPSDData_GetFrequenciesCount(data, &error);
        if (!error.success) goto cleanup;

        error = {};
        int32_t channelCount = clCPSDData_GetChannelsCount(data, &error);
        if (!error.success) goto cleanup;

        // Frequency array
        frequencies = env->NewDoubleArray(freqCount);
        if (freqCount > 0) {
            buf = new jdouble[freqCount];
            bool ok = true;
            for (int f = 0; f < freqCount && ok; ++f) {
                error = {};
                buf[f] = clCPSDData_GetFrequency(data, f, &error);
                if (!error.success) { ok = false; }
            }
            if (!ok) goto cleanup;
            env->SetDoubleArrayRegion(frequencies, 0, freqCount, buf);
            delete[] buf;
            buf = nullptr;
        }

        // PSD values: double[channels][frequencies]
        jclass doubleArrayClass = env->FindClass("[D");
        values = env->NewObjectArray(channelCount, doubleArrayClass, nullptr);
        env->DeleteLocalRef(doubleArrayClass);

        if (freqCount > 0) {
            buf = new jdouble[freqCount];
        }
        bool ok = true;
        for (int ch = 0; ch < channelCount && ok; ++ch) {
            for (int f = 0; f < freqCount && ok; ++f) {
                error = {};
                buf[f] = clCPSDData_GetPSD(data, ch, f, &error);
                if (!error.success) { ok = false; }
            }
            if (!ok) break;
            jdoubleArray inner = env->NewDoubleArray(freqCount);
            if (freqCount > 0) env->SetDoubleArrayRegion(inner, 0, freqCount, buf);
            env->SetObjectArrayElement(values, ch, inner);
            env->DeleteLocalRef(inner);
        }
        if (!ok) goto cleanup;

        // Band bounds
        const clCPSDData_Band kBands[5] = {
            clCPSDData_Band_Delta, clCPSDData_Band_Theta, clCPSDData_Band_Alpha,
            clCPSDData_Band_SMR,   clCPSDData_Band_Beta
        };
        const char* kLowerKeys[5] = {
            "deltaLower", "thetaLower", "alphaLower", "smrLower", "betaLower"
        };
        const char* kUpperKeys[5] = {
            "deltaUpper", "thetaUpper", "alphaUpper", "smrUpper", "betaUpper"
        };
        float bandLower[5] = {}, bandUpper[5] = {};
        for (int b = 0; b < 5; ++b) {
            error = {};
            bandLower[b] = clCPSDData_GetBandLower(data, kBands[b], &error);
            if (!error.success) goto cleanup;
            error = {};
            bandUpper[b] = clCPSDData_GetBandUpper(data, kBands[b], &error);
            if (!error.success) goto cleanup;
        }

        // Individual alpha
        error = {};
        bool hasAlpha = clCPSDData_HasIndividualAlpha(data, &error);
        if (!error.success) goto cleanup;  // hard bail on check failure
        float iAlphaLower = -1.f, iAlphaUpper = -1.f;
        if (hasAlpha) {
            error = {};
            float v = clCPSDData_GetIndividualAlphaLower(data, &error);
            iAlphaLower = error.success ? v : -1.f;
            error = {};
            v = clCPSDData_GetIndividualAlphaUpper(data, &error);
            iAlphaUpper = error.success ? v : -1.f;
        }

        // Individual beta
        error = {};
        bool hasBeta = clCPSDData_HasIndividualBeta(data, &error);
        if (!error.success) goto cleanup;  // hard bail on check failure
        float iBetaLower = -1.f, iBetaUpper = -1.f;
        if (hasBeta) {
            error = {};
            float v = clCPSDData_GetIndividualBetaLower(data, &error);
            iBetaLower = error.success ? v : -1.f;
            error = {};
            v = clCPSDData_GetIndividualBetaUpper(data, &error);
            iBetaUpper = error.success ? v : -1.f;
        }

        map = make_map(env);
        map_put_long(env, map, "ts", (jlong)ts);
        map_put_object(env, map, "values", values);
        map_put_object(env, map, "frequencies", frequencies);
        map_put_int(env, map, "channelCount", (jint)channelCount);
        map_put_int(env, map, "frequencyCount", (jint)freqCount);
        for (int b = 0; b < 5; ++b) {
            map_put_float(env, map, kLowerKeys[b], bandLower[b]);
            map_put_float(env, map, kUpperKeys[b], bandUpper[b]);
        }
        map_put_float(env, map, "individualAlphaLower", iAlphaLower);
        map_put_float(env, map, "individualAlphaUpper", iAlphaUpper);
        map_put_float(env, map, "individualBetaLower",  iBetaLower);
        map_put_float(env, map, "individualBetaUpper",  iBetaUpper);
        env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map);
    }

cleanup:
    delete[] buf;
    if (frequencies) env->DeleteLocalRef(frequencies);
    if (values)      env->DeleteLocalRef(values);
    if (map)         env->DeleteLocalRef(map);
    if (sink_ref)    env->DeleteLocalRef(sink_ref);
    if (handler_ref) env->DeleteLocalRef(handler_ref);
    if (attached)    g_jvm->DetachCurrentThread();
}

// ── EEG Artifacts ─────────────────────────────────────────────────────────────

static void on_artifacts_data(clCDevice device, clCEEGArtifacts data) noexcept {
    if (!g_jvm) return;

    JNIEnv*    env         = nullptr;
    bool       attached    = false;
    jobject    sink_ref    = nullptr;
    jobject    handler_ref = nullptr;
    jobject    map         = nullptr;
    jintArray  artifacts   = nullptr;
    jfloatArray qualities  = nullptr;

    jint rc = g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
    if (rc == JNI_EDETACHED) {
        if (g_jvm->AttachCurrentThread(&env, nullptr) != JNI_OK) return;
        attached = true;
    } else if (rc != JNI_OK) {
        return;
    }

    int slot = find_device_slot(device);
    if (slot < 0) goto cleanup;

    pthread_mutex_lock(&g_device_mutex);
    sink_ref    = g_device_slots[slot].sinks[STREAM_ARTIFACTS]
                      ? env->NewLocalRef(g_device_slots[slot].sinks[STREAM_ARTIFACTS]) : nullptr;
    handler_ref = g_handler ? env->NewLocalRef(g_handler) : nullptr;
    pthread_mutex_unlock(&g_device_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    {
        clCError error = {};
        uint64_t ts = clCEEGArtifacts_GetTimestampMilli(data, &error);
        if (!error.success) goto cleanup;

        error = {};
        int32_t channelCount = clCEEGArtifacts_GetChannelsCount(data, &error);
        if (!error.success) goto cleanup;

        artifacts = env->NewIntArray(channelCount);
        qualities = env->NewFloatArray(channelCount);

        jint*   artifactBuf = new jint[channelCount];
        jfloat* qualityBuf  = new jfloat[channelCount];
        bool ok = true;
        for (int ch = 0; ch < channelCount && ok; ++ch) {
            error = {};
            uint8_t art = clCEEGArtifacts_GetArtifactByChannel(data, ch, &error);
            if (!error.success) { ok = false; break; }
            artifactBuf[ch] = (jint)art;

            error = {};
            float qual = clCEEGArtifacts_GetEEGQuality(data, ch, &error);
            if (!error.success) { ok = false; break; }
            qualityBuf[ch] = (jfloat)qual;
        }
        if (ok) {
            env->SetIntArrayRegion(artifacts, 0, channelCount, artifactBuf);
            env->SetFloatArrayRegion(qualities, 0, channelCount, qualityBuf);
        }
        delete[] artifactBuf;
        delete[] qualityBuf;
        if (!ok) goto cleanup;

        map = make_map(env);
        map_put_long(env, map, "ts", (jlong)ts);
        map_put_object(env, map, "artifacts", artifacts);
        map_put_object(env, map, "qualities", qualities);
        map_put_int(env, map, "channelCount", (jint)channelCount);
        env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map);
    }

cleanup:
    if (artifacts)   env->DeleteLocalRef(artifacts);
    if (qualities)   env->DeleteLocalRef(qualities);
    if (map)         env->DeleteLocalRef(map);
    if (sink_ref)    env->DeleteLocalRef(sink_ref);
    if (handler_ref) env->DeleteLocalRef(handler_ref);
    if (attached)    g_jvm->DetachCurrentThread();
}

// ── Resistance ────────────────────────────────────────────────────────────────

static void on_resistance_data(clCDevice device, clCResistance data) noexcept {
    if (!g_jvm) return;

    JNIEnv*      env          = nullptr;
    bool         attached     = false;
    jobject      sink_ref     = nullptr;
    jobject      handler_ref  = nullptr;
    jobject      map          = nullptr;
    jobjectArray channelNames = nullptr;
    jfloatArray  values       = nullptr;

    jint rc = g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
    if (rc == JNI_EDETACHED) {
        if (g_jvm->AttachCurrentThread(&env, nullptr) != JNI_OK) return;
        attached = true;
    } else if (rc != JNI_OK) {
        return;
    }

    int slot = find_device_slot(device);
    if (slot < 0) goto cleanup;

    pthread_mutex_lock(&g_device_mutex);
    sink_ref    = g_device_slots[slot].sinks[STREAM_RESISTANCE]
                      ? env->NewLocalRef(g_device_slots[slot].sinks[STREAM_RESISTANCE]) : nullptr;
    handler_ref = g_handler ? env->NewLocalRef(g_handler) : nullptr;
    pthread_mutex_unlock(&g_device_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    {
        int32_t count = clCResistance_GetCount(data);  // no clCError*

        channelNames = env->NewObjectArray(count, s_stringClass, nullptr);
        values       = env->NewFloatArray(count);

        jfloat* valueBuf = new jfloat[count];
        for (int i = 0; i < count; ++i) {
            const char* cName = clCResistance_GetChannelName(data, i);
            jstring jName = env->NewStringUTF(cName ? cName : "");
            env->SetObjectArrayElement(channelNames, i, jName);
            env->DeleteLocalRef(jName);

            valueBuf[i] = (jfloat)clCResistance_GetValue(data, i);
        }
        env->SetFloatArrayRegion(values, 0, count, valueBuf);
        delete[] valueBuf;

        map = make_map(env);
        map_put_object(env, map, "channelNames", channelNames);
        map_put_object(env, map, "values", values);
        map_put_int(env, map, "channelCount", (jint)count);
        env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map);
    }

cleanup:
    if (channelNames) env->DeleteLocalRef(channelNames);
    if (values)       env->DeleteLocalRef(values);
    if (map)          env->DeleteLocalRef(map);
    if (sink_ref)     env->DeleteLocalRef(sink_ref);
    if (handler_ref)  env->DeleteLocalRef(handler_ref);
    if (attached)     g_jvm->DetachCurrentThread();
}
