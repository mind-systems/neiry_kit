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
extern void     map_put_string(JNIEnv* env, jobject map, const char* key, const char* val);

// ─── Error helper (defined in jni_device_locator.cpp) ─────────────────────────

extern void throw_sdk_error(JNIEnv* env, const clCError* error);

// ─── File-private Emotions state ──────────────────────────────────────────────

static jobject         g_emotionsStateSink = nullptr;
static jobject         g_emotionsErrorSink = nullptr;
static pthread_mutex_t g_emotions_mutex    = PTHREAD_MUTEX_INITIALIZER;

// ─── Callback forward declarations ────────────────────────────────────────────

static void on_emotions_state_changed(clCEmotions, const clCEmotions_States*) noexcept;
static void on_emotions_error(clCEmotions, const char*) noexcept;

// ─── JNI functions ────────────────────────────────────────────────────────────

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeCreateEmotions(
    JNIEnv* env, jobject, jlong deviceHandle)
{
    clCDevice dev = (clCDevice)(uintptr_t)deviceHandle;
    clCError error = {};
    clCEmotions emotions = clCEmotions_Create(dev, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }
    clCEmotions_SetOnEmotionalStatesUpdateEvent(emotions, on_emotions_state_changed);
    clCEmotions_SetOnErrorEvent(emotions, on_emotions_error);
    return (jlong)(uintptr_t)emotions;
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetEmotionsStateSink(
    JNIEnv* env, jobject, jobject sink)
{
    pthread_mutex_lock(&g_emotions_mutex);
    if (g_emotionsStateSink) {
        env->DeleteGlobalRef(g_emotionsStateSink);
        g_emotionsStateSink = nullptr;
    }
    if (sink != nullptr) {
        g_emotionsStateSink = env->NewGlobalRef(sink);
    }
    pthread_mutex_unlock(&g_emotions_mutex);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetEmotionsErrorSink(
    JNIEnv* env, jobject, jobject sink)
{
    pthread_mutex_lock(&g_emotions_mutex);
    if (g_emotionsErrorSink) {
        env->DeleteGlobalRef(g_emotionsErrorSink);
        g_emotionsErrorSink = nullptr;
    }
    if (sink != nullptr) {
        g_emotionsErrorSink = env->NewGlobalRef(sink);
    }
    pthread_mutex_unlock(&g_emotions_mutex);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeDisposeEmotions(
    JNIEnv* env, jobject, jlong emotionsHandle)
{
    if (emotionsHandle == 0) return;
    clCEmotions emotions = (clCEmotions)(uintptr_t)emotionsHandle;

    clCEmotions_SetOnEmotionalStatesUpdateEvent(emotions, nullptr);
    clCEmotions_SetOnErrorEvent(emotions, nullptr);

    pthread_mutex_lock(&g_emotions_mutex);
    if (g_emotionsStateSink) {
        env->DeleteGlobalRef(g_emotionsStateSink);
        g_emotionsStateSink = nullptr;
    }
    if (g_emotionsErrorSink) {
        env->DeleteGlobalRef(g_emotionsErrorSink);
        g_emotionsErrorSink = nullptr;
    }
    pthread_mutex_unlock(&g_emotions_mutex);
}

} // extern "C"

// ─── Callbacks ────────────────────────────────────────────────────────────────

static void on_emotions_state_changed(clCEmotions /*emotions*/, const clCEmotions_States* data) noexcept {
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

    pthread_mutex_lock(&g_emotions_mutex);
    sink_ref    = g_emotionsStateSink ? env->NewLocalRef(g_emotionsStateSink) : nullptr;
    handler_ref = g_handler           ? env->NewLocalRef(g_handler)           : nullptr;
    pthread_mutex_unlock(&g_emotions_mutex);

    if (!sink_ref || !handler_ref) goto cleanup;

    map = make_map(env);
    map_put_long (env, map, "ts",               (jlong)data->timestampMilli);
    map_put_float(env, map, "attention",         (jfloat)data->attention);
    map_put_float(env, map, "relaxation",        (jfloat)data->relaxation);
    map_put_float(env, map, "cognitiveLoad",     (jfloat)data->cognitiveLoad);
    map_put_float(env, map, "cognitiveControl",  (jfloat)data->cognitiveControl);
    map_put_float(env, map, "selfControl",       (jfloat)data->selfControl);
    env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess, handler_ref, sink_ref, map);

cleanup:
    if (map)         env->DeleteLocalRef(map);
    if (sink_ref)    env->DeleteLocalRef(sink_ref);
    if (handler_ref) env->DeleteLocalRef(handler_ref);
    if (attached)    g_jvm->DetachCurrentThread();
}

static void on_emotions_error(clCEmotions /*emotions*/, const char* message) noexcept {
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

    pthread_mutex_lock(&g_emotions_mutex);
    sink_ref    = g_emotionsErrorSink ? env->NewLocalRef(g_emotionsErrorSink) : nullptr;
    handler_ref = g_handler           ? env->NewLocalRef(g_handler)           : nullptr;
    pthread_mutex_unlock(&g_emotions_mutex);

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
