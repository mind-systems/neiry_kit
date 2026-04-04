## Plan Review: 08-device (iteration 2)

**Plan:** Device Dart API — lifecycle, streams, query getters
**Files Reviewed:** plan + `lib/src/channel/channel_names.dart`, `lib/src/channel/enums.dart`, `lib/src/api/device_locator.dart`, `lib/neiry_kit.dart`, `lib/src/models/device_info.dart`, `lib/src/models/nfb_user_state.dart`, `lib/src/models/neiry_exception.dart`, `lib/src/models/internal/sentinel.dart`, `test/channel_names_test.dart`, `.ai-factory/notes/03-dart-api-device.md`, `.ai-factory/ARCHITECTURE.md`, `.ai-factory/ROADMAP.md`
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md:** OK — `lib/src/api/device.dart` matches the folder structure. Four new model files land in `lib/src/models/`. Dependency direction (`api/ → channel/ + models/`) is respected. Barrel export via `neiry_kit.dart` follows key principle #4. All channel/method/event names reference verified constants in `channel_names.dart`.
- **RULES.md:** WARN — file not present.
- **ROADMAP.md:** OK — plan maps to the "Device" milestone under "Dart API." All behaviors listed in the milestone (lifecycle, state streams, data streams, getters, state machine invariants) are covered.

### Review of iteration-1 suggestions

All four suggestions from review 1 have been addressed:

1. ✅ **Test update for `NeiryArgs.bipolarChannels`** — Task 2 now explicitly adds the new constant to the `NeiryArgs` uniqueness test list in `test/channel_names_test.dart`.
2. ✅ **ResistanceData unit resolved** — Task 1 specifies kOhm (confirmed against Doxygen) with an explicit doc comment: `/// Resistance per channel in kOhm.`
3. ✅ **Missing getters added** — Task 4 now includes `getChannelsCount()` and `getChannelName(int index)` via `DeviceMethods.getChannelNameByIndex` / `DeviceMethods.getChannelsCount`.
4. ✅ **Multi-device EventChannel doc** — Task 2 adds a class-level doc comment explaining the shared-channel-name limitation on concurrent Device stream subscriptions.

### Critical Issues

None.

### Suggestions

None.

### Positive Notes

- All four iteration-1 suggestions resolved cleanly — no residual issues.
- The 5-task phased structure (models → skeleton → streams → getters → integration) gives each phase a clear, independently verifiable boundary.
- Model classes follow existing conventions exactly: `@immutable`, `const` constructor, `factory fromMap(Map<Object?, Object?>)`, `orNull` from `internal/sentinel.dart` for nullable fields, `package:flutter/foundation.dart` import.
- The `_eventStream<T>` helper pattern eliminates boilerplate across 8 stream getters while keeping the decode function explicit per stream.
- `late final` caching ensures `receiveBroadcastStream` is called exactly once per Device instance — correct for EventChannel's activation model — and since the result is a broadcast stream, both internal state tracking and public consumers can subscribe safely.
- Internal state tracking via `_startStateTracking()` / `_stopStateTracking()` correctly handles hardware-initiated disconnects by resetting `_connected` / `_started` flags on `disconnected` events.
- `dispose()` mirrors the `DeviceLocator.dispose()` pattern: flag early → cancel subscriptions → native cleanup → reset state.
- Task 5's `createDevice()` return type change from `Future<void>` to `Future<Device>` is backward-compatible.
- Every referenced constant (`DeviceMethods.*`, `NeiryEvents.*`, `NeiryArgs.*`, `NeiryChannels.device`), enum (`NeiryConnectionState`, `NeiryDeviceMode`), exception (`DeviceNotConnectedException`), and model (`DeviceInfo`) verified to exist in the codebase with matching names and signatures.
- Commit plan is well-scoped: commit 1 (models + skeleton) is self-contained; commit 2 (streams + getters + integration) depends on commit 1 only.

PLAN_REVIEW_PASS
