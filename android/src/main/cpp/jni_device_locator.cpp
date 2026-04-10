#include <jni.h>
#include <pthread.h>
#include <cstdio>
#include "CCapsuleAPI.h"

// ─── Global state ─────────────────────────────────────────────────────────────

JavaVM*   g_jvm              = nullptr;
jobject   g_handler          = nullptr;  // android.os.Handler (main looper), global ref
static jobject   g_deviceListSink   = nullptr;  // EventChannel.EventSink, global ref

static pthread_mutex_t g_callback_mutex = PTHREAD_MUTEX_INITIALIZER;

// ─── Cached JNI IDs for SinkDispatcher ───────────────────────────────────────

jclass    g_dispatcher_class = nullptr;  // global ref
jmethodID g_postSuccess      = nullptr;
jmethodID g_postError        = nullptr;
static jmethodID g_postEndOfStream  = nullptr;

// ─── Error helper ─────────────────────────────────────────────────────────────

void throw_sdk_error(JNIEnv* env, const clCError* error) {
    char encoded[512];
    snprintf(encoded, sizeof(encoded), "%d|%s", (int)error->code, error->message);
    jclass cls = env->FindClass("java/lang/RuntimeException");
    if (cls) env->ThrowNew(cls, encoded);
}

// ─── Device list marshaling ───────────────────────────────────────────────────

static jobject marshal_device_list(JNIEnv* env, clCDeviceInfoList list) {
    jclass    alClass = env->FindClass("java/util/ArrayList");
    jmethodID alCtor  = env->GetMethodID(alClass, "<init>", "()V");
    jmethodID alAdd   = env->GetMethodID(alClass, "add", "(Ljava/lang/Object;)Z");
    jobject   result  = env->NewObject(alClass, alCtor);
    env->DeleteLocalRef(alClass);

    if (!list) return result;

    clCError countErr = {};
    int32_t count = clCDeviceInfoList_GetCount(list, &countErr);
    if (!countErr.success) return result;

    jclass    hmClass = env->FindClass("java/util/HashMap");
    jmethodID hmCtor  = env->GetMethodID(hmClass, "<init>", "()V");
    jmethodID hmPut   = env->GetMethodID(hmClass, "put",
                            "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");

    jclass    intClass = env->FindClass("java/lang/Integer");
    jmethodID intOf    = env->GetStaticMethodID(intClass, "valueOf", "(I)Ljava/lang/Integer;");

    // Reuse key strings across all iterations
    jstring kSerial = env->NewStringUTF("serial");
    jstring kName   = env->NewStringUTF("name");
    jstring kType   = env->NewStringUTF("type");

    for (int32_t i = 0; i < count; ++i) {
        clCError ie = {};
        clCDeviceInfo info = clCDeviceInfoList_GetDeviceInfo(list, i, &ie);
        if (!ie.success || !info) continue;

        const char* s = clCDeviceInfo_GetSerial(info);
        const char* n = clCDeviceInfo_GetName(info);
        jint        t = (jint)clCDeviceInfo_GetType(info);

        jobject map     = env->NewObject(hmClass, hmCtor);
        jstring serialJ = env->NewStringUTF(s ? s : "");
        jstring nameJ   = env->NewStringUTF(n ? n : "");
        jobject typeJ   = env->CallStaticObjectMethod(intClass, intOf, t);

        env->CallObjectMethod(map, hmPut, kSerial, serialJ);
        env->CallObjectMethod(map, hmPut, kName,   nameJ);
        env->CallObjectMethod(map, hmPut, kType,   typeJ);
        env->CallBooleanMethod(result, alAdd, map);

        env->DeleteLocalRef(map);
        env->DeleteLocalRef(serialJ);
        env->DeleteLocalRef(nameJ);
        env->DeleteLocalRef(typeJ);
    }

    env->DeleteLocalRef(kSerial);
    env->DeleteLocalRef(kName);
    env->DeleteLocalRef(kType);
    env->DeleteLocalRef(hmClass);
    env->DeleteLocalRef(intClass);

    return result;
}

