# Plan Review: DeviceBridge — streams (Review 2)

**Plan file:** `.ai-factory/plans/33-devicebridge-streams.md`
**Files reviewed:** `jni_device.cpp`, `jni_device_locator.cpp`, `NativeBridge.kt`, `DeviceBridge.kt`, `NeiryKitPlugin.kt`, `DeviceLocatorBridge.kt`, `FlutterError.kt`, `CMakeLists.txt`, `DeviceBridge.swift` (iOS reference), Dart models (`eeg_data.dart`, `psd_data.dart`, `eeg_artifact_data.dart`, `resistance_data.dart`, `device.dart`, `channel_names.dart`), C SDK headers (`CDevice.h`, `CEEGTimedData.h`, `CPSDData.h`, `CEEGArtifacts.h`, `CResistances.h`)
**Risk Level:** 🟢 Low

## Context Gates

- **ARCHITECTURE.md:** OK — plan follows the layered bridge architecture. All `external fun` on `NativeBridge` (centralized). Platform bridges don't cross-call. EventChannel-per-data-source pattern preserved. Thread-safe main-thread dispatch via `SinkDispatcher.postSuccess`.
- **RULES.md:** not present, skipped.
- **ROADMAP.md:** OK — plan maps directly to the `DeviceBridge — streams` milestone under Android bridges. All 8 EventChannel IDs, map key shapes, and error-handling semantics match the already-completed iOS `DeviceBridge — streams` milestone.

## Review of Prior Critical Issues (from Review 1)

Both critical issues identified in review 1 have been resolved in the updated plan:

1. **`static` linkage / linker error** — Plan now explicitly lists `jni_device_locator.cpp` in Task 1's file list and instructs to remove `static` from the 4 shared globals (`g_jvm`, `g_handler`, `g_dispatcher_class`, `g_postSuccess`) so they have external linkage. The remaining globals (`g_deviceListSink`, `g_callback_mutex`, `g_postError`, `g_postEndOfStream`) correctly stay `static`. Verified against `jni_device_locator.cpp` lines 8-19. **Fixed.**

2. **Missing `nativeUnregisterDeviceCallbacks(old)` in `setDevice()`** — Plan now explicitly specifies calling `nativeUnregisterDeviceCallbacks(old)` before `nativeReleaseDevice(old)` in the `old != 0L && old != handle` branch. Also specifies the same unregister-before-release order in `release()`. Both match iOS `DeviceBridge.swift` lines 113-114 / 125-129. **Fixed.**

## Critical Issues

None.

## Verification Details

### C SDK callback signatures (verified against CDevice.h)
All 8 callback typedefs match the plan's forward declarations:
- `clCDevice_EEGDataHandler(clCDevice, clCEEGTimedData)` — `on_eeg_data` ✓
- `clCDevice_PSDDataHandler(clCDevice, clCPSDData)` — `on_psd_data` ✓
- `clCDevice_EEGArtifactsHandler(clCDevice, clCEEGArtifacts)` — `on_artifacts_data` ✓
- `clCDevice_OnResistanceUpdateHandler(clCDevice, clCResistance)` — `on_resistance_data` ✓
- `clCDevice_OnBatteryChargeUpdateHandler(clCDevice, uint8_t)` — `on_battery_data` ✓
- `clCDevice_ErrorHandler(clCDevice, const char*)` — `on_error_data` ✓
- `clCDevice_ConnectionStatusChangedHandler(clCDevice, clCDevice_ConnectionStatus)` — `on_connection_status_changed` ✓
- `clCDevice_ModeSwitchedHandler(clCDevice, clCDevice_Mode)` — `on_mode_switched` ✓

### Map keys vs Dart models (verified against fromMap factories)
- **Battery:** `{"charge": int}` — matches `device.dart` battery decoder ✓
- **Error:** `{"message": String}` — matches `device.dart` error decoder ✓
- **Connection status:** `{"state": int}` — matches `device.dart` → `NeiryConnectionState.fromCode()` ✓
- **Mode:** `{"mode": int}` — matches `device.dart` → `NeiryDeviceMode.fromCode()` ✓
- **EEG (5 keys):** `ts`/`rawValues`/`processedValues`/`channelCount`/`sampleCount` — matches `EegData.fromMap` ✓
- **PSD (19 keys):** `ts`/`values`/`frequencies`/`channelCount`/`frequencyCount` + 10 band bounds + 4 individual alpha/beta — matches `PsdData.fromMap` ✓
- **Artifacts (4 keys):** `ts`/`artifacts`/`qualities`/`channelCount` — matches `EegArtifactData.fromMap` ✓
- **Resistance (3 keys):** `channelNames`/`values`/`channelCount` — matches `ResistanceData.fromMap` ✓

### EventChannel IDs (verified against channel_names.dart)
All 8 channel IDs in Task 2's `allStreamHandlers()` match `NeiryEvents` constants:
`neiry_kit/events/eeg`, `psd`, `eegArtifacts`, `resistance`, `battery`, `error`, `connectionStatus`, `modeSwitched` ✓

### C SDK accessor error semantics (verified against headers)
- `clCResistance_GetCount`, `GetChannelName`, `GetValue` — no `clCError*` parameter ✓
- `clCPSDData_HasIndividualAlpha/Beta` — takes `clCError*`, hard bail on failure ✓
- `clCPSDData_GetIndividualAlpha/BetaLower/Upper` — takes `clCError*`, soft error → emit `-1` sentinel ✓
- All EEG, PSD, artifacts accessors — take `clCError*`, bail on failure ✓

### Thread safety patterns
- `NewLocalRef` under mutex for sink access in callbacks (not raw pointer copy) — matches the post-review fix pattern established in `jni_device_locator.cpp` ✓
- `goto cleanup` with `DetachCurrentThread` on all return paths ✓
- `pthread_mutex_t` guards all sink global refs in the device registry ✓

### Build configuration
`jni_device.cpp` is already in `CMakeLists.txt`'s `add_library` directive — no build changes needed ✓

## Positive Notes

- **Both review 1 issues cleanly resolved.** The static linkage fix is now the very first step in Task 1, and the unregister-before-release order is explicitly documented with a reference to the iOS line number. Clear evidence the author understood the root cause of both issues.
- **Excellent iOS parity.** All 8 map shapes, error-handling strategies, and key names match `DeviceBridge.swift` exactly. The PSD individual alpha/beta hard-bail vs soft-error distinction, resistance no-`clCError*` pattern, and `Int64(bitPattern:)` → `(jlong)ts` equivalence are all correctly specified.
- **Sound device registry design.** The static `DeviceSlot` array with `MAX_DEVICES = 4` is the right solution for C callbacks with no context parameter. Single-device assumption (slot 0) is well-documented and consistent with the plugin's single-device constraint in ARCHITECTURE.md.
- **Learned patterns applied consistently.** `NewLocalRef` under mutex, `goto cleanup`, `DetachCurrentThread` on all paths — all patterns from the DeviceLocatorBridge post-review fixes are correctly applied here.
- **Clean Kotlin-side design.** `DeviceStreamHandler` inner class with a single `nativeSetDeviceStreamSink` JNI function (dispatching by `streamType` int) is cleaner than having 8 separate JNI functions. The `allStreamHandlers()` pattern mirrors iOS and plugs cleanly into `NeiryKitPlugin`'s EventChannel registration loop.

PLAN_REVIEW_PASS
