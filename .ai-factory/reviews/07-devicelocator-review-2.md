## Code Review: 07-devicelocator (iteration 2)

**Plan:** DeviceLocator Dart API class
**Files reviewed:** `lib/src/api/device_locator.dart` (new), `lib/src/channel/channel_names.dart` (modified), `lib/neiry_kit.dart` (modified), `test/channel_names_test.dart` (modified)
**Risk Level:** 🟢 Low

### Verification

- `flutter test` — 118/118 pass, 0 failures
- `flutter analyze` — no issues

### Review-1 Issue Resolution

All 3 issues from review-1 are resolved:

1. ~~Test compilation failure~~ — Fixed. `DeviceLocatorMethods` test list (line 120–127) updated: removed `requestDevices`, added `create`, `createDevice`, `dispose`, `update`. `NeiryArgs.logDirectory` added to uniqueness list (line 197).
2. ~~Unhandled errored Future~~ — Fixed. Constructor's `.catchError` no longer re-throws. Error stored in `_createError` field (line 44); `_nativeReady` always completes normally (line 70–72). New `_checkReady()` method (line 87–91) throws `StateError` when `_createError` is set, called after `await _nativeReady` in `createDevice`, `setSingleThreaded`, `update`. `dispose` checks `_createError` and skips native destroy when creation failed (line 209–213).
3. ~~Unnecessary `.then((_) {})`~~ — Fixed. `.catchError` chains directly on `invokeMethod<void>` (line 37–46).

### Plan Conformance

**Task 1 — channel contract:**
- `DeviceLocatorMethods`: `create`, `createDevice`, `dispose`, `update` added; `requestDevices` removed — matches plan ✓
- `NeiryArgs.logDirectory` added — matches plan ✓
- `DeviceMethods.createDevice` left in place — matches plan ✓

**Task 2 — DeviceLocator class:**
- Singleton factory with private constructor + `_instance` ✓
- `_nativeReady` failure recovery stores error in `_createError`, nulls `_instance` ✓
- `static const _channel` (MethodChannel) and `static const _deviceListEventChannel` (EventChannel) ✓
- `_checkNotDisposed()` called first in every public method ✓
- `requestDevices`: does NOT await `_nativeReady`; FIFO ordering documented in doc comment (lines 105–112); uses `StreamController` with synchronous `thisSub` capture; cancel-on-overlap; `identical()` guard in `clearIfCurrent()`; `onDone`/`onCancel` wired correctly ✓
- `createDevice`: awaits `_nativeReady`, calls `_checkReady()`, routes through `NeiryChannels.deviceLocator` (not `device`) ✓
- `setSingleThreaded`: awaits `_nativeReady`, calls `_checkReady()` ✓
- `update`: awaits `_nativeReady`, calls `_checkReady()`, no Dart-side enforcement of single-threaded mode ✓
- `dispose`: sets `_disposed = true` immediately, awaits scan cancel, awaits `_nativeReady`, checks `_createError` before native destroy, nulls `_instance`, returns `Future<void>` ✓

**Task 3 — barrel export:**
- `export 'src/api/device_locator.dart';` at top of `neiry_kit.dart`, above model exports ✓

### Critical Issues

None.

### Suggestions

None.

### Positive Notes

- The `_createError` pattern cleanly eliminates the unhandled Future problem without changing the public API. `_nativeReady` always completes normally, and the error surfaces predictably through `_checkReady()` only when a method actually needs the native handle.
- The `dispose` flow correctly distinguishes between "create failed" (skip destroy, early return) and "create succeeded" (send destroy, then null instance). Both paths null `_instance`.
- `controller.isClosed` guards on data/error/done callbacks (lines 140, 148, 152) prevent post-close errors if cancel and data delivery race.
- The FIFO ordering doc comment on `requestDevices` (lines 105–112) is thorough and will save future readers from introducing an incorrect `await _nativeReady` "fix".
- Dependency rules respected: `device_locator.dart` imports only from `channel/` and `models/`.

REVIEW_PASS
