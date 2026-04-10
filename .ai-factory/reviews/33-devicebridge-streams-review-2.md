# Code Review: DeviceBridge — streams (iteration 2)

**Plan:** `.ai-factory/plans/33-devicebridge-streams.md`
**Files reviewed:** `jni_device.cpp`, `jni_device_locator.cpp`, `NativeBridge.kt`, `DeviceBridge.kt`, `NeiryKitPlugin.kt`

## Critical Issues

### 1. `on_resistance_data` uses `s_stringClass` before cache is initialised

**File:** `jni_device.cpp:1119`

`s_stringClass` is initialised inside `init_map_cache()`, which is called only from `nativeRegisterDeviceCallbacks`. If the resistance callback fires before `nativeRegisterDeviceCallbacks` has executed (race on fast connect), `s_stringClass` is `nullptr` and `NewObjectArray` crashes:

```cpp
channelNames = env->NewObjectArray(count, s_stringClass, nullptr);  // ← s_stringClass may be null
```

All other heavy callbacks (EEG, PSD, artifacts) reach `s_stringClass` only through `make_map`, which is safe because the cache is always initialised before `make_map` is ever reachable — but `on_resistance_data` accesses `s_stringClass` directly, bypassing that guarantee.

**Fix:** Add `init_map_cache(env);` at the top of `on_resistance_data` after acquiring `env`, or move the `init_map_cache` call from `nativeRegisterDeviceCallbacks` into `JNI_OnLoad` so the cache is always ready before any callback can fire.

### 2. `nativeSetDeviceStreamSink` hardcodes slot 0 — inconsistent with `find_device_slot`

**File:** `jni_device.cpp:557`

```cpp
jobject old = g_device_slots[0].sinks[streamType];
```

`nativeRegisterDeviceCallbacks` uses `register_device_slot` which can assign any of the `MAX_DEVICES` (4) slots. If slot 0 is already occupied by another device, the sink lands in slot 0 while SDK callbacks resolve the real device to a different slot — stream data silently drops. The comment says "plugin supports one device at a time" but nothing in `register_device_slot` enforces this.

**Fix:** Either reduce `MAX_DEVICES` to 1 so slot 0 is always the active device, or look up the slot via `find_device_slot` inside `nativeSetDeviceStreamSink` (requires storing the current device handle somewhere accessible).

## Observations (non-blocking)

- **`on_eeg_data` — `buf` unallocated when `sampleCount == 0`.** `buf` is only allocated when `sampleCount > 0`, but the subsequent `SetFloatArrayRegion` call is guarded by the same condition, so `buf` is never dereferenced when null. Not a live crash, but the pattern is fragile — PSD handles this more clearly by always pairing allocation and use inside the same `if (freqCount > 0)` block.
- **Double `delete[] buf` in PSD.** In `on_psd_data`, `buf` is explicitly deleted (and nulled) twice inside the function body, then `delete[] buf` runs again in `cleanup`. This is correct (`delete[] nullptr` is a no-op), but the three-location ownership makes the logic hard to audit. Consolidating to a single `delete[]` in `cleanup` would be cleaner.
- **Map key parity:** All 8 stream map shapes (keys, types, nesting) match iOS and the Dart `fromMap` factories exactly.
- **`goto cleanup` pattern:** `NewLocalRef` under mutex, `DetachCurrentThread` on all paths — correctly follows the pattern established in `jni_device_locator.cpp`.
- **PSD individual alpha/beta:** Hard-bail on `Has*` check failure, soft-error sentinel (-1) on accessor failure — matches iOS exactly.
- **Resistance:** Correctly omits `clCError*` for `GetCount`, `GetChannelName`, `GetValue` — verified against C headers.
- **Both fixes from review 1 confirmed:** `unregister_device_slot` only clears the device pointer (sinks survive device replacement); `nativeRegisterDeviceCallbacks` has `if (handle == 0) return;`.
