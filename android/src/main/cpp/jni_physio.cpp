#include <jni.h>
#include <pthread.h>
#include <cstdio>
#include <cmath>
#include "CCapsuleAPI.h"

// ─── Shared globals from jni_device_locator.cpp ───────────────────────────────

extern JavaVM*   g_jvm;
extern jobject   g_handler;
extern jclass    g_dispatcher_class;
extern jmethodID g_postSuccess;

// ─── Shared map helpers from jni_device.cpp ───────────────────────────────────

extern jobject  make_map(JNIEnv* env);
extern void     map_put_float(JNIEnv* env, jobject map, const char* key, jfloat val);
extern void     map_put_long(JNIEnv* env, jobject map, const char* key, jlong val);
extern void     map_put_bool(JNIEnv* env, jobject map, const char* key, jboolean val);

// ─── Error helper (defined in jni_device_locator.cpp) ─────────────────────────

extern void throw_sdk_error(JNIEnv* env, const clCError* error);

// ─── File-private PhysiologicalStates state ───────────────────────────────────

static jobject         g_physioStateSink               = nullptr;
static jobject         g_physioCalibrationProgressSink = nullptr;
static jobject         g_physioCalibratedSink           = nullptr;
static jobject         g_physioIndividualNfbSink        = nullptr;
static pthread_mutex_t g_physio_mutex = PTHREAD_MUTEX_INITIALIZER;

// ─── Callback forward declarations ────────────────────────────────────────────

static void on_physio_state_changed(clCPhysiologicalStates, const clCPhysiologicalStates_Value*) noexcept;
static void on_physio_calibration_progress(clCPhysiologicalStates, float) noexcept;
static void on_physio_calibrated(clCPhysiologicalStates, const clCPhysiologicalStates_Baselines*) noexcept;
static void on_physio_individual_nfb_update(clCPhysiologicalStates) noexcept;

