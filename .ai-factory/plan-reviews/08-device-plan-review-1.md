## Plan Review: 08-device (iteration 1)

**Plan:** Device Dart API — lifecycle, streams, query getters
**Files Reviewed:** plan + `lib/src/channel/channel_names.dart`, `lib/src/channel/enums.dart`, `lib/src/api/device_locator.dart`, `lib/neiry_kit.dart`, `lib/src/models/device_info.dart`, `lib/src/models/nfb_user_state.dart`, `lib/src/models/physio_states.dart`, `lib/src/models/neiry_exception.dart`, `lib/src/models/neiry_error_code.dart`, `lib/src/models/internal/sentinel.dart`, `test/channel_names_test.dart`, `.ai-factory/notes/03-dart-api-device.md`, `.ai-factory/ARCHITECTURE.md`, `.ai-factory/ROADMAP.md`
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md:** OK — `lib/src/api/device.dart` matches the folder structure. Four new models land in `lib/src/models/`. Dependency direction (`api/ → channel/ + models/`) is respected. Barrel export via `neiry_kit.dart` follows key principle #4. All channel/method names reference existing constants in `channel_names.dart`.
- **RULES.md:** WARN — file not present.
- **ROADMAP.md:** OK — plan maps to the "Device" milestone under "Dart API." All behaviors listed in the milestone (lifecycle, state streams, data streams, getters, state machine invariants) are covered.

### Critical Issues

None.

### Suggestions

**1. Task 2 must update `test/channel_names_test.dart` for `NeiryArgs.bipolarChannels`**

The plan adds `NeiryArgs.bipolarChannels` to `channel_names.dart`. The existing test file has a uniqueness test that enumerates all `NeiryArgs` constants (lines 194-213):

```dart
group('NeiryArgs — unique', () {
  final keys = [
    NeiryArgs.serial,
    NeiryArgs.logDirectory,
    // ... all 12 current keys
  ];
```

After Task 2 adds `bipolarChannels`, `flutter test` will still pass but the new constant won't be covered by the uniqueness check. Same class of issue flagged in 07-devicelocator-plan-review-2 (suggestion #1).

**Fix:** Add a sub-step to Task 2: append `NeiryArgs.bipolarChannels` to the `NeiryArgs` uniqueness test list in `test/channel_names_test.dart`.

**2. ResistanceData unit discrepancy between plan and spec notes**

The plan says `values` contains "resistance in Ohms per channel." The spec notes (`03-dart-api-device.md`, line 94) say "kOhm." These contradict each other. The C SDK header (`clCResistance`) is the source of truth — the plan must pick the correct unit and document it in a doc comment on the `values` field so the native bridge author uses the same unit.

**Fix:** Verify which unit the C API actually returns (check `_c_device_8h` documentation or the Doxygen reference in `official/Docs/`). Add a `/// Resistance per channel in [unit]` doc comment to the `values` field.

**3. Missing `getChannelsCount` and `getChannelNameByIndex` from Device getters**

`DeviceMethods` defines `getChannelsCount` (line 96) and `getChannelNameByIndex` (line 95) but the plan's Task 4 doesn't expose them. The roadmap milestone doesn't list them either, so this may be intentional — but they complete the channel introspection API and avoid forcing consumers to call `getChannelNames().length` for a count.

**Fix:** Either add both getters to Task 4, or explicitly note them as deferred.

**4. Multi-device EventChannel limitation should be documented**

The plan states Device "is not a singleton — multiple devices are possible", which is correct for the constructor and MethodChannel calls (serial is passed as an argument). However, all 8 data EventChannels use static channel name strings (`NeiryEvents.eeg`, etc.). Flutter's `EventChannel` supports only one active `receiveBroadcastStream` per channel name — a second device's `receiveBroadcastStream` would overwrite the first device's stream handler on the native side.

This is an existing architectural constraint from the channel contract, not introduced by this plan. But the Device class should document it so consumers know only one device can have active stream subscriptions at a time.

**Fix:** Add a doc comment on the `Device` class noting that concurrent stream subscriptions on multiple Device instances are not supported due to the shared EventChannel names.

### Positive Notes

- The 5-task phased structure (models → skeleton → streams → getters → integration) is clean and each phase has a clear, testable boundary.
- Model classes follow existing conventions exactly: `@immutable`, `const` constructor, `factory fromMap(Map<Object?, Object?>)`, `package:flutter/foundation.dart` import.
- The `_eventStream<T>` helper pattern eliminates boilerplate across 8 stream getters while keeping the decode function explicit per stream.
- Internal state tracking via `_startStateTracking()` / `_stopStateTracking()` correctly handles hardware-initiated disconnects by subscribing to `connectionStateStream` and resetting `_connected` / `_started` flags.
- The `late final` caching approach for streams ensures `receiveBroadcastStream` is called exactly once per Device instance — correct for EventChannel's one-shot activation model.
- `dispose()` design mirrors `DeviceLocator.dispose()`: flag early → cancel subscriptions → native cleanup → reset state.
- Task 5's `createDevice()` return type change from `Future<void>` to `Future<Device>` is backward-compatible (callers can ignore the return value).
- All referenced channel constants, method names, event names, enum types, and exception classes exist in the codebase and match exactly.
