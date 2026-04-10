#include <jni.h>
#include <pthread.h>
#include <cstdio>
#include "CCapsuleAPI.h"

// ─── Shared globals from jni_device_locator.cpp ───────────────────────────────

extern JavaVM*   g_jvm;
extern jobject   g_handler;
extern jclass    g_dispatcher_class;
extern jmethodID g_postSuccess;

// ─── Shared map helpers from jni_device.cpp ───────────────────────────────────

extern void     init_map_cache(JNIEnv* env);
extern jobject  make_map(JNIEnv* env);
extern void     map_put_float(JNIEnv* env, jobject map, const char* key, jfloat val);
extern void     map_put_long(JNIEnv* env, jobject map, const char* key, jlong val);
extern void     map_put_string(JNIEnv* env, jobject map, const char* key, const char* val);

// ─── Error helper (defined in jni_device_locator.cpp) ─────────────────────────

extern void throw_sdk_error(JNIEnv* env, const clCError* error);

// ─── File-private NFB state ───────────────────────────────────────────────────

static jobject         g_nfbStateSink  = nullptr;
static jobject         g_nfbErrorSink  = nullptr;
static pthread_mutex_t g_nfb_mutex     = PTHREAD_MUTEX_INITIALIZER;

// ─── Callback forward declarations ────────────────────────────────────────────

static void on_nfb_state_changed(clCNFB nfb, const clCNFB_UserState* data) noexcept;
static void on_nfb_error(clCNFB nfb, const char* message) noexcept;

// ─── JNI functions ────────────────────────────────────────────────────────────

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeCreateNfb(
    JNIEnv* env, jobject, jlong deviceHandle)
{
    clCDevice dev = (clCDevice)(uintptr_t)deviceHandle;
    clCError error = {};
    clCNFB nfb = clCNFB_Create(dev, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }
    clCNFB_SetOnUserStateChangedEvent(nfb, on_nfb_state_changed);
    clCNFB_SetOnErrorEvent(nfb, on_nfb_error);
    return (jlong)(uintptr_t)nfb;
}