// ─── Device list callback ─────────────────────────────────────────────────────

static void on_device_list_callback(
    clCDeviceLocator /*locator*/,
    clCDeviceInfoList list,
    clCDeviceLocator_FailReason failReason) noexcept
{
    if (!g_jvm) return;

    JNIEnv* env   = nullptr;
    bool attached  = false;

    jint rc = g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
    if (rc == JNI_EDETACHED) {
        if (g_jvm->AttachCurrentThread(&env, nullptr) != JNI_OK) return;
        attached = true;
    } else if (rc != JNI_OK) {
        return;
    }

    // Promote globals to local refs under the mutex so we hold an independent
    // ref count that survives a concurrent DeleteGlobalRef on the Flutter thread.
    pthread_mutex_lock(&g_callback_mutex);
    jobject sink_ref    = g_deviceListSink ? env->NewLocalRef(g_deviceListSink) : nullptr;
    jobject handler_ref = g_handler        ? env->NewLocalRef(g_handler)        : nullptr;
    pthread_mutex_unlock(&g_callback_mutex);

    if (sink_ref) {
        if (failReason != clCDeviceLocator_FailReason_OK) {
            const char* code    = (failReason == clCDeviceLocator_FailReason_BluetoothDisabled)
                                  ? "1" : "255";
            const char* message = (failReason == clCDeviceLocator_FailReason_BluetoothDisabled)
                                  ? "Bluetooth is disabled"
                                  : "Unknown error during device search";
            jstring jCode    = env->NewStringUTF(code);
            jstring jMessage = env->NewStringUTF(message);
            env->CallStaticVoidMethod(g_dispatcher_class, g_postError,
                handler_ref, sink_ref, jCode, jMessage, nullptr);
            env->DeleteLocalRef(jCode);
            env->DeleteLocalRef(jMessage);
        } else {
            jobject deviceArray = marshal_device_list(env, list);
            env->CallStaticVoidMethod(g_dispatcher_class, g_postSuccess,
                handler_ref, sink_ref, deviceArray);
            env->CallStaticVoidMethod(g_dispatcher_class, g_postEndOfStream,
                handler_ref, sink_ref);
            env->DeleteLocalRef(deviceArray);
        }
    }

    if (sink_ref)    env->DeleteLocalRef(sink_ref);
    if (handler_ref) env->DeleteLocalRef(handler_ref);

    if (attached) g_jvm->DetachCurrentThread();
}

