#include <jni.h>
#include <pthread.h>
#include <cstdio>
#include "CCapsuleAPI.h"

// ─── Shared globals from jni_device_locator.cpp ───────────────────────────────

extern JavaVM*   g_jvm;
extern jobject   g_handler;
extern jclass    g_dispatcher_class;
extern jmethodID g_postSuccess;
extern jmethodID g_postError;

// ─── Shared map helpers from jni_device.cpp ───────────────────────────────────

extern void    init_map_cache(JNIEnv* env);
extern jobject make_map(JNIEnv* env);
extern void    map_put_int   (JNIEnv* env, jobject map, const char* key, jint val);
extern void    map_put_float (JNIEnv* env, jobject map, const char* key, jfloat val);
extern void    map_put_long  (JNIEnv* env, jobject map, const char* key, jlong val);
extern void    map_put_string(JNIEnv* env, jobject map, const char* key, const char* val);
extern void    map_put_object(JNIEnv* env, jobject map, const char* key, jobject val);

// ─── Error helper (defined in jni_device_locator.cpp) ─────────────────────────

extern void throw_sdk_error(JNIEnv* env, const clCError* error);

// ─── File-private calibrator state ───────────────────────────────────────────

static clCNFBCalibrator g_calibrator      = nullptr;
static int              g_currentStage    = 0;
static bool             g_isQuickMode     = false;
static jobject          g_calibrationSink = nullptr;
static pthread_mutex_t  g_cal_mutex       = PTHREAD_MUTEX_INITIALIZER;

// ─── Callback forward declarations ────────────────────────────────────────────

static void on_calibration_stage_finished(clCNFBCalibrator calibrator) noexcept;
static void on_calibrated(clCNFBCalibrator calibrator, const clCIndividualNFBData* data) noexcept;

// ─── JNI functions ────────────────────────────────────────────────────────────

