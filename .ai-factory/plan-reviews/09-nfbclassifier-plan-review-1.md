## Plan Review: 09-nfbclassifier

**Files Reviewed:** 7 (plan + channel_names.dart, device.dart, device_locator.dart, neiry_kit.dart, nfb_user_state.dart, individual_nfb_data.dart, 04-dart-api-classifiers.md)
**Risk Level:** 🟡 Medium

### Context Gates

- **ARCHITECTURE.md:** WARN — plan violates the anti-pattern "Starting classifiers before `clCDevice_Start` — enforce this in the Dart API". The constructor does not guard against an un-started device.
- **RULES.md:** file not present — WARN (non-blocking).
- **ROADMAP.md:** plan aligns with the `NfbClassifier` milestone under "Dart API". No linkage issues.

### Critical Issues

**1. Missing error handling on `_createFuture` — unhandled Future error on native creation failure**

The plan says the private constructor "immediately fires (without awaiting) the native creation call as a `late final Future<void> _createFuture`". If the native `create` call throws a `PlatformException` (e.g., device handle invalid, SDK not initialized), two things go wrong:

- **Unhandled Future error:** Dart's unhandled error zone fires immediately. In debug mode this crashes; in release Flutter reports it as unhandled.
- **`dispose()` throws:** The plan says `dispose()` awaits `_createFuture` then calls native destroy. If `_createFuture` errored, the await rethrows and the destroy call never fires, leaving `dispose()` itself in a throwing state.

`DeviceLocator` already solves this exact problem (device_locator.dart lines 38-47):

```dart
_nativeReady = _channel
    .invokeMethod<void>(DeviceLocatorMethods.create, args)
    .catchError((Object error) {
  _createError = error;
  _instance = null;
});
```

It stores the error in a `_createError` field, checks it with `_checkReady()`, and skips the native destroy in `dispose()` when creation failed.

**Fix:** Task 2 must include the same pattern — `.catchError()` on the creation future, a `_createError` field, a `_checkReady()` guard called before stream access, and `dispose()` must check `_createError` before invoking native destroy.

**2. Missing `device.isStarted` guard in constructor**

ARCHITECTURE.md anti-patterns section (line 250):
> ❌ **Starting classifiers before `clCDevice_Start`** — classifiers require an active EEG stream; enforce this in the Dart API

The classifier spec note (04-dart-api-classifiers.md line 112):
> Never create classifiers before `Device.start()`.

The plan's factory constructor accepts a `Device` but performs no check. `Device` already exposes `isStarted` (device.dart line 287). The factory should guard:

```dart
factory NfbClassifier(Device device, {IndividualNfbData? calibration}) {
  if (!device.isStarted) {
    throw StateError('Cannot create NfbClassifier before Device.start()');
  }
  return NfbClassifier._(device.serial, calibration);
}
```

Without this, the native creation call will fail asynchronously (hitting issue #1 above), producing an unhelpful platform exception instead of a clear synchronous error.

### Suggestions

None — fixing the two issues above makes the plan solid. Channel names, event channel IDs, model references, import paths, dispose lifecycle, stream patterns, and barrel export placement all check out correctly against the codebase.

### Positive Notes

- The plan correctly identifies that `ClassifierMethods` is missing `dispose` and scopes Task 1 as a shared contract change that benefits all future classifiers — good forward thinking.
- Stream wiring (`NeiryEvents.nfbState`, `NeiryEvents.nfbError`) matches the existing channel contract exactly.
- The `_eventStream` helper reuse from `Device` is the right call — keeps the decode pattern consistent.
- Import paths from the new `classifiers/` subdirectory are all correct (verified: `../../channel/`, `../../models/`, `../device.dart`).
- `IndividualNfbData.toMap()` exists and returns `Map<String, dynamic>` — the plan's `calibration.toMap()` call is valid.
- Barrel export placement after `device_locator.dart` keeps API classes grouped logically.
