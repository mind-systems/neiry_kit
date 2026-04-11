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

extern jobject  make_map(JNIEnv* env);
extern void     map_put_float(JNIEnv* env, jobject map, const char* key, jfloat val);
extern void     map_put_long(JNIEnv* env, jobject map, const char* key, jlong val);
extern void     map_put_bool(JNIEnv* env, jobject map, const char* key, jboolean val);
extern void     map_put_int(JNIEnv* env, jobject map, const char* key, jint val);
extern void     map_put_object(JNIEnv* env, jobject map, const char* key, jobject val);

// ─── Error helper (defined in jni_device_locator.cpp) ─────────────────────────

extern void throw_sdk_error(JNIEnv* env, const clCError* error);

// ─── File-private Cardio state ────────────────────────────────────────────────

static jobject         g_cardioStateSink      = nullptr;
static jobject         g_cardioPpgSink        = nullptr;
static jobject         g_cardioCalibratedSink = nullptr;
static pthread_mutex_t g_cardio_mutex = PTHREAD_MUTEX_INITIALIZER;

// ─── Callback forward declarations ────────────────────────────────────────────

static void on_cardio_indexes_update(clCCardio, const clCCardio_Data*) noexcept;
static void on_cardio_ppg_data(clCCardio, clCPPGTimedData) noexcept;
static void on_cardio_calibrated(clCCardio) noexcept;

// ─── JNI functions ────────────────────────────────────────────────────────────

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeCreateCardio(
    JNIEnv* env, jobject, jlong deviceHandle)
{
    clCDevice dev = (clCDevice)(uintptr_t)deviceHandle;
    clCError error = {};
    clCCardio cardio = clCCardio_Create(dev, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }

    clCError e1 = {};
    clCCardio_SetOnIndexesUpdateEvent(cardio, on_cardio_indexes_update, &e1);
    if (!e1.success) { throw_sdk_error(env, &e1); return 0; }

    clCError e2 = {};
    clCCardio_SetOnPPGDataEvent(cardio, on_cardio_ppg_data, &e2);
    if (!e2.success) { throw_sdk_error(env, &e2); return 0; }

    clCError e3 = {};
    clCCardio_SetOnCalibratedEvent(cardio, on_cardio_calibrated, &e3);
    if (!e3.success) { throw_sdk_error(env, &e3); return 0; }

    return (jlong)(uintptr_t)cardio;
}

