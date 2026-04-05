# Explore: Android JNI Bridge Patterns

Research findings for implementing Android JNI bridges in `neiry_kit`. Covers handle management, threading, global references, and data marshaling. Applies to all Android bridge milestones after the build setup spike.

## Architecture summary

The JNI layer sits between Kotlin (Flutter plugin) and the C SDK:

```
Flutter Dart
     ↓ MethodChannel / EventChannel
Kotlin (NeiryKitPlugin + bridge classes)
     ↓ external fun → System.loadLibrary("neiry_jni")
libneiry_jni.so (jni_bridge.cpp + per-domain files)
     ↓ clC* function calls
libCapsuleClient.so (C SDK)
```

C callbacks fire on **background JNI worker threads**. `EventChannel.EventSink` is NOT thread-safe. All emissions must be dispatched to the main thread via `Handler(Looper.getMainLooper()).post { }`.

## JNI naming convention

Package: `com.neiry.neiry_kit`

JNI function name pattern:
```
Java_com_neiry_neiry_1kit_<ClassName>_<methodName>
```

Example for `NativeBridge.nativeGetVersion()`:
```c
JNIEXPORT jstring JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeGetVersion(JNIEnv* env, jobject thiz)
```

Note: `neiry_kit` → `neiry_1kit` (underscore escaped as `_1`).

## Recommended class structure

Single `NativeBridge` class for MVP. All `external fun` declarations live there. Per-domain bridge classes (`DeviceLocatorBridge.kt`, `DeviceBridge.kt` etc.) handle Kotlin-side logic and hold the `Long` handle IDs.

```kotlin
// NativeBridge.kt — all JNI declarations
class NativeBridge {
    companion object {
        init { System.loadLibrary("neiry_jni") }
    }

    external fun nativeCreateLocator(logDir: String?): Long
    external fun nativeDestroyLocator(handle: Long)
    external fun nativeRequestDevices(handle: Long, type: Int, searchTime: Int)
    external fun nativeCreateDevice(locatorHandle: Long, serial: String): Long
    external fun nativeReleaseDevice(handle: Long)
    // ...
}
```

## Handle management

C handles (`clCDeviceLocator`, `clCDevice`, etc.) are opaque pointers. Cast them to `jlong` when crossing the JNI boundary — jlong is 64-bit, same width as a pointer on arm64-v8a.

```c
JNIEXPORT jlong JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeCreateLocator(
    JNIEnv* env, jobject thiz, jstring logDir)
{
    clCError error = {0};
    clCDeviceLocator locator = clCDeviceLocator_Create(&error);
    if (!error.success) {
        jclass ex = (*env)->FindClass(env, "java/lang/RuntimeException");
        (*env)->ThrowNew(env, ex, error.message);
        return 0;
    }
    return (jlong)(uintptr_t)locator;
}

JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeDestroyLocator(
    JNIEnv* env, jobject thiz, jlong handle)
{
    if (handle == 0) return;
    clCDeviceLocator_Destroy((clCDeviceLocator)(uintptr_t)handle);
}
```

Kotlin stores the returned `Long` as a field:

```kotlin
class DeviceLocatorBridge(private val bridge: NativeBridge) {
    private var handle: Long = 0L

    fun create(logDir: String?) {
        handle = bridge.nativeCreateLocator(logDir)
    }

    fun dispose() {
        if (handle != 0L) {
            bridge.nativeDestroyLocator(handle)
            handle = 0L
        }
    }
}
```

## C callback → EventChannel threading

C callbacks fire on a JNI worker thread. To reach `EventSink.success()` safely:

1. Store `JavaVM*` at init time (call `GetJavaVM` in `JNI_OnLoad` or first JNI call)
2. Store `EventSink` jobject as a **global reference**
3. In callback: `AttachCurrentThread` → build map → `Handler.post` → `DetachCurrentThread`

