## Code Review: 08-device (iteration 1)

**Plan:** Device Dart API — lifecycle, streams, query getters
**Files Reviewed:** `lib/src/api/device.dart`, `lib/src/api/device_locator.dart`, `lib/src/models/eeg_data.dart`, `lib/src/models/psd_data.dart`, `lib/src/models/eeg_artifact_data.dart`, `lib/src/models/resistance_data.dart`, `lib/src/channel/channel_names.dart`, `lib/neiry_kit.dart`, `test/channel_names_test.dart`
**Tests:** 118 passing, `flutter analyze` clean

### Plan review suggestions — verification

All four suggestions from `08-device-plan-review-1.md` are addressed:

1. **`NeiryArgs.bipolarChannels` in uniqueness test:** Added at `test/channel_names_test.dart:208`.
2. **Resistance unit kOhm:** `resistance_data.dart:18-21` — doc comment says "kOhm" with threshold guidance.
3. **`getChannelName(int)` and `getChannelsCount()`:** Added at `device.dart:381-400`.
4. **Multi-device EventChannel limitation:** Documented in class-level doc comment at `device.dart:17-23`.

### Critical Issues

**1. Leaked subscriptions on double `connect()` call**

`connect()` (`device.dart:153`) guards against disposed state but not against already-connected state. If a caller invokes `connect()` twice without an intervening `disconnect()`, `_startStateTracking()` (line 160) overwrites `_stateSubscriptions` with 3 new subscriptions, orphaning the previous 3. The orphaned subscriptions:

- Continue to listen on broadcast streams and mutate `_connectionState`, `_connected`, `_started`, `_mode`, `_battery` — producing duplicate state updates per event.
- Can never be cancelled — `_stopStateTracking()` only cancels whatever is currently in `_stateSubscriptions`.
- Hold a closure reference to `this`, preventing garbage collection if the stream stays open.

**Fix — option A (guard):** Add a connected check at the top of `connect()`:

```dart
Future<void> connect({bool bipolarChannels = false}) async {
  _checkNotDisposed();
  if (_connected) throw StateError('Device is already connected');
  ...
}
```

**Fix — option B (idempotent):** Cancel existing subscriptions before creating new ones:

```dart
void _startStateTracking() {
  _stopStateTracking();        // cancel any existing subs first
  _stateSubscriptions = [ ... ];
}
```

Option A is recommended — it matches the state machine contract (connect→start→stop→disconnect) and prevents a redundant native connect call.

### Suggestions

**1. `dispose()` does not guard against double-dispose**

`DeviceLocator.dispose()` calls `_checkNotDisposed()` first and throws `StateError` on a second call. `Device.dispose()` (`device.dart:206`) sets `_disposed = true` unconditionally and re-sends a native disconnect each time. The plan says "Follow the `DeviceLocator.dispose()` pattern of guarding against already-released state."

While the comment says native disconnect is idempotent, sending redundant platform channel calls is unnecessary and deviates from the established pattern.

**Fix:** Add `if (_disposed) return;` at the top of `dispose()` (soft idempotent) or `_checkNotDisposed()` (hard — throws like DeviceLocator).

### Positive Notes

- All four model classes (`EegData`, `PsdData`, `EegArtifactData`, `ResistanceData`) follow existing conventions exactly: `@immutable`, `const` constructor, `factory fromMap(Map<Object?, Object?>)`, `package:flutter/foundation.dart` import.
- Sample rate getters correctly use `(result! as num).toDouble()` instead of direct `result as double` — handles the `StandardMessageCodec` edge case where native integers arrive as Dart `int` rather than `double`. Prevents a runtime `TypeError`.
- The `_eventStream<T>` helper + `late final` caching pattern is clean. Broadcast streams from `receiveBroadcastStream()` correctly support both internal state tracking and external consumer subscriptions simultaneously.
- `_startStateTracking()`'s connection-state listener correctly handles hardware-initiated disconnects by resetting `_connected` and `_started` flags.
- Barrel exports in `neiry_kit.dart` maintain alphabetical order. `NeiryArgs.bipolarChannels` is covered by the uniqueness test.
- `DeviceLocator.createDevice()` return type change to `Future<Device>` is backward-compatible.