// ─── JNI functions ────────────────────────────────────────────────────────────

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeCreateLocator(
    JNIEnv* env, jobject, jstring logDir)
{
    env->GetJavaVM(&g_jvm);

    // Create Handler(Looper.getMainLooper()) once — survives for the process lifetime
    if (!g_handler) {
        jclass    looperClass  = env->FindClass("android/os/Looper");
        jmethodID getMain      = env->GetStaticMethodID(looperClass, "getMainLooper",
                                     "()Landroid/os/Looper;");
        jobject   mainLooper   = env->CallStaticObjectMethod(looperClass, getMain);
        jclass    handlerClass = env->FindClass("android/os/Handler");
        jmethodID handlerCtor  = env->GetMethodID(handlerClass, "<init>",
                                     "(Landroid/os/Looper;)V");
        jobject   handlerLocal = env->NewObject(handlerClass, handlerCtor, mainLooper);
        g_handler = env->NewGlobalRef(handlerLocal);
        env->DeleteLocalRef(handlerLocal);
        env->DeleteLocalRef(mainLooper);
        env->DeleteLocalRef(looperClass);
        env->DeleteLocalRef(handlerClass);
    }

    // Cache SinkDispatcher class + method IDs once
    if (!g_dispatcher_class) {
        jclass local = env->FindClass("com/neiry/neiry_kit/SinkDispatcher");
        g_dispatcher_class = (jclass)env->NewGlobalRef(local);
        env->DeleteLocalRef(local);

        g_postSuccess = env->GetStaticMethodID(g_dispatcher_class, "postSuccess",
            "(Landroid/os/Handler;Ljava/lang/Object;Ljava/lang/Object;)V");
        g_postError = env->GetStaticMethodID(g_dispatcher_class, "postError",
            "(Landroid/os/Handler;Ljava/lang/Object;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Object;)V");
        g_postEndOfStream = env->GetStaticMethodID(g_dispatcher_class, "postEndOfStream",
            "(Landroid/os/Handler;Ljava/lang/Object;)V");
    }

    clCError error = {};
    clCDeviceLocator locator = nullptr;

    if (logDir != nullptr) {
        const char* dir = env->GetStringUTFChars(logDir, nullptr);
        locator = clCDeviceLocator_CreateWithLogDirectory(dir, &error);
        env->ReleaseStringUTFChars(logDir, dir);
    } else {
        locator = clCDeviceLocator_Create(&error);
    }

    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }

    return (jlong)(uintptr_t)locator;
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeDestroyLocator(
    JNIEnv* env, jobject, jlong handle)
{
    if (handle == 0) return;

    pthread_mutex_lock(&g_callback_mutex);
    if (g_deviceListSink) {
        env->DeleteGlobalRef(g_deviceListSink);
        g_deviceListSink = nullptr;
    }
    pthread_mutex_unlock(&g_callback_mutex);

    clCDeviceLocator locator = (clCDeviceLocator)(uintptr_t)handle;
    clCDeviceLocator_Destroy(locator);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetDeviceListSink(
    JNIEnv* env, jobject, jobject sink)
{
    pthread_mutex_lock(&g_callback_mutex);
    if (g_deviceListSink) {
        env->DeleteGlobalRef(g_deviceListSink);
        g_deviceListSink = nullptr;
    }
    if (sink != nullptr) {
        g_deviceListSink = env->NewGlobalRef(sink);
    }
    pthread_mutex_unlock(&g_callback_mutex);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeRequestDevices(
    JNIEnv* env, jobject, jlong handle, jint deviceType, jint searchTime)
{
    clCDeviceLocator locator = (clCDeviceLocator)(uintptr_t)handle;

    clCDeviceLocator_SetOnDeviceListEvent(locator, on_device_list_callback);

    clCError error = {};
    clCDeviceLocator_RequestDevices(locator, (clCDeviceType)deviceType,
                                    (int32_t)searchTime, &error);
    if (!error.success) {
        throw_sdk_error(env, &error);
    }
}

JNIEXPORT jlong JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeCreateDevice(
    JNIEnv* env, jobject, jlong locatorHandle, jstring serial)
{
    if (locatorHandle == 0) {
        jclass cls = env->FindClass("java/lang/RuntimeException");
        if (cls) env->ThrowNew(cls, "0|DeviceLocator not created");
        return 0;
    }

    clCDeviceLocator locator = (clCDeviceLocator)(uintptr_t)locatorHandle;
    const char* serialStr = env->GetStringUTFChars(serial, nullptr);

    clCError error = {};
    clCDevice device = clCDeviceLocator_CreateDevice(locator, serialStr, &error);

    env->ReleaseStringUTFChars(serial, serialStr);

    if (!error.success) {
        throw_sdk_error(env, &error);
        return 0;
    }

    return (jlong)(uintptr_t)device;
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetSingleThreaded(
    JNIEnv* /*env*/, jobject, jboolean enabled)
{
    clCCapsule_SetSingleThreaded((bool)enabled);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeUpdate(
    JNIEnv* /*env*/, jobject, jlong handle)
{
    if (handle == 0) return;
    clCDeviceLocator locator = (clCDeviceLocator)(uintptr_t)handle;
    clCDeviceLocator_Update(locator);
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetLogLevel(
    JNIEnv* /*env*/, jobject, jint level)
{
    clCCapsule_SetLogLevel((clCCapsule_LogLevel)level);
}

} // extern "C"
