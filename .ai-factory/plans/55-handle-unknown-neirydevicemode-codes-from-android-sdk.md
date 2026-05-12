# Plan: Handle unknown NeiryDeviceMode codes from Android SDK

## Context
The Android AAR v2.0.72 occasionally fires undocumented integer codes (e.g. `7`) through `SetOnModeSwitchedEvent` — distinct from the public `clCDevice_Mode` enum (0–6). These transient values surface during GATT discovery right after `connect()` and currently crash `modeChangedStream` with `ArgumentError`. Make the Dart layer defensively drop unknown mode codes instead of throwing, while emitting a one-time diagnostic log per unknown code so future SDK regressions stay visible.

## Settings
- Testing: no (only update one pre-existing test broken by the contract change)
- Logging: minimal — exactly one `developer.log` call per *unknown* mode code per `Device` instance (gated by a `Set<int>`). No log on the happy path. This is the intentional realisation of the "minimal logging" setting: enough signal to surface future SDK regressions, no spam during a connection burst.
- Docs: no

## Tasks

### Phase 1: Defensive enum decoding

- [x] **Task 1: Make `NeiryDeviceMode.fromCode` nullable**
  Files: `lib/src/channel/enums.dart`
  Change `NeiryDeviceMode.fromCode(int code)` (lines 60–65) so its return type becomes `NeiryDeviceMode?` and it returns `null` for unrecognised codes instead of throwing `ArgumentError`. Update the dartdoc comment immediately above the method (lines 57–59) to describe the new nullable contract — explicitly note that the Android AAR may emit undocumented internal `Device_Status` values (e.g. `7`) that are silently ignored at this layer, and remove the "Throws [ArgumentError]" line. Do NOT add any placeholder enum values such as `unknown7(7)`. Leave `NeiryDeviceType.fromCode` and `NeiryConnectionState.fromCode` untouched — they remain throwing because those values originate on Dart→native and create-device flows where an unknown code indicates a real bug, not transient noise.

- [x] **Task 2: Filter unknown mode codes from the public stream with one-time diagnostic log** (depends on Task 1)
  Files: `lib/src/api/device.dart`
  Update the `_modeChangedStream` definition at lines 65–68. After Task 1, the `decode` callback returns `NeiryDeviceMode?`, but `_eventStream<T>` is generic over `T` and does not perform null-filtering. Cleanest fix: build this stream inline rather than via `_eventStream` so the unknown-code filter and the diagnostic log can be applied.

  Add a private field on the `Device` class (the public class defined at `lib/src/api/device.dart:31`, next to other per-instance state near the top of the class — note: there is no `_NeiryDevice` symbol in the codebase) to remember which unknown codes have already been logged, scoped to this `Device` instance:

  ```dart
  final Set<int> _loggedUnknownModeCodes = <int>{};
  ```

  Replace the existing `late final Stream<NeiryDeviceMode> _modeChangedStream = _eventStream(...)` with an inline broadcast pipeline that decodes the raw int, logs once per unknown code, then drops the nulls. **Important:** `Stream` in `dart:async` does **not** have a `whereType<T>()` method (that extension only exists on `Iterable`); use the canonical `Stream` equivalent `.where((m) => m != null).cast<NeiryDeviceMode>()`. Example shape:

  ```dart
  late final Stream<NeiryDeviceMode> _modeChangedStream = const EventChannel(
    NeiryEvents.modeSwitched,
  )
      .receiveBroadcastStream({NeiryArgs.serial: serial})
      .map<NeiryDeviceMode?>((raw) {
        final code = (raw as Map<Object?, Object?>)['mode'] as int;
        final mode = NeiryDeviceMode.fromCode(code);
        if (mode == null && _loggedUnknownModeCodes.add(code)) {
          developer.log(
            'Ignoring unknown NeiryDeviceMode code $code from native SDK',
            name: 'neiry_kit',
          );
        }
        return mode;
      })
      .where((mode) => mode != null)
      .cast<NeiryDeviceMode>();
  ```

  Add the `dart:developer` import if it is not already present at the top of `device.dart` (the current imports are `dart:async` plus `package:flutter/services.dart` and friends — `dart:developer` is not yet there). Use the `Set<int>.add` return value as the gate so each unknown code is logged exactly once per `Device` instance — repeated `7`s during a single connection do not spam the log. The public `Stream<NeiryDeviceMode>` type stays unchanged, so the `modeChangedStream` getter at line 231 and the `_startStateTracking` listener at lines 130–132 continue to work without modification. Do not introduce a separate generic helper — only this one stream needs nullable decoding.

- [x] **Task 3: Update the pre-existing test that asserts `NeiryDeviceMode.fromCode` throws** (depends on Task 1)
  Files: `test/channel_names_test.dart`
  Inside the `group('fromCode throws ArgumentError for unknown codes', ...)` block (lines 285–294), remove the `NeiryDeviceMode.fromCode(999)` test case (lines 288–289). Leave the `NeiryDeviceType.fromCode(999)` and `NeiryConnectionState.fromCode(999)` cases in place — those enums remain throwing per Task 1. Immediately below that group, add a new sibling group that asserts the new nullable contract:

  ```dart
  group('NeiryDeviceMode.fromCode returns null for unknown codes', () {
    test('code 7 (undocumented Android Device_Status)',
        () => expect(NeiryDeviceMode.fromCode(7), isNull));
    test('code 999',
        () => expect(NeiryDeviceMode.fromCode(999), isNull));
  });
  ```

  This keeps `flutter test` green after the contract change and documents the specific real-world code (`7`) that motivated the fix. No other test files reference `NeiryDeviceMode.fromCode`, so no further test updates are required.