JNIEXPORT jlong JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeCreateNfbCalibrated(
    JNIEnv* env, jobject,
    jlong deviceHandle,
    jboolean hasCalibrationData,
    jlong ts,
    jint failReason,
    jfloat individualFrequency,
    jfloat individualPeakFrequency,
    jfloat individualPeakFrequencyPower,
    jfloat individualPeakFrequencySuppression,
    jfloat individualBandwidth,
    jfloat individualNormalizedPower,
    jfloat lowerFrequency,
    jfloat upperFrequency)
{
    clCDevice dev = (clCDevice)(uintptr_t)deviceHandle;

    clCNFBCalibrator calibrator = clCNFBCalibrator_CreateOrGet(dev);
    if (!calibrator) {
        jclass cls = env->FindClass("java/lang/RuntimeException");
        if (cls) env->ThrowNew(cls, "0|clCNFBCalibrator_CreateOrGet returned null");
        return 0;
    }

    if (hasCalibrationData) {
        clCIndividualNFBData data = {};
        data.timestampMilli                  = (int64_t)ts;
        data.failReason                      = (clCIndividualNFBCalibrationFailReason)failReason;
        data.individualFrequency             = (float)individualFrequency;
        data.individualPeakFrequency         = (float)individualPeakFrequency;
        data.individualPeakFrequencyPower    = (float)individualPeakFrequencyPower;
        data.individualPeakFrequencySuppression = (float)individualPeakFrequencySuppression;
        data.individualBandwidth             = (float)individualBandwidth;
        data.individualNormalizedPower       = (float)individualNormalizedPower;
        data.lowerFrequency                  = (float)lowerFrequency;
        data.upperFrequency                  = (float)upperFrequency;

        clCError importError = {};
        clCNFBCalibrator_ImportIndividualNFBData(calibrator, &data, &importError);
        if (!importError.success) {
            throw_sdk_error(env, &importError);
            return 0;
        }
    }

    clCError error = {};
    clCNFB nfb = clCNFB_CreateCalibrated(dev, calibrator, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }

    clCNFB_SetOnUserStateChangedEvent(nfb, on_nfb_state_changed);
    clCNFB_SetOnErrorEvent(nfb, on_nfb_error);
    return (jlong)(uintptr_t)nfb;
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetNfbStateSink(
    JNIEnv* env, jobject, jobject sink)
{
    pthread_mutex_lock(&g_nfb_mutex);
    if (g_nfbStateSink) {
        env->DeleteGlobalRef(g_nfbStateSink);
        g_nfbStateSink = nullptr;
    }
    if (sink != nullptr) {
        g_nfbStateSink = env->NewGlobalRef(sink);
    }
    pthread_mutex_unlock(&g_nfb_mutex);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetNfbErrorSink(
    JNIEnv* env, jobject, jobject sink)
{
    pthread_mutex_lock(&g_nfb_mutex);
    if (g_nfbErrorSink) {
        env->DeleteGlobalRef(g_nfbErrorSink);
        g_nfbErrorSink = nullptr;
    }
    if (sink != nullptr) {
        g_nfbErrorSink = env->NewGlobalRef(sink);
    }
    pthread_mutex_unlock(&g_nfb_mutex);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeDisposeNfb(
    JNIEnv* env, jobject, jlong nfbHandle)
{
    if (nfbHandle == 0) return;
    clCNFB nfb = (clCNFB)(uintptr_t)nfbHandle;

    clCNFB_SetOnUserStateChangedEvent(nfb, nullptr);
    clCNFB_SetOnErrorEvent(nfb, nullptr);

    pthread_mutex_lock(&g_nfb_mutex);
    if (g_nfbStateSink) {
        env->DeleteGlobalRef(g_nfbStateSink);
        g_nfbStateSink = nullptr;
    }
    if (g_nfbErrorSink) {
        env->DeleteGlobalRef(g_nfbErrorSink);
        g_nfbErrorSink = nullptr;
    }
    pthread_mutex_unlock(&g_nfb_mutex);
}

} // extern "C"

// ─── Callbacks ────────────────────────────────────────────────────────────────

static void on_nfb_state_changed(clCNFB /*nfb*/, const clCNFB_UserState* data) noexcept {
    if (!g_jvm || !data) return;

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

    pthread_mutex_lock(&g_nfb_mutex);
    sink_ref    = g_nfbStateSink ? env->NewLocalRef(g_nfbStateSink) : nullptr;
    handler_ref = g_handler      ? env->NewLocalRef(g_handler)      : nullptr;
    pthread_mutex_unlock(&g_nfb_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    map = make_map(env);
    map_put_long (env, map, "ts",    (jlong)data->timestampMilli);
    map_put_float(env, map, "delta", (jfloat)data->delta);
    map_put_float(env, map, "theta", (jfloat)data->theta);
    map_put_float(env, map, "alpha", (jfloat)data->alpha);
    map_put_float(env, map, "smr",   (jfloat)data->smr);
    map_put_float(env, map, "beta",  (jfloat)data->beta);
    env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map);

cleanup:
    if (map)         env->DeleteLocalRef(map);
    if (sink_ref)    env->DeleteLocalRef(sink_ref);
    if (handler_ref) env->DeleteLocalRef(handler_ref);
    if (attached)    g_jvm->DetachCurrentThread();
}

static void on_nfb_error(clCNFB /*nfb*/, const char* message) noexcept {
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

    pthread_mutex_lock(&g_nfb_mutex);
    sink_ref    = g_nfbErrorSink ? env->NewLocalRef(g_nfbErrorSink) : nullptr;
    handler_ref = g_handler      ? env->NewLocalRef(g_handler)      : nullptr;
    pthread_mutex_unlock(&g_nfb_mutex);

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
