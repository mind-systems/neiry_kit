## Code Review: Export + integration tests

**Files Reviewed:** `test/api_test.dart` (new, 266 lines), `test/channel_names_test.dart` (modified), plan, 12 source files
**Tests:** 147 total (all passing) — 35 new in `api_test.dart`, 42 in `channel_names_test.dart` (3 assertions added), 70 in `models_test.dart` (unchanged)

### Verification against plan

All 5 plan tasks are implemented and marked complete:

1. **Barrel file verification** — `lib/neiry_kit.dart` exports 30 files, matching all 30 public `.dart` files under `lib/src/` (excluding `models/internal/sentinel.dart`). No missing exports.
2. **channel_names_test.dart fixes** — Three missing `NeiryEvents` IDs added (`physiologicalIndividualNfb`, `productivityBaselines`, `productivityIndividualNfb`), count updated 26→29 (verified: 29 constants in `NeiryEvents`), `ClassifierMethods.dispose` added to uniqueness list.
3. **Device state machine guards** — 5 tests covering pre-connect throws, double-connect throw, and post-dispose throws.
4. **Classifier factory guards + stream types** — 7 factory guard tests + 8 stream type assertions.
5. **CalibrationEvent sealed dispatch** — Exhaustive switch sentinel + 2 field-carrying tests.

### Verification against source

Every assertion checked against the corresponding source file:

- **`_checkConnected()` guard** (`device.dart:106-108`): `start()` at line 184, `getInfo()` at line 297, `getEEGSampleRate()` at line 308 — all call `_checkConnected()` synchronously before any `await`. Tests use `await expectLater(device.method(), throwsA(...))` which correctly catches the synchronously-rejected Future from the `async` method. ✅
- **Double-connect guard** (`device.dart:155`): `if (_connected) throw StateError('Device is already connected')`. Test mocks the MethodChannel AND three EventChannels (`connectionStatus`, `modeSwitched`, `battery`) needed by `_startStateTracking()` at lines 121–137. Uses `setMockMessageHandler` with `StandardMethodCodec().encodeSuccessEnvelope(null)` — correct technique for intercepting EventChannel `listen` calls. Cleanup via `addTearDown`. ✅
- **Post-dispose guard** (`device.dart:102-104`): `_checkNotDisposed()` throws `StateError('Device has been disposed')`. Test creates a fresh device (no `connect()` call — avoids EventChannel mocking), calls `await device.dispose()`, then verifies `eegStream` getter, `connect()`, `start()`, `getInfo()` all throw. Stream getter test correctly uses sync closure: `expect(() => device.eegStream, throwsA(...))`. ✅
- **Initial state** (`device.dart:47-52`): `_connected = false`, `_started = false`, `_disposed = false`, `_battery` null, `_mode` null, `_connectionState = NeiryConnectionState.disconnected`. All 6 assertions match. ✅
- **Classifier factories**: All 5 classifiers check `device.isStarted` synchronously in factory constructors. Error messages all contain `'before Device.start()'`. Tests use `const IndividualNfbData()` for `.withCalibration` variants — correct since the guard throws before data is accessed. ✅
- **Stream type assertions**: All 8 `late final` stream getters access `receiveBroadcastStream()` which defers the platform `listen` message to `.listen()`. `isA<Stream<T>>()` works without mocking because no platform call is triggered. Verified for all 8 streams. ✅
- **CalibrationEvent sealed dispatch**: `CalibrationEvent` is sealed with exactly two `final` subtypes. The exhaustive `switch` expression serves as a compile-time sentinel. `const IndividualNfbData(individualFrequency: 11.5)` is valid — default constructor has this named parameter with default `10.0`. ✅

### Critical Issues

None.

### Suggestions

**1. Classifier guard tests don't assert error message content**

The plan states "All error messages must contain `'before Device.start()'`", and all 5 classifier source files do include this substring. However, the tests only check `throwsA(isA<StateError>())` — they don't verify the message. Compare with the `connect() when already connected` test which does use `.having((e) => e.message, 'message', contains('already connected'))`. Adding `.having()` to classifier tests would make them more specific and protect against accidental message changes. Not a runtime bug — the correct exception type is thrown — but the message assertion would be more thorough.

### Positive Notes

- All plan review 1 issues are properly addressed in the implementation: EventChannel mocking, source-verified count, barrel export check, `const IndividualNfbData()`, fresh-device dispose, sync closure for getters.
- `addTearDown` is used consistently to clean up mock handlers, preventing test pollution.
- `TestWidgetsFlutterBinding.ensureInitialized()` correctly placed at top of `main()` for binary messenger access.
- Test style matches existing files (`models_test.dart`, `channel_names_test.dart`): flat groups, `// ──…──` dividers, no setUp/tearDown blocks except where mocking requires it.
- The sealed dispatch exhaustiveness test is a compile-time sentinel — adding a new `CalibrationEvent` subtype would break compilation, not silently pass.

REVIEW_PASS
