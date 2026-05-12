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
extern void     map_put_int(JNIEnv* env, jobject map, const char* key, jint val);
extern void     map_put_bool(JNIEnv* env, jobject map, const char* key, jboolean val);
extern void     map_put_object(JNIEnv* env, jobject map, const char* key, jobject val);

// ─── Error helper (defined in jni_device_locator.cpp) ─────────────────────────

extern void throw_sdk_error(JNIEnv* env, const clCError* error);

// ─── File-private Productivity state ──────────────────────────────────────────

static jobject         g_productivityMetricsSink             = nullptr;
static jobject         g_productivityIndexesSink             = nullptr;
static jobject         g_productivityBaselinesSink           = nullptr;
static jobject         g_productivityCalibrationProgressSink = nullptr;
static jobject         g_productivityCalibratedSink          = nullptr;
static jobject         g_productivityIndividualNfbSink       = nullptr;
static pthread_mutex_t g_productivity_mutex = PTHREAD_MUTEX_INITIALIZER;

// ─── Callback forward declarations ────────────────────────────────────────────

static void on_productivity_metrics_update(clCProductivity, const clCProductivity_Metrics*) noexcept;
static void on_productivity_indexes_update(clCProductivity, const clCProductivity_Indexes*) noexcept;
static void on_productivity_baseline_update(clCProductivity, const clCProductivity_Baselines*) noexcept;
static void on_productivity_calibration_progress(clCProductivity, float) noexcept;
static void on_productivity_individual_nfb_update(clCProductivity) noexcept;

// ─── JNI functions ────────────────────────────────────────────────────────────

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeCreateProductivity(
    JNIEnv* env, jobject, jlong deviceHandle)
{
    clCDevice dev = (clCDevice)(uintptr_t)deviceHandle;
    clCError error = {};
    clCProductivity prod = clCProductivity_Create(dev, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }

    clCProductivity_SetOnMetricsUpdateEvent(prod, on_productivity_metrics_update);
    clCProductivity_SetOnIndexesUpdateEvent(prod, on_productivity_indexes_update);
    clCProductivity_SetOnBaselineUpdateEvent(prod, on_productivity_baseline_update);
    clCProductivity_SetOnCalibrationProgressUpdateEvent(prod, on_productivity_calibration_progress);
    clCProductivity_SetOnIndividualNFBUpdateEvent(prod, on_productivity_individual_nfb_update);

    return (jlong)(uintptr_t)prod;
}

