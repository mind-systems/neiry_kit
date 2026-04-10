## Plan Review: NfbCalibratorBridge (Android)

**Plan file:** `.ai-factory/plans/35-nfbcalibratorbridge.md`
**Files reviewed:** plan + 15 codebase files (JNI, Kotlin, Swift, C headers, Dart models)
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md** — WARN: Plan aligns with the layered SDK bridge architecture. New bridge follows the one-bridge-per-module principle. No dependency rule violations.
- **RULES.md** — not present (no file).
- **ROADMAP.md** — Plan implements the `NfbCalibratorBridge` milestone under "Android bridges", which is marked `[ ]`. No linkage issues.

### Verification Summary

Every claim in the plan was verified against the actual codebase:

| Claim | Verified against | Result |
|---|---|---|
| `g_postError` is `static` on line 18 of `jni_device_locator.cpp` | `jni_device_locator.cpp:18` | ✅ Correct |
| `g_jvm`, `g_handler`, `g_dispatcher_class`, `g_postSuccess` have external linkage | `jni_device_locator.cpp:8-17` | ✅ All non-static |
| Map helpers (`init_map_cache`, `make_map`, `map_put_*`) are non-static in `jni_device.cpp` | `jni_device.cpp:87-173` | ✅ All non-static |
| `throw_sdk_error` is non-static | `jni_device_locator.cpp:23` | ✅ Correct |
| `jni_nfb.cpp` externs pattern is followed | `jni_nfb.cpp:6-23` | ✅ Plan mirrors it, adding `g_postError` + `map_put_int` + `map_put_object` |
| CMakeLists has 4 sources, plan appends 5th | `CMakeLists.txt:7-12` | ✅ Correct |
| `NativeBridge.kt` sink setter pattern | `NativeBridge.kt:81-82` | ✅ `nativeSetNfbCalibrationSink` follows same signature |
| `NfbBridge.kt` stream handler pattern | `NfbBridge.kt:18-36` | ✅ `CalibrationStreamHandler` mirrors `NfbStreamHandler` |
| `NfbBridge.kt` error parsing pattern | `NfbBridge.kt:46-47, FlutterError.kt:20-27` | ✅ `parseSdkError` reused correctly |
| `DeviceBridge.requireHandle()` exists | `DeviceBridge.kt:83-88` | ✅ Returns device handle or throws `FlutterError` |
| iOS `handleNfbCalibratorCall` dispatch shape | `NeiryKitPlugin.swift:352-398` | ✅ Android plan matches method names, arg keys, error handling |
| iOS teardown order | `NeiryKitPlugin.swift:148` | ✅ Calibrator stopped before classifier disposal |
| `NeiryKitPlugin.kt` stub exists | `NeiryKitPlugin.kt:253-255` | ✅ `handleNfbCalibratorCall` is `result.notImplemented()` stub |
| EventChannel `nfbCalibration` registered | `NeiryKitPlugin.kt:79` | ✅ Already in the event channel list |
| C API signatures: `CreateOrGet`, callbacks, `IsCalibrated` | `CNFBCalibrator.h:76-132` | ✅ All match plan's usage |
| `clCIndividualNFBCalibrationStage` enum 0-indexed | `CNFBCalibrator.h:18-23` | ✅ Stage_1=0 through Stage_4=3 |
| `clCIndividualNFBData` has 10 fields | `CNFBCalibrator.h:31-66` | ✅ All 10 accounted for in plan |
| Dart `CalibrationEvent.deserialize` expects `{"type":"stage","stage":int}` and `{"type":"done","data":{...}}` | `calibration_event.dart:23-39` | ✅ Map format matches |
| Dart `IndividualNfbData.fromMap` expects `ts` (int), `failReason` (int), 8 float fields | `individual_nfb_data.dart:59-84` | ✅ JNI `map_put_long`/`map_put_int`/`map_put_float` produce correct Java types |
| `CalibrationStage.fromCode` expects codes 0–3 | `calibration_stage.dart:30-35` | ✅ `g_currentStage` emitted before increment matches |
| Dart sends `{calibratorData: 'quick'}` for quick mode, null args for full mode | `nfb_calibrator.dart:142,238-239` | ✅ Plan's arg extraction handles both cases |

### Critical Issues

None.

### Recommendations

**1. Add `!g_jvm` early-return guard to both C callbacks**

The established pattern in this codebase (see `jni_nfb.cpp:171`, `jni_nfb.cpp:220`, `jni_device_locator.cpp:99`) is to guard every C callback with `if (!g_jvm) return;` as the first line. The plan's `on_calibration_stage_finished` and `on_calibrated` descriptions jump straight to "Early return if `g_isQuickMode`" and "Attach thread" respectively, without mentioning the `g_jvm` null check.

Add `if (!g_jvm) return;` as the first line of both callbacks for consistency with the established pattern.

**2. Add null-check for `data` pointer in `on_calibrated`**

The C callback signature is `void (*)(clCNFBCalibrator, const clCIndividualNFBData*)` — the data pointer can be null. The iOS code explicitly guards this: `guard let dataPtr = dataPtr else { return }`. The existing `jni_nfb.cpp` also checks `!data` in its state callback (`jni_nfb.cpp:171`).

The plan's `on_calibrated` description proceeds directly to building the data map without null-checking `data`. Add `if (!data) goto cleanup;` after the attach/snapshot block to prevent a null pointer dereference.

### Positive Notes

- Thorough and precise plan — every JNI function, callback, extern declaration, and Kotlin method is specified with exact types and behavior, leaving almost no ambiguity for the implementer.
- Correctly identifies that `g_postError` needs its `static` removed for cross-file error dispatch in the stage callback — subtle linkage detail that's easy to miss.
- Stage tracking with `g_currentStage` + auto-advancement mirrors the iOS implementation exactly, including the quick-mode guard and the re-entry call to `CalibrateIndividualNFB` from within the stage-finished callback.
- Teardown order (calibrator before classifier) correctly matches iOS and the semantic dependency (calibrator feeds into NFB classifier).
- The plan correctly handles the Dart API's two invocation modes (full: no args, quick: `{calibratorData: 'quick'}`) for `startCalibration`.

PLAN_REVIEW_PASS
