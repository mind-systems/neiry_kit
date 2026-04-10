# Code Review: DeviceBridge — streams

**Plan:** `.ai-factory/plans/33-devicebridge-streams.md`
**Files reviewed:** `jni_device.cpp`, `jni_device_locator.cpp`, `NativeBridge.kt`, `DeviceBridge.kt`, `NeiryKitPlugin.kt`, `DeviceBridge.swift` (iOS reference)

## Critical Issues

### 1. `unregister_device_slot` destroys sinks — breaks device replacement

**File:** `jni_device.cpp:63-74`

`unregister_device_slot` deletes all 8 sink global refs when clearing a device slot:

```cpp
static void unregister_device_slot(JNIEnv* env, int slot) {
    ...
    for (int s = 0; s < STREAM_COUNT; ++s) {
        if (g_device_slots[slot].sinks[s]) {
            env->DeleteGlobalRef(g_device_slots[slot].sinks[s]);  // ← destroys sinks
            g_device_slots[slot].sinks[s] = nullptr;
        }
    }
    ...
}
```

This function is called from `nativeUnregisterDeviceCallbacks`, which is called by `DeviceBridge.setDevice()` when replacing a device:

```kotlin
fun setDevice(serial: String, handle: Long) {
    val old = this.handle
    if (old != 0L && old != handle) {
        nativeBridge.nativeUnregisterDeviceCallbacks(old)  // destroys sinks!
        nativeBridge.nativeReleaseDevice(old)
    }
    this.handle = handle
    ...
    nativeBridge.nativeRegisterDeviceCallbacks(handle)     // new device, but sinks are gone
}
```

**What breaks:** When Dart calls `createDevice` a second time (reconnection, switching devices), `setDevice` replaces the old handle. The unregister call destroys all sink global refs. After the new device is registered, SDK callbacks fire but find null sinks in slot 0 — all stream data is silently dropped. The Dart side still has active `StreamSubscription`s, but the native side has lost its references to the EventChannel sinks. Data won't flow until Dart unsubscribes and re-subscribes on every stream, which it has no reason to do.

**iOS comparison:** iOS `unregisterCallbacks()` (line 372-385) only clears the 8 SDK callbacks and sets `activeBridge = nil`. It does NOT touch the EventChannel sinks — they are owned by the `DeviceStreamHandler` instances on the Swift object and survive device replacement.

**Fix:** Remove the sink deletion loop from `unregister_device_slot`. The function should only clear the device pointer:

```cpp
static void unregister_device_slot(JNIEnv* /*env*/, int slot) {
    if (slot < 0 || slot >= MAX_DEVICES) return;
    pthread_mutex_lock(&g_device_mutex);
    g_device_slots[slot].device = nullptr;
    pthread_mutex_unlock(&g_device_mutex);
}
```

Sink lifecycle is already managed by `nativeSetDeviceStreamSink` (called from `onListen`/`onCancel`). On engine teardown, `onDetachedFromEngine` calls `channel.setStreamHandler(null)` for every EventChannel, which triggers `onCancel`, which calls `nativeSetDeviceStreamSink(type, null)`, which deletes the global ref. So sinks are always cleaned up — just not tied to device registration.

### 2. `nativeRegisterDeviceCallbacks` missing `handle == 0` guard

**File:** `jni_device.cpp:521-535`

`nativeUnregisterDeviceCallbacks` has `if (handle == 0) return;` (line 541), but `nativeRegisterDeviceCallbacks` does not. If called with handle=0:

1. `register_device_slot(nullptr)` — `find_device_slot(nullptr)` matches any empty slot (device==nullptr), returns slot 0. The slot's device field stays nullptr (set to nullptr). No new slot is actually claimed.
2. `clCDevice_SetOnEEGDataEvent(nullptr, callback)` — undefined behavior, likely crash.

Not triggered in practice (Kotlin guarantees non-zero handles from the SDK), but inconsistent with `nativeUnregisterDeviceCallbacks`.

**Fix:** Add `if (handle == 0) return;` at the start of `nativeRegisterDeviceCallbacks`.

## Observations (non-blocking)

- **Map key parity:** All 8 stream map shapes (keys, types, nesting) match iOS exactly. Battery, error, connectionStatus, mode use identical single-key maps. EEG 5 keys, PSD 19 keys, artifacts 4 keys, resistance 3 keys — all verified against `DeviceBridge.swift` and the Dart `fromMap` factories.
- **Callback pattern:** `goto cleanup` with `NewLocalRef` under mutex, `DetachCurrentThread` on all paths — correctly follows the post-review pattern established in `jni_device_locator.cpp`.
- **PSD individual alpha/beta:** Hard-bail on `HasIndividualAlpha` check failure, soft-error sentinel (-1) on accessor failure — matches iOS exactly.
- **Resistance no-`clCError*`:** Correctly omits error checking for `GetCount`, `GetChannelName`, `GetValue` — verified against C headers.
- **EventChannel registration in `NeiryKitPlugin`:** Clean `buildMap` + lookup pattern replaces the previous `when` block with `StubStreamHandler` fallback. All 8 channel IDs match `NeiryEvents` constants in Dart.
