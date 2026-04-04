## Plan Review: Export + integration tests

**Files Reviewed:** 1 plan + 12 source files
**Risk Level:** 🟡 Medium

### Context Gates

- **ARCHITECTURE.md:** WARN — The plan creates `test/api_test.dart` and modifies `test/channel_names_test.dart`. Both align with the existing test structure (`test/models_test.dart`, `test/channel_names_test.dart`) and dependency rules (tests import only via the barrel `neiry_kit.dart`). No boundary issues.
- **RULES.md:** File does not exist. WARN (non-blocking).
- **ROADMAP.md:** The plan targets the `export + integration tests` milestone under **Dart API**. All three roadmap deliverables (state machine throws, stream types match models, CalibrationEvent sealed dispatch) are covered by Tasks 2–4. The plan also fixes existing test gaps (Task 1), which isn't in the milestone description but is directly relevant prep work. No alignment issues.

### Critical Issues

**1. Task 2 — "connect() when already connected" test needs EventChannel mocking**

The plan says to mock only `MethodChannel(NeiryChannels.device)` returning `null` for all calls, then call `device.connect()` successfully before calling it again.

The problem: `connect()` (device.dart:153–162) calls `_startStateTracking()` after the `invokeMethod` returns. `_startStateTracking()` (device.dart:121–137) subscribes (`.listen()`) to three `late final` EventChannel-backed streams:

- `_connectionStateStream` → `EventChannel(NeiryEvents.connectionStatus)`
- `_modeChangedStream` → `EventChannel(NeiryEvents.modeSwitched)`
- `_batteryStream` → `EventChannel(NeiryEvents.battery)`

Subscribing to an EventChannel triggers a `listen` MethodCall on that channel's binary messenger key. In the test environment, with no handler registered for those channel names, `StandardMethodCodec.decodeEnvelope(null)` throws `MissingPluginException`. This exception propagates as a stream error. Since the listeners in `_startStateTracking()` have no `onError` callback, the error reaches the zone's uncaught error handler and fails the test.

Fix: the plan must also register mock stream handlers (or mock binary message handlers) for the three EventChannels used by `_startStateTracking()`. `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler` for each of `NeiryEvents.connectionStatus`, `NeiryEvents.modeSwitched`, and `NeiryEvents.battery` — returning `StandardMethodCodec().encodeSuccessEnvelope(null)` — so the `listen` call succeeds silently. Alternatively, use `setMockStreamHandler` (available in recent Flutter). Clean up all handlers in `tearDown`.

This same issue affects the "methods after dispose()" test if it calls `connect()` first. As written, that test calls `device.dispose()` directly on a fresh device (without `connect()`), which avoids the issue — but the plan should clarify this explicitly so the implementer doesn't add a `connect()` call before `dispose()`.

**2. Task 1 — count assertion update is correct but incomplete as a guard**

The plan says to update `equals(26)` to `equals(29)`. This is arithmetically correct (26 + 3 = 29). However, the actual number of EventChannel IDs in `channel_names.dart` is 29 (I counted all entries from `deviceList` through `productivityError`). The plan should verify this total against the source, not just increment by 3, to avoid a stale count if another milestone added IDs between plan creation and implementation.

Not blocking — the count is correct today — but the implementer should double-check the source file.

### Suggestions

**3. Plan doesn't explicitly verify barrel file completeness**

The roadmap milestone says "export all classes" and the plan title includes "Export." The barrel file `lib/neiry_kit.dart` already exports all 31 public source files (the only unexported file is `models/internal/sentinel.dart`, which is intentionally internal). The plan should include a brief verification step — even if it's just "confirm all exports are present" — since the milestone explicitly calls it out. As-is, an implementer following the plan would complete it without ever checking.

**4. Task 3 — simpler `IndividualNfbData` construction for guard tests**

The plan says to use `IndividualNfbData.fromMap(...)` for the `ProductivityClassifier.withCalibration` and `CardioClassifier.withCalibration` guard tests. Since the factory guard (`device.isStarted` check) throws before the data parameter is ever used, `const IndividualNfbData()` works and is simpler. Not wrong, just unnecessary ceremony.

**5. Task 2 — "methods after dispose()" should test `device.dispose()` on a fresh device**

The plan says to "use the same mock" and "Call `device.dispose()`". It's ambiguous whether this means calling `connect()` first. On a fresh device (never connected), `dispose()` only calls `_channel.invokeMethod(DeviceMethods.disconnect)` (which the mock handles) and `_stopStateTracking()` is a no-op (no subscriptions). This avoids the EventChannel mocking problem entirely. The plan should state explicitly: "create a fresh `Device(serial: 'test')`, do NOT call `connect()` first, call `device.dispose()` directly."

**6. Task 2 — stream getter tests after dispose need sync expectations**

`device.eegStream` is a synchronous getter that throws `StateError` from `_checkNotDisposed()`. The test should use `expect(() => device.eegStream, throwsA(isA<StateError>()))` — a sync closure, not `expect(device.eegStream, ...)` which would evaluate the getter (and throw) before `expect` runs. The plan says to test `device.eegStream` (getter) but doesn't specify the expect pattern. The implementer might write it incorrectly.

### Positive Notes

- Task 1 correctly identifies all three missing EventChannel IDs (`physiologicalIndividualNfb`, `productivityBaselines`, `productivityIndividualNfb`) and the omitted `ClassifierMethods.dispose` — verified against the source.
- The plan's reasoning about `late final` stream getters being safe to access without mocking (Task 3, stream type assertions) is correct: `receiveBroadcastStream()` defers the `listen` platform message to `.listen()`, so the type-check `isA<Stream<T>>()` works without native code.
- Sealed class exhaustiveness test (Task 4) is a smart compile-time sentinel — if a subtype is added, the switch breaks at compile time, not silently at runtime.
- All seven classifier factory paths are accounted for, and the error message assertion (`'before Device.start()'`) is verified against all five classifier source files.
- The dependency chain (Task 1 → Task 2 → Tasks 3/4) is logical and avoids merge conflicts.