extern "C" {

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeStartCalibration(
    JNIEnv* env, jobject, jlong deviceHandle, jboolean quick)
{
    clCDevice dev = (clCDevice)(uintptr_t)deviceHandle;

    clCNFBCalibrator cal = clCNFBCalibrator_CreateOrGet(dev);
    if (!cal) {
        jclass cls = env->FindClass("java/lang/RuntimeException");
        if (cls) env->ThrowNew(cls, "0|clCNFBCalibrator_CreateOrGet returned null");
        return;
    }

    g_calibrator   = cal;
    g_currentStage = 0;
    g_isQuickMode  = (bool)quick;

    clCNFBCalibrator_SetOnCalibrationStageFinishedEvent(cal, on_calibration_stage_finished);
    clCNFBCalibrator_SetOnCalibratedEvent(cal, on_calibrated);

    clCError error = {};
    if (quick) {
        clCNFBCalibrator_CalibrateIndividualNFBQuick(cal, &error);
    } else {
        clCNFBCalibrator_CalibrateIndividualNFB(cal, clCIndividualNFBCalibrationStage_1, &error);
    }

    if (!error.success) {
        throw_sdk_error(env, &error);
    }
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeStopCalibration(
    JNIEnv* /*env*/, jobject)
{
    if (g_calibrator) {
        clCNFBCalibrator_SetOnCalibrationStageFinishedEvent(g_calibrator, nullptr);
        clCNFBCalibrator_SetOnCalibratedEvent(g_calibrator, nullptr);
    }
    g_currentStage = 0;
    g_isQuickMode  = false;
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeImportCalibration(
    JNIEnv* env, jobject,
    jlong deviceHandle,
    jlong ts, jint failReason,
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

    clCNFBCalibrator cal = clCNFBCalibrator_CreateOrGet(dev);
    if (!cal) {
        jclass cls = env->FindClass("java/lang/RuntimeException");
        if (cls) env->ThrowNew(cls, "0|clCNFBCalibrator_CreateOrGet returned null");
        return;
    }

    clCIndividualNFBData data = {};
    data.timestampMilli                     = (int64_t)ts;
    data.failReason                         = (clCIndividualNFBCalibrationFailReason)failReason;
    data.individualFrequency                = (float)individualFrequency;
    data.individualPeakFrequency            = (float)individualPeakFrequency;
    data.individualPeakFrequencyPower       = (float)individualPeakFrequencyPower;
    data.individualPeakFrequencySuppression = (float)individualPeakFrequencySuppression;
    data.individualBandwidth                = (float)individualBandwidth;
    data.individualNormalizedPower          = (float)individualNormalizedPower;
    data.lowerFrequency                     = (float)lowerFrequency;
    data.upperFrequency                     = (float)upperFrequency;

    clCError error = {};
    clCNFBCalibrator_ImportIndividualNFBData(cal, &data, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
    }
}

JNIEXPORT jobject JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeGetCalibration(
    JNIEnv* env, jobject, jlong deviceHandle)
{
    clCDevice dev = (clCDevice)(uintptr_t)deviceHandle;

    clCNFBCalibrator cal = clCNFBCalibrator_CreateOrGet(dev);
    if (!cal) return nullptr;

    if (!clCNFBCalibrator_IsCalibrated(cal)) return nullptr;

    clCIndividualNFBData data = {};
    clCError error = {};
    clCNFBCalibrator_GetIndividualNFB(cal, &data, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return nullptr;
    }

    jobject map = make_map(env);
    map_put_long  (env, map, "ts",                              (jlong)data.timestampMilli);
    map_put_int   (env, map, "failReason",                      (jint)data.failReason);
    map_put_float (env, map, "individualFrequency",             (jfloat)data.individualFrequency);
    map_put_float (env, map, "individualPeakFrequency",         (jfloat)data.individualPeakFrequency);
    map_put_float (env, map, "individualPeakFrequencyPower",    (jfloat)data.individualPeakFrequencyPower);
    map_put_float (env, map, "individualPeakFrequencySuppression", (jfloat)data.individualPeakFrequencySuppression);
    map_put_float (env, map, "individualBandwidth",             (jfloat)data.individualBandwidth);
    map_put_float (env, map, "individualNormalizedPower",       (jfloat)data.individualNormalizedPower);
    map_put_float (env, map, "lowerFrequency",                  (jfloat)data.lowerFrequency);
    map_put_float (env, map, "upperFrequency",                  (jfloat)data.upperFrequency);
    return map;
}

JNIEXPORT jboolean JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeIsCalibrated(
    JNIEnv* /*env*/, jobject, jlong deviceHandle)
{
    clCDevice dev = (clCDevice)(uintptr_t)deviceHandle;
    clCNFBCalibrator cal = clCNFBCalibrator_CreateOrGet(dev);
    if (!cal) return JNI_FALSE;
    return (jboolean)clCNFBCalibrator_IsCalibrated(cal);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetNfbCalibrationSink(
    JNIEnv* env, jobject, jobject sink)
{
    pthread_mutex_lock(&g_cal_mutex);
    if (g_calibrationSink) {
        env->DeleteGlobalRef(g_calibrationSink);
        g_calibrationSink = nullptr;
    }
    if (sink != nullptr) {
        g_calibrationSink = env->NewGlobalRef(sink);
    }
    pthread_mutex_unlock(&g_cal_mutex);
}

} // extern "C"

// ─── Callbacks ────────────────────────────────────────────────────────────────

static void on_calibration_stage_finished(clCNFBCalibrator /*calibrator*/) noexcept {
    if (g_isQuickMode) return;
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

    pthread_mutex_lock(&g_cal_mutex);
    sink_ref    = g_calibrationSink ? env->NewLocalRef(g_calibrationSink) : nullptr;
    handler_ref = g_handler         ? env->NewLocalRef(g_handler)         : nullptr;
    pthread_mutex_unlock(&g_cal_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    map = make_map(env);
    map_put_string(env, map, "type",  "stage");
    map_put_int   (env, map, "stage", (jint)g_currentStage);
    env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map);
    env->DeleteLocalRef(map);
    map = nullptr;

    ++g_currentStage;

    if (g_currentStage < 4) {
        clCError error = {};
        clCNFBCalibrator_CalibrateIndividualNFB(
            g_calibrator,
            (clCIndividualNFBCalibrationStage)g_currentStage,
            &error);
        if (!error.success) {
            char codeBuf[32];
            snprintf(codeBuf, sizeof(codeBuf), "%d", (int)error.code);
            jstring jCode    = env->NewStringUTF(codeBuf);
            jstring jMessage = env->NewStringUTF(error.message ? error.message : "");
            env->CallStaticVoidMethod(g_dispatcher_class, g_postError,
                handler_ref, sink_ref, jCode, jMessage, nullptr);
            env->DeleteLocalRef(jCode);
            env->DeleteLocalRef(jMessage);
        }
    }

cleanup:
    if (map)         env->DeleteLocalRef(map);
    if (sink_ref)    env->DeleteLocalRef(sink_ref);
    if (handler_ref) env->DeleteLocalRef(handler_ref);
    if (attached)    g_jvm->DetachCurrentThread();
}

static void on_calibrated(clCNFBCalibrator /*calibrator*/, const clCIndividualNFBData* data) noexcept {
    if (!g_jvm || !data) return;

    JNIEnv* env         = nullptr;
    bool    attached    = false;
    jobject sink_ref    = nullptr;
    jobject handler_ref = nullptr;
    jobject dataMap     = nullptr;
    jobject outerMap    = nullptr;

    jint rc = g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
    if (rc == JNI_EDETACHED) {
        if (g_jvm->AttachCurrentThread(&env, nullptr) != JNI_OK) return;
        attached = true;
    } else if (rc != JNI_OK) {
        return;
    }

    pthread_mutex_lock(&g_cal_mutex);
    sink_ref    = g_calibrationSink ? env->NewLocalRef(g_calibrationSink) : nullptr;
    handler_ref = g_handler         ? env->NewLocalRef(g_handler)         : nullptr;
    pthread_mutex_unlock(&g_cal_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    dataMap = make_map(env);
    map_put_long  (env, dataMap, "ts",                              (jlong)data->timestampMilli);
    map_put_int   (env, dataMap, "failReason",                      (jint)data->failReason);
    map_put_float (env, dataMap, "individualFrequency",             (jfloat)data->individualFrequency);
    map_put_float (env, dataMap, "individualPeakFrequency",         (jfloat)data->individualPeakFrequency);
    map_put_float (env, dataMap, "individualPeakFrequencyPower",    (jfloat)data->individualPeakFrequencyPower);
    map_put_float (env, dataMap, "individualPeakFrequencySuppression", (jfloat)data->individualPeakFrequencySuppression);
    map_put_float (env, dataMap, "individualBandwidth",             (jfloat)data->individualBandwidth);
    map_put_float (env, dataMap, "individualNormalizedPower",       (jfloat)data->individualNormalizedPower);
    map_put_float (env, dataMap, "lowerFrequency",                  (jfloat)data->lowerFrequency);
    map_put_float (env, dataMap, "upperFrequency",                  (jfloat)data->upperFrequency);

    outerMap = make_map(env);
    map_put_string(env, outerMap, "type", "done");
    map_put_object(env, outerMap, "data", dataMap);

    env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, outerMap);

cleanup:
    if (outerMap)    env->DeleteLocalRef(outerMap);
    if (dataMap)     env->DeleteLocalRef(dataMap);
    if (sink_ref)    env->DeleteLocalRef(sink_ref);
    if (handler_ref) env->DeleteLocalRef(handler_ref);
    if (attached)    g_jvm->DetachCurrentThread();
}
