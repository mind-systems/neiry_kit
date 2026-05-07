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
extern void     map_put_object(JNIEnv* env, jobject map, const char* key, jobject val);
extern void     map_put_int(JNIEnv* env, jobject map, const char* key, jint val);

// ─── Error helper (defined in jni_device_locator.cpp) ─────────────────────────

extern void throw_sdk_error(JNIEnv* env, const clCError* error);

// ─── File-private MEMS state ──────────────────────────────────────────────────

static jobject         g_memsDataSink = nullptr;
static pthread_mutex_t g_mems_mutex   = PTHREAD_MUTEX_INITIALIZER;

// ─── Callback forward declaration ────────────────────────────────────────────

static void on_mems_data(clCMEMS, clCMEMSTimedData memsData) noexcept;

// ─── JNI functions ────────────────────────────────────────────────────────────

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeCreateMems(
    JNIEnv* env, jobject, jlong deviceHandle)
{
    clCDevice dev = (clCDevice)(uintptr_t)deviceHandle;
    clCError error = {};
    clCMEMS mems = clCMEMS_Create(dev, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }

    clCError e1 = {};
    clCMEMS_SetOnMEMSTimedDataUpdateEvent(mems, on_mems_data, &e1);
    if (!e1.success) { throw_sdk_error(env, &e1); return 0; }

    return (jlong)(uintptr_t)mems;
}

JNIEXPORT jlong JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeCreateMemsCalibrated(
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
    clCMEMS mems = clCMEMS_CreateCalibrated(dev, calibrator, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }

    clCError e1 = {};
    clCMEMS_SetOnMEMSTimedDataUpdateEvent(mems, on_mems_data, &e1);
    if (!e1.success) { throw_sdk_error(env, &e1); return 0; }

    return (jlong)(uintptr_t)mems;
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetMemsDataSink(
    JNIEnv* env, jobject, jobject sink)
{
    pthread_mutex_lock(&g_mems_mutex);
    if (g_memsDataSink) {
        env->DeleteGlobalRef(g_memsDataSink);
        g_memsDataSink = nullptr;
    }
    if (sink != nullptr) {
        g_memsDataSink = env->NewGlobalRef(sink);
    }
    pthread_mutex_unlock(&g_mems_mutex);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeDisposeMems(
    JNIEnv* env, jobject, jlong memsHandle)
{
    if (memsHandle == 0) return;
    clCMEMS mems = (clCMEMS)(uintptr_t)memsHandle;

    clCError error = {};
    clCMEMS_SetOnMEMSTimedDataUpdateEvent(mems, nullptr, &error);

    pthread_mutex_lock(&g_mems_mutex);
    if (g_memsDataSink) {
        env->DeleteGlobalRef(g_memsDataSink);
        g_memsDataSink = nullptr;
    }
    pthread_mutex_unlock(&g_mems_mutex);
}

} // extern "C"

// ─── Callbacks ────────────────────────────────────────────────────────────────

static void on_mems_data(clCMEMS /*mems*/, clCMEMSTimedData memsData) noexcept {
    if (!g_jvm || !memsData) return;

    JNIEnv* env         = nullptr;
    bool    attached    = false;
    jobject sink_ref    = nullptr;
    jobject handler_ref = nullptr;
    jobject list        = nullptr;

    jint rc = g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
    if (rc == JNI_EDETACHED) {
        if (g_jvm->AttachCurrentThread(&env, nullptr) != JNI_OK) return;
        attached = true;
    } else if (rc != JNI_OK) {
        return;
    }

    pthread_mutex_lock(&g_mems_mutex);
    sink_ref    = g_memsDataSink ? env->NewLocalRef(g_memsDataSink) : nullptr;
    handler_ref = g_handler       ? env->NewLocalRef(g_handler)      : nullptr;
    pthread_mutex_unlock(&g_mems_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    {
        int32_t count = clCMEMSTimedData_GetCount(memsData);

        jclass    alClass = env->FindClass("java/util/ArrayList");
        jmethodID alCtor  = env->GetMethodID(alClass, "<init>", "()V");
        jmethodID alAdd   = env->GetMethodID(alClass, "add", "(Ljava/lang/Object;)Z");
        list              = env->NewObject(alClass, alCtor);
        env->DeleteLocalRef(alClass);

        for (int32_t i = 0; i < count; ++i) {
            clCPoint3d acc  = clCMEMSTimedData_GetAccelerometer(memsData, i);
            clCPoint3d gyro = clCMEMSTimedData_GetGyroscope(memsData, i);
            jlong      tsMs = (jlong)clCMEMSTimedData_GetTimestampMilli(memsData, i);

            jobject sample = make_map(env);
            map_put_float(env, sample, "ax", (jfloat)acc.x);
            map_put_float(env, sample, "ay", (jfloat)acc.y);
            map_put_float(env, sample, "az", (jfloat)acc.z);
            map_put_float(env, sample, "gx", (jfloat)gyro.x);
            map_put_float(env, sample, "gy", (jfloat)gyro.y);
            map_put_float(env, sample, "gz", (jfloat)gyro.z);
            map_put_long (env, sample, "ts", tsMs);
            env->CallBooleanMethod(list, alAdd, sample);
            env->DeleteLocalRef(sample);
        }

        env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, list);
    }

cleanup:
    if (list)        env->DeleteLocalRef(list);
    if (sink_ref)    env->DeleteLocalRef(sink_ref);
    if (handler_ref) env->DeleteLocalRef(handler_ref);
    if (attached)    g_jvm->DetachCurrentThread();
}
