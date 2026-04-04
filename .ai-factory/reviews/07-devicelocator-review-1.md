## Code Review: 07-devicelocator

**Plan:** DeviceLocator Dart API class
**Files reviewed:** `lib/src/api/device_locator.dart` (new), `lib/src/channel/channel_names.dart` (modified), `lib/neiry_kit.dart` (modified), `test/channel_names_test.dart` (not modified — should have been)
**Risk Level:** 🟡 Medium

### Critical Issues

**1. Existing tests don't compile — `DeviceLocatorMethods.requestDevices` was removed but test still references it**

`test/channel_names_test.dart:120` references the removed constant:

```dart
group('DeviceLocatorMethods — unique', () {
  final names = [
    DeviceLocatorMethods.requestDevices,  // ← removed in channel_names.dart
    DeviceLocatorMethods.setSingleThreaded,
    DeviceLocatorMethods.setLogLevel,
    DeviceLocatorMethods.getVersionString,
  ];
```

`flutter test` fails with:
```
test/channel_names_test.dart:120:28: Error: Member not found: 'requestDevices'.
```

This was flagged in plan-review-2 suggestion #1. The plan's `Testing: no` setting means "don't write new tests" — it does not mean "ignore compilation failures in existing tests caused by contract changes."

**Fix:** Update the `DeviceLocatorMethods` uniqueness test list (line 119–128) to remove `requestDevices` and add the four new constants (`create`, `createDevice`, `dispose`, `update`). Also add `NeiryArgs.logDirectory` to the `NeiryArgs` uniqueness test list (line 192–204) — this isn't a compilation failure but leaves the new constant uncovered by the existing uniqueness check.

**2. `_nativeReady` becomes an unhandled errored Future if native create fails**

In the constructor (line 37–45):

```dart
_nativeReady = _channel
    .invokeMethod<void>(DeviceLocatorMethods.create, args)
    .then((_) {})
    .catchError((Object error) {
  _instance = null;
  throw error;   // ← re-throws, so _nativeReady completes with error
});
```

The `catchError` callback re-throws, which means `_nativeReady` is an errored Future. If nobody awaits it before Dart's microtask queue processes the error, the zone's uncaught error handler fires — in debug mode this produces a red error screen; in release it logs to console.

This happens when:
- Native create fails (Bluetooth unavailable, SDK init error, etc.)
- The user only called `requestDevices` before the error surfaces (requestDevices doesn't await `_nativeReady` per the FIFO design)
- Or the user never calls any method at all after construction

The `dispose` method does catch the error via try/catch, but `dispose` is typically called later — by then the uncaught error has already fired.

**Fix:** Don't re-throw in `catchError`. Instead, store the error in a field and check it in methods that currently await `_nativeReady`:

```dart
Object? _createError;

DeviceLocator._({String? logDirectory}) {
  final args = logDirectory != null
      ? {NeiryArgs.logDirectory: logDirectory}
      : null;
  _nativeReady = _channel
      .invokeMethod<void>(DeviceLocatorMethods.create, args)
      .catchError((Object error) {
    _instance = null;
    _createError = error;
    // Don't re-throw — _nativeReady completes normally
  });
}

void _checkReady() {
  if (_createError != null) {
    throw StateError('DeviceLocator creation failed: $_createError');
  }
}
```

Then in `createDevice`, `setSingleThreaded`, `update`: call `await _nativeReady` then `_checkReady()`. In `dispose`: after `await _nativeReady`, if `_createError != null`, skip the native destroy (same logic, cleaner).

This eliminates the unhandled Future error while preserving the same observable behavior for methods that depend on the native handle.

### Suggestions

**3. Unnecessary `.then((_) {})` in constructor**

Line 39: `.then((_) {})` is a no-op. `invokeMethod<void>` already returns `Future<void>`. The intermediate transformation adds a microtask hop but does nothing. Remove it — chain `.catchError` directly on `invokeMethod`.

### Positive Notes

- The FIFO ordering rationale for skipping `_nativeReady` in `requestDevices` is well-documented with the inline comment block (lines 93–100). This was the correct design choice from the plan review.
- The `identical(_scanSubscription, thisSub)` guard in `clearIfCurrent` (line 123) correctly prevents stale subscription cancellation from killing an active scan.
- The `dispose` flow (check → flag → cancel subscription → await native ready → native destroy → null singleton) is thorough and handles the error path correctly.
- Channel constants are clean — `DeviceLocatorMethods.create/createDevice/dispose/update` added, orphaned `requestDevices` removed.
- The `_deviceListEventChannel` is cached as `static const`, consistent with the `_channel` pattern.
- The `controller.isClosed` checks in the stream callbacks (lines 128, 136, 140) prevent post-close errors.
- Barrel export is in the right position — `api/` exports above `models/` exports.