// ─── JNI functions ────────────────────────────────────────────────────────────

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeCreatePhysio(
    JNIEnv* env, jobject, jlong deviceHandle)
{
    clCDevice dev = (clCDevice)(uintptr_t)deviceHandle;
    clCError error = {};
    clCPhysiologicalStates physio = clCPhysiologicalStates_Create(dev, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }

    clCPhysiologicalStates_SetOnStatesUpdateEvent(physio, on_physio_state_changed, &error);
    if (!error.success) { throw_sdk_error(env, &error); return 0; }

    clCPhysiologicalStates_SetOnCalibrationProgressUpdateEvent(physio, on_physio_calibration_progress, &error);
    if (!error.success) { throw_sdk_error(env, &error); return 0; }

    clCPhysiologicalStates_SetOnCalibratedEvent(physio, on_physio_calibrated, &error);
    if (!error.success) { throw_sdk_error(env, &error); return 0; }

    clCPhysiologicalStates_SetOnIndividualNFBUpdateEvent(physio, on_physio_individual_nfb_update, &error);
    if (!error.success) { throw_sdk_error(env, &error); return 0; }

    return (jlong)(uintptr_t)physio;
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetPhysioStateSink(
    JNIEnv* env, jobject, jobject sink)
{
    pthread_mutex_lock(&g_physio_mutex);
    if (g_physioStateSink) {
        env->DeleteGlobalRef(g_physioStateSink);
        g_physioStateSink = nullptr;
    }
    if (sink != nullptr) {
        g_physioStateSink = env->NewGlobalRef(sink);
    }
    pthread_mutex_unlock(&g_physio_mutex);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetPhysioCalibrationProgressSink(
    JNIEnv* env, jobject, jobject sink)
{
    pthread_mutex_lock(&g_physio_mutex);
    if (g_physioCalibrationProgressSink) {
        env->DeleteGlobalRef(g_physioCalibrationProgressSink);
        g_physioCalibrationProgressSink = nullptr;
    }
    if (sink != nullptr) {
        g_physioCalibrationProgressSink = env->NewGlobalRef(sink);
    }
    pthread_mutex_unlock(&g_physio_mutex);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetPhysioCalibratedSink(
    JNIEnv* env, jobject, jobject sink)
{
    pthread_mutex_lock(&g_physio_mutex);
    if (g_physioCalibratedSink) {
        env->DeleteGlobalRef(g_physioCalibratedSink);
        g_physioCalibratedSink = nullptr;
    }
    if (sink != nullptr) {
        g_physioCalibratedSink = env->NewGlobalRef(sink);
    }
    pthread_mutex_unlock(&g_physio_mutex);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetPhysioIndividualNfbSink(
    JNIEnv* env, jobject, jobject sink)
{
    pthread_mutex_lock(&g_physio_mutex);
    if (g_physioIndividualNfbSink) {
        env->DeleteGlobalRef(g_physioIndividualNfbSink);
        g_physioIndividualNfbSink = nullptr;
    }
    if (sink != nullptr) {
        g_physioIndividualNfbSink = env->NewGlobalRef(sink);
    }
    pthread_mutex_unlock(&g_physio_mutex);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeStartBaselineCalibration(
    JNIEnv* /*env*/, jobject, jlong physioHandle)
{
    if (physioHandle == 0) return;
    clCPhysiologicalStates physio = (clCPhysiologicalStates)(uintptr_t)physioHandle;
    clCPhysiologicalStates_StartBaselineCalibration(physio);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeImportBaselines(
    JNIEnv* /*env*/, jobject, jlong physioHandle,
    jlong ts, jfloat alpha, jfloat beta,
    jfloat alphaGravity, jfloat betaGravity, jfloat concentration)
{
    if (physioHandle == 0) return;
    clCPhysiologicalStates physio = (clCPhysiologicalStates)(uintptr_t)physioHandle;
    clCPhysiologicalStates_Baselines baselines = {};
    baselines.timestampMilli = (int64_t)ts;
    baselines.alpha          = alpha;
    baselines.beta           = beta;
    baselines.alphaGravity   = alphaGravity;
    baselines.betaGravity    = betaGravity;
    baselines.concentration  = concentration;
    clCPhysiologicalStates_ImportBaselines(physio, &baselines);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeDisposePhysio(
    JNIEnv* env, jobject, jlong physioHandle)
{
    if (physioHandle == 0) return;
    clCPhysiologicalStates physio = (clCPhysiologicalStates)(uintptr_t)physioHandle;

    clCError err = {};
    clCPhysiologicalStates_SetOnStatesUpdateEvent(physio, nullptr, &err);
    clCPhysiologicalStates_SetOnCalibrationProgressUpdateEvent(physio, nullptr, &err);
    clCPhysiologicalStates_SetOnCalibratedEvent(physio, nullptr, &err);
    clCPhysiologicalStates_SetOnIndividualNFBUpdateEvent(physio, nullptr, &err);

    pthread_mutex_lock(&g_physio_mutex);
    if (g_physioStateSink) {
        env->DeleteGlobalRef(g_physioStateSink);
        g_physioStateSink = nullptr;
    }
    if (g_physioCalibrationProgressSink) {
        env->DeleteGlobalRef(g_physioCalibrationProgressSink);
        g_physioCalibrationProgressSink = nullptr;
    }
    if (g_physioCalibratedSink) {
        env->DeleteGlobalRef(g_physioCalibratedSink);
        g_physioCalibratedSink = nullptr;
    }
    if (g_physioIndividualNfbSink) {
        env->DeleteGlobalRef(g_physioIndividualNfbSink);
        g_physioIndividualNfbSink = nullptr;
    }
    pthread_mutex_unlock(&g_physio_mutex);
}

} // extern "C"

// ─── Callbacks ────────────────────────────────────────────────────────────────

static void on_physio_state_changed(clCPhysiologicalStates /*physio*/, const clCPhysiologicalStates_Value* data) noexcept {
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

    pthread_mutex_lock(&g_physio_mutex);
    sink_ref    = g_physioStateSink ? env->NewLocalRef(g_physioStateSink) : nullptr;
    handler_ref = g_handler         ? env->NewLocalRef(g_handler)         : nullptr;
    pthread_mutex_unlock(&g_physio_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    map = make_map(env);
    map_put_long (env, map, "ts",             (jlong)data->timestampMilli);
    map_put_float(env, map, "relaxation",     (jfloat)data->relaxation);
    map_put_float(env, map, "fatigue",        (jfloat)data->fatigue);
    map_put_float(env, map, "none",           (jfloat)data->none);
    map_put_float(env, map, "concentration",  (jfloat)data->concentration);
    map_put_float(env, map, "involvement",    (jfloat)data->involvement);
    map_put_float(env, map, "stress",         (jfloat)data->stress);
    map_put_bool (env, map, "nfbArtifacts",   (jboolean)data->nfbArtifacts);
    map_put_bool (env, map, "cardioArtifacts",(jboolean)data->cardioArtifacts);
    env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map);

cleanup:
    if (map)         env->DeleteLocalRef(map);
    if (sink_ref)    env->DeleteLocalRef(sink_ref);
    if (handler_ref) env->DeleteLocalRef(handler_ref);
    if (attached)    g_jvm->DetachCurrentThread();
}

static void on_physio_calibration_progress(clCPhysiologicalStates /*physio*/, float progress) noexcept {
    if (!g_jvm) return;

    JNIEnv* env         = nullptr;
    bool    attached    = false;
    jobject sink_ref    = nullptr;
    jobject handler_ref = nullptr;
    jobject map         = nullptr;
    float   clamped     = fmaxf(0.0f, fminf(1.0f, progress));

    jint rc = g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
    if (rc == JNI_EDETACHED) {
        if (g_jvm->AttachCurrentThread(&env, nullptr) != JNI_OK) return;
        attached = true;
    } else if (rc != JNI_OK) {
        return;
    }

    pthread_mutex_lock(&g_physio_mutex);
    sink_ref    = g_physioCalibrationProgressSink ? env->NewLocalRef(g_physioCalibrationProgressSink) : nullptr;
    handler_ref = g_handler                        ? env->NewLocalRef(g_handler)                       : nullptr;
    pthread_mutex_unlock(&g_physio_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    map = make_map(env);
    map_put_float(env, map, "progress", (jfloat)clamped);
    env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map);

cleanup:
    if (map)         env->DeleteLocalRef(map);
    if (sink_ref)    env->DeleteLocalRef(sink_ref);
    if (handler_ref) env->DeleteLocalRef(handler_ref);
    if (attached)    g_jvm->DetachCurrentThread();
}

static void on_physio_calibrated(clCPhysiologicalStates /*physio*/, const clCPhysiologicalStates_Baselines* baselines) noexcept {
    if (!g_jvm || !baselines) return;

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

    pthread_mutex_lock(&g_physio_mutex);
    sink_ref    = g_physioCalibratedSink ? env->NewLocalRef(g_physioCalibratedSink) : nullptr;
    handler_ref = g_handler              ? env->NewLocalRef(g_handler)              : nullptr;
    pthread_mutex_unlock(&g_physio_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    map = make_map(env);
    map_put_long (env, map, "ts",            (jlong)baselines->timestampMilli);
    map_put_float(env, map, "alpha",         (jfloat)baselines->alpha);
    map_put_float(env, map, "beta",          (jfloat)baselines->beta);
    map_put_float(env, map, "alphaGravity",  (jfloat)baselines->alphaGravity);
    map_put_float(env, map, "betaGravity",   (jfloat)baselines->betaGravity);
    map_put_float(env, map, "concentration", (jfloat)baselines->concentration);
    env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map);

cleanup:
    if (map)         env->DeleteLocalRef(map);
    if (sink_ref)    env->DeleteLocalRef(sink_ref);
    if (handler_ref) env->DeleteLocalRef(handler_ref);
    if (attached)    g_jvm->DetachCurrentThread();
}

static void on_physio_individual_nfb_update(clCPhysiologicalStates /*physio*/) noexcept {
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

    pthread_mutex_lock(&g_physio_mutex);
    sink_ref    = g_physioIndividualNfbSink ? env->NewLocalRef(g_physioIndividualNfbSink) : nullptr;
    handler_ref = g_handler                 ? env->NewLocalRef(g_handler)                 : nullptr;
    pthread_mutex_unlock(&g_physio_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    map = make_map(env);
    env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map);

cleanup:
    if (map)         env->DeleteLocalRef(map);
    if (sink_ref)    env->DeleteLocalRef(sink_ref);
    if (handler_ref) env->DeleteLocalRef(handler_ref);
    if (attached)    g_jvm->DetachCurrentThread();
}