```c
static JavaVM* g_jvm = NULL;
static jobject g_sink_global = NULL;   // global ref to EventSink
static jobject g_handler_global = NULL; // global ref to Handler(main looper)

// Called from Kotlin to register the sink before starting scan
JNIEXPORT void JNICALL
Java_com_neiry_neiry_1kit_NativeBridge_nativeSetDeviceListSink(
    JNIEnv* env, jobject thiz, jobject sink)
{
    if (g_sink_global != NULL) (*env)->DeleteGlobalRef(env, g_sink_global);
    g_sink_global = sink != NULL ? (*env)->NewGlobalRef(env, sink) : NULL;
}

// C SDK callback (background thread)
static void on_device_list(clCDeviceLocator locator, clCDeviceInfoList list, ...) {
    JNIEnv* env = NULL;
    (*g_jvm)->AttachCurrentThread(g_jvm, &env, NULL);

    if (g_sink_global != NULL) {
        jobject data = marshal_device_list(env, list);  // build map/array
        // Post to main thread
        jclass handler_class = (*env)->GetObjectClass(env, g_handler_global);
        jmethodID post = (*env)->GetMethodID(env, handler_class, "post", "(Ljava/lang/Runnable;)Z");
        jobject runnable = make_sink_runnable(env, g_sink_global, data);
        (*env)->CallBooleanMethod(env, g_handler_global, post, runnable);
        (*env)->DeleteLocalRef(env, data);
        (*env)->DeleteLocalRef(env, runnable);
        (*env)->DeleteLocalRef(env, handler_class);
    }

    (*g_jvm)->DetachCurrentThread(g_jvm);
}
```

A simpler alternative when you can tolerate slightly more Kotlin glue: return the raw data from JNI and let Kotlin post it:

```kotlin
// Kotlin-side callback interface
interface DeviceListCallback {
    fun onDeviceList(devices: List<Map<String, Any>>)
}

// Register in Kotlin, call from C via JNI reflection
nativeSetDeviceListCallback(object : DeviceListCallback {
    override fun onDeviceList(devices: List<Map<String, Any>>) {
        Handler(Looper.getMainLooper()).post {
            eventSink?.success(devices)
        }
    }
})
```

**Recommendation:** Use Kotlin-side `Handler.post { }` in the JNI callback wrapper class. Keeps C code simpler; threading logic in Kotlin where it's easier to read.

## Global reference lifecycle

| Situation | Action |
|---|---|
| Store EventSink for callbacks | `NewGlobalRef` on onListen, `DeleteGlobalRef` on onCancel |
| Store Handler(mainLooper) | `NewGlobalRef` once at init, keep for app lifetime |
| Data passed to `Handler.post` runnable | Local ref in the runnable lambda — auto-cleaned |
| Returning jobject from JNI function | Caller receives local ref; caller must not store without `NewGlobalRef` |

Rule: every `NewGlobalRef` must have a matching `DeleteGlobalRef`. Leak = memory leak that won't show until repeated scans.

## C callback context — no void* param problem

Most C SDK callbacks have no user context parameter:

```c
typedef void (*clCDevice_ConnectionStatusChangedHandler)(
    clCDevice device, clCDevice_ConnectionStatus status) NOEXCEPT;
```

Solution: static device registry keyed by C handle pointer.

```c
#define MAX_DEVICES 4
static clCDevice g_devices[MAX_DEVICES] = {0};
static jobject  g_device_sinks[MAX_DEVICES] = {0}; // global refs to EventSinks

static int find_device_slot(clCDevice device) {
    for (int i = 0; i < MAX_DEVICES; i++)
        if (g_devices[i] == device) return i;
    return -1;
}

static void on_connection_status(clCDevice device, clCDevice_ConnectionStatus status) {
    int slot = find_device_slot(device);
    if (slot < 0 || g_device_sinks[slot] == NULL) return;
    // emit to g_device_sinks[slot] via Handler.post
}
```

This is the same pattern as iOS where the bridge stores per-device state in a static map.

## Data marshaling

### C struct → Kotlin Map (preferred pattern)

Build a `HashMap<String, Any>` in C and return it as `jobject`. Flutter platform channels accept Java Maps natively.

```c
static jobject make_map(JNIEnv* env) {
    jclass cls = (*env)->FindClass(env, "java/util/HashMap");
    return (*env)->NewObject(env, cls,
        (*env)->GetMethodID(env, cls, "<init>", "()V"));
}

static void map_put_long(JNIEnv* env, jobject map, const char* key, jlong val) {
    jclass map_cls = (*env)->GetObjectClass(env, map);
    jmethodID put = (*env)->GetMethodID(env, map_cls, "put",
        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
    jclass long_cls = (*env)->FindClass(env, "java/lang/Long");
    jobject boxed = (*env)->NewObject(env, long_cls,
        (*env)->GetMethodID(env, long_cls, "<init>", "(J)V"), val);
    (*env)->CallObjectMethod(env, map,
        put, (*env)->NewStringUTF(env, key), boxed);
}
// similarly: map_put_float, map_put_bool, map_put_string
```