// TODO(neiry-aar): restore _CreateWithIndividualData path when the AAR exports it.
JNIEXPORT jlong JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeCreateProductivityWithIndividualData(
    JNIEnv* env, jobject,
    [[maybe_unused]] jlong  deviceHandle,
    [[maybe_unused]] jlong  ts,
    [[maybe_unused]] jint   failReason,
    [[maybe_unused]] jfloat individualFrequency,
    [[maybe_unused]] jfloat individualPeakFrequency,
    [[maybe_unused]] jfloat individualPeakFrequencyPower,
    [[maybe_unused]] jfloat individualPeakFrequencySuppression,
    [[maybe_unused]] jfloat individualBandwidth,
    [[maybe_unused]] jfloat individualNormalizedPower,
    [[maybe_unused]] jfloat lowerFrequency,
    [[maybe_unused]] jfloat upperFrequency)
{
    clCError error{};
    error.success = false;
    error.code = clCError_ModuleIsNotSupported;
    snprintf(error.message, sizeof(error.message),
             "clCProductivity_CreateWithIndividualData is not exported by the Android Capsule AAR");
    throw_sdk_error(env, &error);
    return 0;
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetProductivityMetricsSink(
    JNIEnv* env, jobject, jobject sink)
{
    pthread_mutex_lock(&g_productivity_mutex);
    if (g_productivityMetricsSink) {
        env->DeleteGlobalRef(g_productivityMetricsSink);
        g_productivityMetricsSink = nullptr;
    }
    if (sink != nullptr) {
        g_productivityMetricsSink = env->NewGlobalRef(sink);
    }
    pthread_mutex_unlock(&g_productivity_mutex);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetProductivityIndexesSink(
    JNIEnv* env, jobject, jobject sink)
{
    pthread_mutex_lock(&g_productivity_mutex);
    if (g_productivityIndexesSink) {
        env->DeleteGlobalRef(g_productivityIndexesSink);
        g_productivityIndexesSink = nullptr;
    }
    if (sink != nullptr) {
        g_productivityIndexesSink = env->NewGlobalRef(sink);
    }
    pthread_mutex_unlock(&g_productivity_mutex);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetProductivityBaselinesSink(
    JNIEnv* env, jobject, jobject sink)
{
    pthread_mutex_lock(&g_productivity_mutex);
    if (g_productivityBaselinesSink) {
        env->DeleteGlobalRef(g_productivityBaselinesSink);
        g_productivityBaselinesSink = nullptr;
    }
    if (sink != nullptr) {
        g_productivityBaselinesSink = env->NewGlobalRef(sink);
    }
    pthread_mutex_unlock(&g_productivity_mutex);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetProductivityCalibrationProgressSink(
    JNIEnv* env, jobject, jobject sink)
{
    pthread_mutex_lock(&g_productivity_mutex);
    if (g_productivityCalibrationProgressSink) {
        env->DeleteGlobalRef(g_productivityCalibrationProgressSink);
        g_productivityCalibrationProgressSink = nullptr;
    }
    if (sink != nullptr) {
        g_productivityCalibrationProgressSink = env->NewGlobalRef(sink);
    }
    pthread_mutex_unlock(&g_productivity_mutex);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetProductivityCalibratedSink(
    JNIEnv* env, jobject, jobject sink)
{
    pthread_mutex_lock(&g_productivity_mutex);
    if (g_productivityCalibratedSink) {
        env->DeleteGlobalRef(g_productivityCalibratedSink);
        g_productivityCalibratedSink = nullptr;
    }
    if (sink != nullptr) {
        g_productivityCalibratedSink = env->NewGlobalRef(sink);
    }
    pthread_mutex_unlock(&g_productivity_mutex);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetProductivityIndividualNfbSink(
    JNIEnv* env, jobject, jobject sink)
{
    pthread_mutex_lock(&g_productivity_mutex);
    if (g_productivityIndividualNfbSink) {
        env->DeleteGlobalRef(g_productivityIndividualNfbSink);
        g_productivityIndividualNfbSink = nullptr;
    }
    if (sink != nullptr) {
        g_productivityIndividualNfbSink = env->NewGlobalRef(sink);
    }
    pthread_mutex_unlock(&g_productivity_mutex);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeStartProductivityBaselineCalibration(
    JNIEnv* /*env*/, jobject, jlong prodHandle)
{
    if (prodHandle == 0) return;
    clCProductivity prod = (clCProductivity)(uintptr_t)prodHandle;
    clCProductivity_StartBaselineCalibration(prod);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeImportProductivityBaselines(
    JNIEnv* env, jobject, jlong prodHandle, jbyteArray baselinesBytes)
{
    if (prodHandle == 0) return;
    clCProductivity prod = (clCProductivity)(uintptr_t)prodHandle;

    jsize len = env->GetArrayLength(baselinesBytes);
    if ((size_t)len != sizeof(clCProductivity_Baselines)) {
        jclass cls = env->FindClass("java/lang/IllegalArgumentException");
        if (cls) env->ThrowNew(cls, "Baselines data size mismatch");
        return;
    }

    clCProductivity_Baselines baselines = {};
    env->GetByteArrayRegion(baselinesBytes, 0, len, reinterpret_cast<jbyte*>(&baselines));

    clCError error = {};
    clCProductivity_ImportBaselines(prod, &baselines, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
    }
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeResetAccumulatedFatigue(
    JNIEnv* env, jobject, jlong prodHandle)
{
    if (prodHandle == 0) return;
    clCProductivity prod = (clCProductivity)(uintptr_t)prodHandle;
    // Metrics values may briefly show stale fatigue during reset.
    clCError error = {};
    clCProductivity_ResetAccumulatedFatigue(prod, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
    }
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeDisposeProductivity(
    JNIEnv* env, jobject, jlong prodHandle)
{
    if (prodHandle == 0) return;
    clCProductivity prod = (clCProductivity)(uintptr_t)prodHandle;

    clCProductivity_SetOnMetricsUpdateEvent(prod, nullptr);
    clCProductivity_SetOnIndexesUpdateEvent(prod, nullptr);
    clCProductivity_SetOnBaselineUpdateEvent(prod, nullptr);
    clCProductivity_SetOnCalibrationProgressUpdateEvent(prod, nullptr);
    clCProductivity_SetOnIndividualNFBUpdateEvent(prod, nullptr);

    pthread_mutex_lock(&g_productivity_mutex);
    if (g_productivityMetricsSink) {
        env->DeleteGlobalRef(g_productivityMetricsSink);
        g_productivityMetricsSink = nullptr;
    }
    if (g_productivityIndexesSink) {
        env->DeleteGlobalRef(g_productivityIndexesSink);
        g_productivityIndexesSink = nullptr;
    }
    if (g_productivityBaselinesSink) {
        env->DeleteGlobalRef(g_productivityBaselinesSink);
        g_productivityBaselinesSink = nullptr;
    }
    if (g_productivityCalibrationProgressSink) {
        env->DeleteGlobalRef(g_productivityCalibrationProgressSink);
        g_productivityCalibrationProgressSink = nullptr;
    }
    if (g_productivityCalibratedSink) {
        env->DeleteGlobalRef(g_productivityCalibratedSink);
        g_productivityCalibratedSink = nullptr;
    }
    if (g_productivityIndividualNfbSink) {
        env->DeleteGlobalRef(g_productivityIndividualNfbSink);
        g_productivityIndividualNfbSink = nullptr;
    }
    pthread_mutex_unlock(&g_productivity_mutex);
}

} // extern "C"

// ─── Callbacks ────────────────────────────────────────────────────────────────

static void on_productivity_metrics_update(clCProductivity /*prod*/, const clCProductivity_Metrics* data) noexcept {
    if (!g_jvm || !data) return;

    JNIEnv*    env         = nullptr;
    bool       attached    = false;
    jobject    sink_ref    = nullptr;
    jobject    handler_ref = nullptr;
    jobject    map         = nullptr;
    jbyteArray artifacts   = nullptr;

    jint rc = g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
    if (rc == JNI_EDETACHED) {
        if (g_jvm->AttachCurrentThread(&env, nullptr) != JNI_OK) return;
        attached = true;
    } else if (rc != JNI_OK) {
        return;
    }

    pthread_mutex_lock(&g_productivity_mutex);
    sink_ref    = g_productivityMetricsSink ? env->NewLocalRef(g_productivityMetricsSink) : nullptr;
    handler_ref = g_handler                  ? env->NewLocalRef(g_handler)                  : nullptr;
    pthread_mutex_unlock(&g_productivity_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    map = make_map(env);
    map_put_long (env, map, "ts",                  (jlong)data->timestampMilli);
    map_put_float(env, map, "fatigueScore",         (jfloat)data->fatigueScore);
    map_put_float(env, map, "reverseFatigueScore",  (jfloat)data->reverseFatigueScore);
    map_put_float(env, map, "gravityScore",         (jfloat)data->gravityScore);
    map_put_float(env, map, "relaxationScore",      (jfloat)data->relaxationScore);
    map_put_float(env, map, "concentrationScore",   (jfloat)data->concentrationScore);
    map_put_float(env, map, "productivityScore",    (jfloat)data->productivityScore);
    map_put_float(env, map, "currentValue",         (jfloat)data->currentValue);
    map_put_float(env, map, "alpha",                (jfloat)data->alpha);
    map_put_float(env, map, "productivityBaseline", (jfloat)data->productivityBaseline);
    map_put_float(env, map, "accumulatedFatigue",   (jfloat)data->accumulatedFatigue);
    map_put_int  (env, map, "fatigueGrowthRate",    (jint)data->fatigueGrowthRate);

    if (data->artifactsSize > 0 && data->artifactsData != nullptr) {
        artifacts = env->NewByteArray((jsize)data->artifactsSize);
        if (artifacts) {
            env->SetByteArrayRegion(artifacts, 0, (jsize)data->artifactsSize,
                                    reinterpret_cast<const jbyte*>(data->artifactsData));
            map_put_object(env, map, "artifactsData", artifacts);
        }
    }

    env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map);

cleanup:
    if (artifacts)   env->DeleteLocalRef(artifacts);
    if (map)         env->DeleteLocalRef(map);
    if (sink_ref)    env->DeleteLocalRef(sink_ref);
    if (handler_ref) env->DeleteLocalRef(handler_ref);
    if (attached)    g_jvm->DetachCurrentThread();
}

static void on_productivity_indexes_update(clCProductivity /*prod*/, const clCProductivity_Indexes* data) noexcept {
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

    pthread_mutex_lock(&g_productivity_mutex);
    sink_ref    = g_productivityIndexesSink ? env->NewLocalRef(g_productivityIndexesSink) : nullptr;
    handler_ref = g_handler                  ? env->NewLocalRef(g_handler)                  : nullptr;
    pthread_mutex_unlock(&g_productivity_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    map = make_map(env);
    map_put_long (env, map, "ts",                    (jlong)data->timestampMilli);
    map_put_int  (env, map, "relaxation",             (jint)data->relaxation);
    map_put_int  (env, map, "stress",                 (jint)data->stress);
    map_put_bool (env, map, "hasArtifacts",           (jboolean)data->hasArtifacts);
    map_put_float(env, map, "gravityBaseline",        (jfloat)data->gravityBaseline);
    map_put_float(env, map, "productivityBaseline",   (jfloat)data->productivityBaseline);
    map_put_float(env, map, "fatigueBaseline",        (jfloat)data->fatigueBaseline);
    map_put_float(env, map, "reverseFatigueBaseline", (jfloat)data->reverseFatigueBaseline);
    map_put_float(env, map, "relaxationBaseline",     (jfloat)data->relaxationBaseline);
    map_put_float(env, map, "concentrationBaseline",  (jfloat)data->concentrationBaseline);
    env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map);

cleanup:
    if (map)         env->DeleteLocalRef(map);
    if (sink_ref)    env->DeleteLocalRef(sink_ref);
    if (handler_ref) env->DeleteLocalRef(handler_ref);
    if (attached)    g_jvm->DetachCurrentThread();
}

// Dual-dispatch: one SDK callback feeds both the structured baselines sink and
// the raw-bytes calibrated sink, mirroring ProductivityBridge.swift lines 147–167.
static void on_productivity_baseline_update(clCProductivity /*prod*/, const clCProductivity_Baselines* data) noexcept {
    if (!g_jvm || !data) return;

    JNIEnv*    env               = nullptr;
    bool       attached          = false;
    jobject    baselinesSink_ref  = nullptr;
    jobject    calibratedSink_ref = nullptr;
    jobject    handler_ref       = nullptr;
    jobject    baselinesMap      = nullptr;
    jobject    calibratedMap     = nullptr;
    jbyteArray blob              = nullptr;

    jint rc = g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
    if (rc == JNI_EDETACHED) {
        if (g_jvm->AttachCurrentThread(&env, nullptr) != JNI_OK) return;
        attached = true;
    } else if (rc != JNI_OK) {
        return;
    }

    pthread_mutex_lock(&g_productivity_mutex);
    baselinesSink_ref  = g_productivityBaselinesSink  ? env->NewLocalRef(g_productivityBaselinesSink)  : nullptr;
    calibratedSink_ref = g_productivityCalibratedSink ? env->NewLocalRef(g_productivityCalibratedSink) : nullptr;
    handler_ref        = g_handler                     ? env->NewLocalRef(g_handler)                    : nullptr;
    pthread_mutex_unlock(&g_productivity_mutex);

    if (!handler_ref) goto cleanup;

    if (baselinesSink_ref) {
        baselinesMap = make_map(env);
        map_put_long (env, baselinesMap, "ts",             (jlong)data->timestampMilli);
        map_put_float(env, baselinesMap, "gravity",        (jfloat)data->gravity);
        map_put_float(env, baselinesMap, "productivity",   (jfloat)data->productivity);
        map_put_float(env, baselinesMap, "fatigue",        (jfloat)data->fatigue);
        map_put_float(env, baselinesMap, "reverseFatigue", (jfloat)data->reverseFatigue);
        map_put_float(env, baselinesMap, "relaxation",     (jfloat)data->relaxation);
        map_put_float(env, baselinesMap, "concentration",  (jfloat)data->concentration);
        env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, baselinesSink_ref, baselinesMap);
    }

    if (calibratedSink_ref) {
        calibratedMap = make_map(env);
        blob = env->NewByteArray((jsize)sizeof(clCProductivity_Baselines));
        if (blob) {
            env->SetByteArrayRegion(blob, 0, (jsize)sizeof(clCProductivity_Baselines),
                                    reinterpret_cast<const jbyte*>(data));
            map_put_object(env, calibratedMap, "baselines", blob);
        }
        env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, calibratedSink_ref, calibratedMap);
    }

cleanup:
    if (blob)               env->DeleteLocalRef(blob);
    if (calibratedMap)      env->DeleteLocalRef(calibratedMap);
    if (baselinesMap)       env->DeleteLocalRef(baselinesMap);
    if (baselinesSink_ref)  env->DeleteLocalRef(baselinesSink_ref);
    if (calibratedSink_ref) env->DeleteLocalRef(calibratedSink_ref);
    if (handler_ref)        env->DeleteLocalRef(handler_ref);
    if (attached)           g_jvm->DetachCurrentThread();
}

static void on_productivity_calibration_progress(clCProductivity /*prod*/, float progress) noexcept {
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

    pthread_mutex_lock(&g_productivity_mutex);
    sink_ref    = g_productivityCalibrationProgressSink ? env->NewLocalRef(g_productivityCalibrationProgressSink) : nullptr;
    handler_ref = g_handler                              ? env->NewLocalRef(g_handler)                             : nullptr;
    pthread_mutex_unlock(&g_productivity_mutex);

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

static void on_productivity_individual_nfb_update(clCProductivity /*prod*/) noexcept {
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

    pthread_mutex_lock(&g_productivity_mutex);
    sink_ref    = g_productivityIndividualNfbSink ? env->NewLocalRef(g_productivityIndividualNfbSink) : nullptr;
    handler_ref = g_handler                        ? env->NewLocalRef(g_handler)                       : nullptr;
    pthread_mutex_unlock(&g_productivity_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    map = make_map(env);
    env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map);

cleanup:
    if (map)         env->DeleteLocalRef(map);
    if (sink_ref)    env->DeleteLocalRef(sink_ref);
    if (handler_ref) env->DeleteLocalRef(handler_ref);
    if (attached)    g_jvm->DetachCurrentThread();
}
