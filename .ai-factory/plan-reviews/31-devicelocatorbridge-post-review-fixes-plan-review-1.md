# Plan Review: DeviceLocatorBridge — post-review fixes

**Files Reviewed:** 5 (plan + 4 source files)
**Risk Level:** 🟢 Low

## Context Gates

- **ARCHITECTURE.md:** WARN — no violations. Plan touches only the Android native bridge layer (`android/src/main/cpp/` and `android/src/main/kotlin/`), consistent with the layered SDK bridge architecture. Threading/dispatch rules are followed.
- **RULES.md:** not present (no file).
- **ROADMAP.md:** WARN — no issues. The plan maps 1:1 to the unchecked milestone "DeviceLocatorBridge — post-review fixes". The `NewLocalRef` pattern established here is already referenced as the required pattern in all subsequent Android bridge milestones (DeviceBridge streams, NfbBridge, EmotionsBridge, PhysioBridge, CardioBridge, ProductivityBridge).

## Verification

### Task 1: JNI callback ref safety (`NewLocalRef`)

**Bug analysis is correct.** Lines 114-117 of `jni_device_locator.cpp` copy raw `jobject` pointers under the mutex. If `nativeSetDeviceListSink(null)` (line 226-234) or `nativeDestroyLocator` (line 210-216) runs concurrently and calls `DeleteGlobalRef`, the raw copies become dangling pointers. The callback then passes them to `CallStaticVoidMethod`, causing a use-after-free.

**Fix is correct.** `NewLocalRef` under the mutex creates an independently ref-counted local reference. Since both the `NewLocalRef` call and the `DeleteGlobalRef` calls are serialized by `g_callback_mutex`, there is no window where `NewLocalRef` is called on a concurrently-freed ref. After the dispatch block, `DeleteLocalRef` cleans up.

**Code snippets verified:**
- The "before" snippet matches the actual code at lines 114-117 exactly.
- The ternary null check (`g_deviceListSink ? env->NewLocalRef(g_deviceListSink) : nullptr`) is correct — `NewLocalRef(nullptr)` would return nullptr anyway per JNI spec, but the explicit check is clearer.
- Cleanup after the dispatch block covers both the happy path (sink_ref non-null) and the early-return path (sink_ref null but handler_ref non-null). The null checks before `DeleteLocalRef` handle all combinations.
- `g_handler` is never deleted in the current code (created once, survives process lifetime), so the use-after-free risk is theoretical for it today. Still, applying `NewLocalRef` is correct defensive programming and matches the pattern the ROADMAP mandates for all future bridges.
- `g_dispatcher_class` (also used in the callback) is a global ref created once and never deleted — no fix needed for it.

### Task 2: `update()` iOS parity

**iOS behavior verified.** `DeviceLocatorBridge.swift` lines 85-90 throw `FlutterError(code: "NO_LOCATOR", ...)` when `locator` is nil. The Android code at `DeviceLocatorBridge.kt` line 59 silently returns instead.

**Fix is correct.** Replacing `return` with `throw FlutterError(...)` matches iOS behavior.

**Error propagation verified.** `NeiryKitPlugin.kt` handles `"update"` at lines 130-133 inside `handleDeviceLocatorCall`, which wraps the entire `when` block in `try { ... } catch (e: FlutterError) { result.error(e.code, e.message, e.details) }` (lines 106-153). The thrown `FlutterError` will be caught and forwarded to Dart as a `PlatformException`.

**JNI layer alignment:** The JNI `nativeUpdate` function (line 290) still has `if (handle == 0) return;`. This is harmless — Kotlin throws before calling JNI, so the JNI guard is just a defensive fallback. No change needed there.

## Critical Issues

None.

## Positive Notes

- Both bugs are real and well-diagnosed with clear root cause analysis.
- The plan includes precise line numbers that match the actual source code.
- The `NewLocalRef` fix is the textbook JNI solution for this class of race condition.
- The cleanup section correctly handles all ref combinations (both null, one null, both non-null).
- The iOS parity fix aligns with the established error contract (`FlutterError` codes + `NeiryKitPlugin` catch pattern).
- The plan is minimal and focused — two surgical fixes, no scope creep.

PLAN_REVIEW_PASS
