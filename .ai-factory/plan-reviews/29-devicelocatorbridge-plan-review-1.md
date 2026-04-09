# Plan Review: DeviceLocatorBridge (Android)

**Plan file:** `.ai-factory/plans/29-devicelocatorbridge.md`
**Reviewed:** 2026-04-09

**Files Referenced:** 6 plan tasks across 6 target files
**Risk Level:** 🟡 Medium

## Context Gates

- **ARCHITECTURE.md:** PASS — plan follows the layered bridge pattern (NativeBridge centralizes JNI declarations, DeviceLocatorBridge owns the handle and StreamHandler logic). One bridge per C API module respected.
- **RULES.md:** WARN — file does not exist, no convention violations possible.
- **ROADMAP.md:** PASS — plan targets the next unchecked Android bridges milestone ("DeviceLocatorBridge"). Scope matches the roadmap description exactly.

## Critical Issues

### 1. Missing step: rename JNI function for `nativeGetVersion` in `jni_bridge.cpp`

Task 2 moves `external fun nativeGetVersion(): String` from `NeiryKitPlugin` to `NativeBridge`. Task 6 removes the declaration from `NeiryKitPlugin`. But neither task mentions updating `jni_bridge.cpp`, where the JNI function is currently named:

```c
Java_com_neiry_neiry_1kit_NeiryKitPlugin_nativeGetVersion(JNIEnv* env, jobject)
```

This must be renamed to:

```c
Java_com_neiry_neiry_1kit_NativeBridge_nativeGetVersion(JNIEnv* env, jobject)
```

Without this, calling `getVersionString` at runtime throws `UnsatisfiedLinkError` and crashes the plugin. Add an explicit sub-step to Task 3 or Task 4 (since it touches the same `.cpp` / CMake layer): "Rename `Java_com_neiry_neiry_1kit_NeiryKitPlugin_nativeGetVersion` to `Java_com_neiry_neiry_1kit_NativeBridge_nativeGetVersion` in `jni_bridge.cpp`."

### 2. Runnable creation from JNI is under-specified and fragile

Task 3's "Sink dispatch helper" section describes building a `Runnable` in C/JNI, posting it via `Handler.post`, then calling `eventSink.success(data)` from inside the Runnable. Creating an anonymous Runnable from C requires:
- FindClass a concrete Runnable-implementing class
- Constructing it with the data and sink as constructor params
- Managing global refs for the captured data (local refs die on DetachCurrentThread)

This is the most error-prone part of the entire JNI layer and the plan doesn't specify how the Runnable is actually constructed or how captured data refs survive thread detachment.

**Recommendation:** Define a Kotlin-side dispatcher class with `@JvmStatic` methods callable from JNI:

```kotlin
object SinkDispatcher {
    @JvmStatic
    fun postSuccess(handler: Handler, sink: Any?, data: Any?) {
        handler.post { (sink as? EventChannel.EventSink)?.success(data) }
    }
    @JvmStatic
    fun postError(handler: Handler, sink: Any?, code: String, message: String, details: Any?) {
        handler.post {
            (sink as? EventChannel.EventSink)?.error(code, message, details)
            (sink as? EventChannel.EventSink)?.endOfStream()
        }
    }
    @JvmStatic
    fun postEndOfStream(handler: Handler, sink: Any?) {
        handler.post { (sink as? EventChannel.EventSink)?.endOfStream() }
    }
}
```

The C callback then calls these via JNI reflection — no Runnable construction needed, no ref lifecycle issues (data objects are held by the JVM stack during the JNI call, then captured by Handler.post's lambda). This matches notes/11's recommendation: "Use Kotlin-side `Handler.post { }` in the JNI callback wrapper class. Keeps C code simpler."

### 3. Local ref survival across DetachCurrentThread not addressed

In `on_device_list_callback`, `marshal_device_list` creates an `ArrayList<HashMap>` as local refs. The plan then posts this data via `Handler.post` and calls `DetachCurrentThread`. Local refs are freed when the thread detaches — but the posted Runnable hasn't executed yet (it runs asynchronously on the main thread).

If the Runnable captures the data as a Java field reference (via the Runnable's constructor), the GC keeps the underlying object alive. But if the data is only held as a JNI local ref and passed to `Handler.post` in the same JNI frame, the ref table is cleared on detach and the object may be collected before the Runnable runs.

The plan must either:
- Convert marshaled data to a global ref before posting, and delete it inside the Runnable (complex)
- Use the Kotlin dispatcher approach above, which calls `Handler.post` from Kotlin where Java-side references are naturally managed (simple)

## Suggestions

### 4. Redundant device handle storage in Task 6

Task 6 says: `"createDevice"` → call `bridge.createDevice(serial)`, **store handle in `DeviceLocatorBridge.devices`**, `result.success(null)`.

But Task 5 already defines `createDevice` as storing the result in `devices[serial]`. The Task 6 description should just say "call `bridge.createDevice(serial)`, `result.success(null)`" — the storage is internal to the bridge. Minor wording issue, but could confuse the implementer into adding duplicate storage code.

### 5. `nativeSetDeviceListSink` parameter type

The plan declares `external fun nativeSetDeviceListSink(sink: Any?)`. Since this always receives an `EventChannel.EventSink?`, using the concrete type provides better safety at Kotlin call sites. The JNI side sees `jobject` regardless of the declared Kotlin type.

## Positive Notes

- The three-phase structure (shared infra → JNI C layer → Kotlin bridge + wiring) is well-organized and creates clean commit boundaries.
- Behavioral parity with iOS `DeviceLocatorBridge.swift` is thoroughly specified — the plan references the exact same guard checks, error codes, and callback patterns.
- Mutex + `goto cleanup` pattern for C callback thread safety is correct and defensive. DetachCurrentThread on all return paths is explicitly called out.
- Correct identification that `clCDeviceInfo_GetType` (not `GetDeviceType`) is the right C function — verified against `CDeviceInfo.h:52`.
- `FindClass` paths correctly noted as using literal `neiry_kit` (not `neiry_1kit`) — the `_1` encoding only applies to `Java_` function name prefixes, not class lookup strings.
- Error encoding as `"<code>|<message>"` with split-on-first-`|` is a pragmatic JNI boundary crossing pattern that preserves the SDK error code for Dart-side `NeiryErrorCode` mapping.
- NativeBridge as instance-per-plugin (not singleton) correctly avoids state leakage across hot restarts.
