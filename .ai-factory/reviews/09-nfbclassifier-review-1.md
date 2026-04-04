## Code Review: 09-nfbclassifier

**Files reviewed:** 3 changed (`channel_names.dart`, `nfb_classifier.dart`, `neiry_kit.dart`) + 5 reference (`device.dart`, `device_locator.dart`, `nfb_user_state.dart`, `individual_nfb_data.dart`, `04-dart-api-classifiers.md`)
**Static analysis:** `flutter analyze` — no issues found

### Changes Summary

1. **`channel_names.dart`** — added `ClassifierMethods.dispose` constant
2. **`nfb_classifier.dart`** — new file, 158 lines, implements `NfbClassifier`
3. **`neiry_kit.dart`** — barrel export for the new classifier

### Verification Against Plan

All three tasks implemented as specified:

- **Task 1 (ClassifierMethods.dispose):** `static const String dispose = 'dispose';` added at line 104. Positioned between `createCalibrated` and `startBaselineCalibration` — correct alphabetical placement within the class.

- **Task 2 (NfbClassifier class):**
  - `device.isStarted` guard in factory constructor (line 43) — satisfies ARCHITECTURE.md anti-pattern rule ✅
  - `.catchError()` on `_nativeReady` with `_createError` field (lines 52-68) — matches DeviceLocator pattern ✅
  - `_checkReady()` guard before stream access (lines 106-110, called in getters at lines 128, 135) ✅
  - `dispose()` awaits `_nativeReady`, checks `_createError` before native destroy (lines 145-157) ✅
  - `_eventStream` helper matches Device's implementation exactly ✅
  - All channel/method/arg constants verified against `channel_names.dart` ✅
  - `IndividualNfbData.toMap()` returns `Map<String, dynamic>` — call is valid ✅
  - `NfbUserState.fromMap` signature `(Map<Object?, Object?>)` matches `_eventStream` decode parameter ✅

- **Task 3 (barrel export):** Export added at line 1, before `device.dart`. Alphabetically correct within the `src/api/` group — API exports remain together.

### Correctness Checks

**Error handling lifecycle:** Complete and consistent with DeviceLocator. The `.catchError()` ensures `_nativeReady` always completes normally, preventing unhandled Future errors. `_checkReady()` guards stream access. `dispose()` skips native destroy when creation failed. No code paths leave dangling native handles.

**FIFO ordering:** `_stateStream` and `_errorStream` are `late final` — the `receiveBroadcastStream()` call fires lazily on first access. The platform thread FIFO guarantees the `create` MethodChannel call (sent during construction) completes before the EventChannel `onListen` message arrives. This matches DeviceLocator's documented guarantee (device_locator.dart lines 107-113).

**Dispose idempotency:** The `if (_disposed) return` guard at line 146 prevents double-destroy. After dispose, stream getters throw `StateError` via `_checkNotDisposed()`. Active stream listeners continue receiving in-flight events until the native side tears down — consistent with Device's dispose behavior.

**Type safety:** `.catchError((Object error) { _createError = error; })` on `Future<void>` — the callback returns void (implicitly null), matching the Future's type parameter. Correct.

**Import completeness:** All 6 imports are used. `dart:async` is technically redundant (Stream/Future re-exported from dart:core) but matches Device's import list — consistent.

### Critical Issues

None.

### Suggestions

None.

### Positive Notes

- Clean implementation that follows both the DeviceLocator error-handling pattern and Device stream pattern without unnecessary additions.
- The `_eventStream` helper is appropriately duplicated (5 lines) rather than over-extracted into a shared utility.
- Doc comments on the class and factory are helpful without being excessive — the lifecycle section explains the FIFO guarantee clearly.
- No unused code, no dead imports, no unnecessary null checks.

REVIEW_PASS
