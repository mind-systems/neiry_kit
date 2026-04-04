## Plan Review: Export + integration tests (round 2)

**Files Reviewed:** 1 plan + 14 source files + 2 existing test files + review 1
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md:** WARN — No boundary issues. `test/api_test.dart` imports only via the barrel `neiry_kit.dart` (matching `example/` dependency rule). CalibrationEvent dispatch tests are placed in `api_test.dart` rather than `models_test.dart` — reasonable because the unit-level `CalibrationEvent.deserialize` test already exists in `models_test.dart`; the sealed exhaustiveness switch is an API-level integration concern.
- **RULES.md:** File does not exist. WARN (non-blocking).
- **ROADMAP.md:** Plan covers all three milestone deliverables (state machine throws, stream types match models, CalibrationEvent sealed dispatch) plus barrel export verification and existing test gap fixes. Fully aligned.

### Verification of Review 1 Fixes

All six issues from review 1 have been addressed in the updated plan:

1. **EventChannel mocking** — Task 3's "connect() when already connected" test now includes detailed `setMockMessageHandler` setup for `NeiryEvents.connectionStatus`, `NeiryEvents.modeSwitched`, and `NeiryEvents.battery`, with `StandardMethodCodec().encodeSuccessEnvelope(null)` return values and cleanup instructions.
2. **Count assertion** — Task 2 now says "count every static String constant in NeiryEvents class and set the expected value" with "currently 29 — verify against source before hardcoding." Verified: NeiryEvents has exactly 29 constants.
3. **Barrel file verification** — Task 1 now explicitly compares every `.dart` file under `lib/src/` against the barrel file. Verified: 30 public files, 30 barrel exports — all present.
4. **Simpler IndividualNfbData** — Tasks 4's `.withCalibration` guard tests now use `const IndividualNfbData()` instead of `fromMap(...)`.
5. **Dispose on fresh device** — Task 3's "methods after dispose()" test now explicitly states "create a fresh Device(serial: 'test'). Do NOT call connect() first."
6. **Sync closure for stream getters** — Task 3 now specifies `expect(() => device.eegStream, throwsA(...))` pattern with an explicit note not to write `expect(device.eegStream, ...)`.

### Source Verification

Verified every factual claim against source:

- **Task 2 — missing IDs:** NeiryEvents source has 29 constants; test lists 26. Missing three: `physiologicalIndividualNfb` (line 48), `productivityBaselines` (line 54), `productivityIndividualNfb` (line 56). Same three missing from the `eventIds` set. `ClassifierMethods.dispose` (line 110) is absent from the ClassifierMethods test group (6 of 7 listed). All correct.
- **Task 3 — Device guards:** `start()` calls `_checkConnected()` synchronously at line 185 before any await — throws `DeviceNotConnectedException`. `getInfo()` same at line 297. `getEEGSampleRate()` same at line 308. `connect()` checks `if (_connected)` at line 155 — throws `StateError('Device is already connected')`. `dispose()` sets `_disposed = true` at line 209, then `_checkNotDisposed()` in all subsequent calls throws `StateError('Device has been disposed')`. All verified.
- **Task 3 — initial state:** `_connected = false`, `_started = false`, `_disposed = false`, `_battery` is uninitialized `int?` (null), `_mode` is uninitialized `NeiryDeviceMode?` (null), `_connectionState = NeiryConnectionState.disconnected`. All match plan assertions.
- **Task 4 — classifier guards:** All 5 classifier classes check `device.isStarted` synchronously in their factory constructors. Error messages verified: `NfbClassifier` → "Cannot create NfbClassifier before Device.start()", `PhysioClassifier` → same pattern, `EmotionsClassifier`, `ProductivityClassifier` (both factories), `CardioClassifier` (both factories). All contain `'before Device.start()'`.
- **Task 4 — stream type assertions:** `receiveBroadcastStream()` defers the platform `listen` message to `.listen()` — accessing `late final` stream getters triggers initialization but not a platform call. `.map(decode)` preserves the generic type. All 8 stream getters checked: `connectionStateStream`, `modeChangedStream`, `eegStream`, `psdStream`, `artifactsStream`, `resistanceStream`, `batteryStream`, `errorStream`. All have only `_checkNotDisposed()` guard (no `_checkConnected()`), so they work on a fresh device.
- **Task 5 — CalibrationEvent sealed:** `CalibrationEvent` is sealed with two final subtypes: `CalibrationStageFinished(stage)` and `CalibrationCompleted(data)`. `IndividualNfbData` has a `const` constructor with named `individualFrequency` parameter (default 10.0). All correct.

### Critical Issues

None.

### Suggestions

None.

### Positive Notes

- The plan is exceptionally detailed — every test includes the exact expect pattern, mock setup, and reasoning for why mocking is or isn't needed. This removes ambiguity for the implementer.
- The EventChannel mock approach using `setMockMessageHandler` with `StandardMethodCodec().encodeSuccessEnvelope(null)` is the correct low-level technique for intercepting EventChannel `listen` calls in tests.
- The sealed dispatch exhaustiveness test is a compile-time sentinel — if a new subtype is added to `CalibrationEvent`, the test breaks at compile time, not silently at runtime.
- Clear dependency chain: Task 1 (verify) → Task 2 (fix existing tests) → Task 3 (create new file) → Tasks 4–5 (add to file). Logical and avoids conflicts.
- All review 1 issues were addressed thoroughly with explicit, implementer-friendly language.

PLAN_REVIEW_PASS