### Bool fields with float initializers

`clCCardio_Data` bool fields are initialized to `0.F` in the header (SDK bug). Read them normally in JNI:

```c
(jboolean)(data->hasArtifacts != 0)  // cast float literal 0.F → false
```

### PPG accessor pattern

PPG data uses getter functions, not direct struct access (same as iOS):

```c
int32_t count = clCPPGTimedData_GetCount(ppgData);
for (int32_t i = 0; i < count; i++) {
    float val = clCPPGTimedData_GetValue(ppgData, i);
    uint64_t ts  = clCPPGTimedData_GetTimestampMilli(ppgData, i);
    // build array element
}
```

### Channel names (two-step accessor — same as iOS)

```c
clCDevice_ChannelNames names = clCDevice_GetChannelNames(device, &error);
int32_t count = clCDevice_ChannelNames_GetChannelsCount(names, &error);
for (int32_t i = 0; i < count; i++) {
    const char* name = clCDevice_ChannelNames_GetChannelNameByIndex(names, i, &error);
}
```

### Opaque byte blobs (Physio baselines)

`clCPhysiologicalStates_Baselines` is a C struct (NOT opaque). Serialize it as a map of 6 floats, same as the iOS bridge. Do NOT pass as raw bytes.

## onDetachedFromEngine cleanup checklist

Called on app close and hot restart. All C resources must be released:

1. Call `setStreamHandler(null)` on all EventChannels — triggers `onCancel` → sink global refs deleted
2. Stop all active device operations (`stop`, `disconnect`)
3. Release device handles: `clCDevice_Release` for each active device
4. Destroy locator: `clCDeviceLocator_Destroy`
5. Delete remaining global refs (Handler, any static sinks)
6. Zero out all static handle storage

Order matters: devices depend on locator — release devices before locator.

## CMakeLists.txt shape

```cmake
cmake_minimum_required(VERSION 3.18)
project(neiry_jni)

set(CAPSULE_LIBS "${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/arm64-v8a")
set(CAPSULE_HEADERS "${CMAKE_CURRENT_SOURCE_DIR}/../../../../official/iOS/CapsuleClient.framework/Headers")

add_library(neiry_jni SHARED
    jni_bridge.cpp
    device_locator_bridge.cpp
    device_bridge.cpp
)

target_include_directories(neiry_jni PRIVATE ${CAPSULE_HEADERS})

target_link_libraries(neiry_jni
    ${CAPSULE_LIBS}/libCapsuleClient.so
    ${CAPSULE_LIBS}/libc++_shared.so
    android
    log
)
```

Link `android` (for `Handler` support) and `log` (for `__android_log_print`).

## Logging in C code

```c
#include <android/log.h>
#define LOG_TAG "neiry_jni"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
```

## Resolved

1. **`clCDeviceLocator_Update()` on Android:** `CDeviceLocator.h:37–38` documents: "to work in this mode, `clCDeviceLocator_Update` must be called periodically on the main thread." This is **single-threaded mode only** — same rule as iOS. By default the SDK is multi-threaded; `Update()` is a no-op unless `SetSingleThreaded(true)` was called. JNI bridge should expose `nativeUpdate(handle)` but it's only needed when single-threaded mode is explicitly enabled.
2. **`NativeBridge` singleton vs instance:** Use **instance-per-plugin** (regular class, not singleton companion object). `NeiryKitPlugin.onAttachedToEngine` creates the instance; `onDetachedFromEngine` releases it. Singleton would leak state across hot restarts.
3. **`JNI_OnLoad` conflict:** `nm -D libCapsuleClient.so | grep JNI_OnLoad` → **found at `0xe9207c`**. The SDK defines its own `JNI_OnLoad`. Do NOT define a second `JNI_OnLoad` in `neiry_jni.so` — only one can be active per `.so`. Instead, use `RegisterNatives` inside a regular C init function called from Kotlin, or rely on the `Java_...` naming convention which doesn't require `JNI_OnLoad` at all. The `Java_com_neiry_neiry_1kit_...` naming is the correct approach — no `JNI_OnLoad` needed in `jni_bridge.cpp`.
