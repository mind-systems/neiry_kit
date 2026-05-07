## Plan Review: firmwareVersion getter — Dart + iOS + Android

**Risk Level:** Low

### Context Gates

- **ARCHITECTURE.md:** WARN — no issues. Plan follows the established layered bridge architecture: channel constant -> Dart API -> native bridges. One bridge class per C API module is respected.
- **RULES.md:** file does not exist — WARN (non-blocking).
- **ROADMAP.md:** OK — milestone "firmwareVersion getter — Dart + iOS + Android" is explicitly listed under "SDK v2.0.72 upgrade" (line 55). Plan is a direct implementation of that milestone.

### SDK Function Verification

Confirmed `clCDevice_GetFirmwareVersion` exists in vendored headers:
```c
CL_DLL const char* clCDevice_GetFirmwareVersion(clCDevice device, clCError* error) NOEXCEPT;
```
Signature matches the plan's stated contract exactly.

### Task-by-Task Validation

**Task 1 — `DeviceMethods` constant:** Placement after `getChannelsCount` (line 102) is correct. No issues.

**Task 2 — Dart `Device.getFirmwareVersion()`:** Guards (`_checkNotDisposed`, `_checkConnected`) and invocation pattern are consistent with existing async getters. Using `invokeMethod<String>` directly (like `getChannelName`) is the correct approach for a `String` result. Arguments `{NeiryArgs.serial: serial}` are sufficient (no extra params needed). No issues.

**Task 3 — iOS `DeviceBridge.swift` + `NeiryKitPlugin.swift`:**
- Bridge method follows the `getEEGSampleRate()` pattern with the necessary additional nil-guard for the `const char*` return type — consistent with `getChannelNameByIndex()` (line 548-561) which also nil-guards a C string pointer.
- Dispatch in `NeiryKitPlugin.swift` placed before `default:` in `handleDeviceCall` switch — correct location (currently at line 307).
- do/catch pattern matches existing cases.
- No issues.

**Task 4 — JNI `nativeGetFirmwareVersion` in `jni_device.cpp`:**
- Placement in "Getters" section after `nativeGetPPGRedAmplitude` (ends at line 356) is correct.
- Pattern matches existing getters: cast handle, call C function, check error, return.
- Returns `jstring` via `env->NewStringUTF(result ? result : "")` — null-guard prevents passing nullptr to JNI, consistent with the `nativeGetChannelNameByIndex` function (line 460) which uses the same pattern.
- No issues.

**Task 5 — Kotlin `NativeBridge.kt` + `DeviceBridge.kt` + `NeiryKitPlugin.kt`:**
- `external fun nativeGetFirmwareVersion(handle: Long): String` placement after `nativeGetPPGRedAmplitude` (line 54) is correct.
- `DeviceBridge.getFirmwareVersion()` using `requireHandle()` + try/catch + `parseSdkError()` matches `getBatteryCharge()` pattern (line 181-188) exactly.
- Plugin dispatch `"getFirmwareVersion" -> result.success(bridge.getFirmwareVersion())` in the `when` block after `"getBatteryCharge"` (line 218) is correct and follows existing patterns.
- No issues.

### Critical Issues

None.

### Positive Notes

- Plan correctly identifies that `const char*` return from C requires a nil-guard on both platforms (iOS: `guard result`, Android: `result ? result : ""`), unlike numeric getters.
- All file paths verified against the actual codebase — every referenced file, section, and line range is accurate.
- Follows established patterns consistently across all three layers with no shortcuts or deviations.
- Scope is appropriately minimal — no unnecessary changes.

PLAN_REVIEW_PASS