JNIEXPORT jlong JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeCreateCardioCalibrated(
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

        clCError importError = {};
        clCNFBCalibrator_ImportIndividualNFBData(calibrator, &data, &importError);
        if (!importError.success) {
            throw_sdk_error(env, &importError);
            return 0;
        }
    }

    clCError error = {};
    clCCardio cardio = clCCardio_CreateCalibrated(dev, calibrator, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }

    clCError e1 = {};
    clCCardio_SetOnIndexesUpdateEvent(cardio, on_cardio_indexes_update, &e1);
    if (!e1.success) { throw_sdk_error(env, &e1); return 0; }

    clCError e2 = {};
    clCCardio_SetOnPPGDataEvent(cardio, on_cardio_ppg_data, &e2);
    if (!e2.success) { throw_sdk_error(env, &e2); return 0; }

    clCError e3 = {};
    clCCardio_SetOnCalibratedEvent(cardio, on_cardio_calibrated, &e3);
    if (!e3.success) { throw_sdk_error(env, &e3); return 0; }

    return (jlong)(uintptr_t)cardio;
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetCardioStateSink(
    JNIEnv* env, jobject, jobject sink)
{
    pthread_mutex_lock(&g_cardio_mutex);
    if (g_cardioStateSink) {
        env->DeleteGlobalRef(g_cardioStateSink);
        g_cardioStateSink = nullptr;
    }
    if (sink != nullptr) {
        g_cardioStateSink = env->NewGlobalRef(sink);
    }
    pthread_mutex_unlock(&g_cardio_mutex);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetCardioPpgSink(
    JNIEnv* env, jobject, jobject sink)
{
    pthread_mutex_lock(&g_cardio_mutex);
    if (g_cardioPpgSink) {
        env->DeleteGlobalRef(g_cardioPpgSink);
        g_cardioPpgSink = nullptr;
    }
    if (sink != nullptr) {
        g_cardioPpgSink = env->NewGlobalRef(sink);
    }
    pthread_mutex_unlock(&g_cardio_mutex);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetCardioCalibratedSink(
    JNIEnv* env, jobject, jobject sink)
{
    pthread_mutex_lock(&g_cardio_mutex);
    if (g_cardioCalibratedSink) {
        env->DeleteGlobalRef(g_cardioCalibratedSink);
        g_cardioCalibratedSink = nullptr;
    }
    if (sink != nullptr) {
        g_cardioCalibratedSink = env->NewGlobalRef(sink);
    }
    pthread_mutex_unlock(&g_cardio_mutex);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeDisposeCardio(
    JNIEnv* env, jobject, jlong cardioHandle)
{
    if (cardioHandle == 0) return;
    clCCardio cardio = (clCCardio)(uintptr_t)cardioHandle;

    clCError e = {};
    clCCardio_SetOnIndexesUpdateEvent(cardio, nullptr, &e);
    clCCardio_SetOnPPGDataEvent(cardio, nullptr, &e);
    clCCardio_SetOnCalibratedEvent(cardio, nullptr, &e);

    pthread_mutex_lock(&g_cardio_mutex);
    if (g_cardioStateSink) {
        env->DeleteGlobalRef(g_cardioStateSink);
        g_cardioStateSink = nullptr;
    }
    if (g_cardioPpgSink) {
        env->DeleteGlobalRef(g_cardioPpgSink);
        g_cardioPpgSink = nullptr;
    }
    if (g_cardioCalibratedSink) {
        env->DeleteGlobalRef(g_cardioCalibratedSink);
        g_cardioCalibratedSink = nullptr;
    }
    pthread_mutex_unlock(&g_cardio_mutex);
}

} // extern "C"

// ─── Callbacks ────────────────────────────────────────────────────────────────

static void on_cardio_indexes_update(clCCardio /*cardio*/, const clCCardio_Data* data) noexcept {
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

    pthread_mutex_lock(&g_cardio_mutex);
    sink_ref    = g_cardioStateSink ? env->NewLocalRef(g_cardioStateSink) : nullptr;
    handler_ref = g_handler         ? env->NewLocalRef(g_handler)         : nullptr;
    pthread_mutex_unlock(&g_cardio_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    map = make_map(env);
    map_put_long (env, map, "ts",              (jlong)data->timestampMilli);
    map_put_float(env, map, "heartRate",        (jfloat)data->heartRate);
    map_put_float(env, map, "stressIndex",      (jfloat)data->stressIndex);
    map_put_float(env, map, "kaplanIndex",      (jfloat)data->kaplanIndex);
    map_put_bool (env, map, "hasArtifacts",     (jboolean)(data->hasArtifacts != 0));
    map_put_bool (env, map, "skinContact",      (jboolean)(data->skinContact != 0));
    map_put_bool (env, map, "motionArtifacts",  (jboolean)(data->motionArtifacts != 0));
    map_put_bool (env, map, "metricsAvailable", (jboolean)(data->metricsAvailable != 0));
    env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map);

cleanup:
    if (map)         env->DeleteLocalRef(map);
    if (sink_ref)    env->DeleteLocalRef(sink_ref);
    if (handler_ref) env->DeleteLocalRef(handler_ref);
    if (attached)    g_jvm->DetachCurrentThread();
}

static void on_cardio_ppg_data(clCCardio /*cardio*/, clCPPGTimedData ppgData) noexcept {
    if (!g_jvm || !ppgData) return;

    JNIEnv*     env         = nullptr;
    bool        attached    = false;
    jobject     sink_ref    = nullptr;
    jobject     handler_ref = nullptr;
    jobject     map         = nullptr;
    jfloatArray values      = nullptr;
    jlongArray  timestamps  = nullptr;

    jint rc = g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
    if (rc == JNI_EDETACHED) {
        if (g_jvm->AttachCurrentThread(&env, nullptr) != JNI_OK) return;
        attached = true;
    } else if (rc != JNI_OK) {
        return;
    }

    pthread_mutex_lock(&g_cardio_mutex);
    sink_ref    = g_cardioPpgSink ? env->NewLocalRef(g_cardioPpgSink) : nullptr;
    handler_ref = g_handler        ? env->NewLocalRef(g_handler)       : nullptr;
    pthread_mutex_unlock(&g_cardio_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    {
        int32_t count = clCPPGTimedData_GetCount(ppgData);

        values     = env->NewFloatArray(count);
        timestamps = env->NewLongArray(count);

        jfloat* valueBuf = new jfloat[count];
        jlong*  tsBuf    = new jlong[count];
        for (int i = 0; i < count; ++i) {
            valueBuf[i] = (jfloat)clCPPGTimedData_GetValue(ppgData, i);
            tsBuf[i]    = (jlong)clCPPGTimedData_GetTimestampMilli(ppgData, i);
        }
        env->SetFloatArrayRegion(values, 0, count, valueBuf);
        env->SetLongArrayRegion(timestamps, 0, count, tsBuf);
        delete[] valueBuf;
        delete[] tsBuf;

        map = make_map(env);
        map_put_int   (env, map, "sampleCount", (jint)count);
        map_put_object(env, map, "values",      values);
        map_put_object(env, map, "timestamps",  timestamps);
        env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map);
    }

cleanup:
    if (values)      env->DeleteLocalRef(values);
    if (timestamps)  env->DeleteLocalRef(timestamps);
    if (map)         env->DeleteLocalRef(map);
    if (sink_ref)    env->DeleteLocalRef(sink_ref);
    if (handler_ref) env->DeleteLocalRef(handler_ref);
    if (attached)    g_jvm->DetachCurrentThread();
}

static void on_cardio_calibrated(clCCardio /*cardio*/) noexcept {
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

    pthread_mutex_lock(&g_cardio_mutex);
    sink_ref    = g_cardioCalibratedSink ? env->NewLocalRef(g_cardioCalibratedSink) : nullptr;
    handler_ref = g_handler               ? env->NewLocalRef(g_handler)               : nullptr;
    pthread_mutex_unlock(&g_cardio_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    map = make_map(env);
    env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map);

cleanup:
    if (map)         env->DeleteLocalRef(map);
    if (sink_ref)    env->DeleteLocalRef(sink_ref);
    if (handler_ref) env->DeleteLocalRef(handler_ref);
    if (attached)    g_jvm->DetachCurrentThread();
}
