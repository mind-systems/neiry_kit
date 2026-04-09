## Code Review: PhysioBridge

**Plan:** `.ai-factory/plans/25-physiobridge.md`
**Changed files:** `ios/Classes/classifiers/PhysioBridge.swift` (new), `ios/Classes/NeiryKitPlugin.swift` (modified), `lib/src/api/classifiers/physio_classifier.dart` (modified)

### Task 1: PhysioBridge.swift — verified

- Scaffold: `activeBridge`, `physio`, 4 `DeviceStreamHandler` instances, `allStreamHandlers()` — all match plan and follow NfbBridge/EmotionsBridge patterns. ✓
- `create(device:)`: guards existing handle, creates via `clCPhysiologicalStates_Create`, checks error, registers callbacks. Same pattern as NfbBridge. ✓
- `registerCallbacks()`: marked `throws`, uses separate `var error1..4 = clCError()` per registration, passes `&error` as 3rd argument (no trailing closures), calls `try checkCError` after each. ✓
- States callback: serializes all 8 fields (`ts`, `relaxation`, `fatigue`, `none`, `concentration`, `involvement`, `stress`, `nfbArtifacts`, `cardioArtifacts`). Keys match `PhysiologicalStatesValue.fromMap` exactly. ✓
- Calibration progress callback: clamps to `[0, 1]`, sends `["progress": clamped]`. Matches Dart `(map['progress'] as num).toDouble()`. ✓
- Calibrated callback: serializes all 6 baselines fields (`ts`, `alpha`, `beta`, `alphaGravity`, `betaGravity`, `concentration`). Keys match `PhysiologicalStatesBaselines.fromMap` exactly. ✓
- Individual NFB callback: sends `[:]` (empty dict). Matches Dart `Stream<void>` with `.map((_) {})`. ✓
- `unregisterCallbacks()`: uses 3-param form `(handle, nil, &e)` for all 4, reuses throwaway error, clears `activeBridge`. ✓
- `requirePhysio()`: throws `FlutterError(code: "NOT_CREATED")` on nil handle. Follows `DeviceBridge.requireDevice()` pattern. ✓
- `startBaselineCalibration()`: `throws`, guards via `requirePhysio()`, calls C function. ✓
- `importBaselines(map:)`: `throws`, guards via `requirePhysio()`, deserializes all 6 fields with correct casts (`Int` → `Int64` for ts, `Double` → `Float` for floats). ✓
- `dispose()`: unregisters callbacks, nils handle. ✓

### Task 2: NeiryKitPlugin wiring — verified

- Property: `private var physioBridge: PhysioBridge?` alongside other bridges. ✓
- Instantiation: `PhysioBridge()` created after `emotionsBridge`, before `registerEventChannels()`. ✓
- `handlePhysiologicalCall`: guards both bridges, dispatches `create`/`startBaselineCalibration`/`importBaselines`/`dispose`/default. ✓
  - `create`: `do/catch` with `requireDevice()` + `create(device:)`. ✓
  - `startBaselineCalibration`: `do/catch` wrapping `try physioBridge.startBaselineCalibration()`. ✓
  - `importBaselines`: guards `args?["baselines"]` with `INVALID_ARGS`, then `do/catch` wrapping `try physioBridge.importBaselines(map:)`. ✓
  - `dispose`: non-throwing, `result(nil)`. ✓
- Routing: `else if channelId == "neiry_kit/physiological"` after emotions branch, before fallthrough. ✓
- Event channels: `physioHandlers` dictionary built from `physioBridge.allStreamHandlers()`, looked up in the registration loop before `StubStreamHandler` fallback. ✓
- Cleanup: `physioBridge?.dispose()` in `handleDeviceLocatorCall.dispose` after `emotionsBridge?.dispose()` and before `nfbBridge?.dispose()`. ✓

### Task 3: Dart individualNfbStream fix — verified

- `_individualNfbStream` changed from `Stream<NfbUserState>` to `Stream<void>` with `.map((_) {})`. ✓
- Public getter `individualNfbStream` returns `Stream<void>`. ✓
- `NfbUserState` import removed — confirmed no remaining references in file. ✓

### Cross-cutting checks

- **Channel name contract**: all 4 EventChannel IDs in PhysioBridge match `channel_names.dart` constants and are present in `NeiryKitPlugin.registerEventChannels()` `ids` array. ✓
- **MethodChannel name**: `"neiry_kit/physiological"` matches `NeiryChannels.physiological`. ✓
- **Method names**: `"create"`, `"startBaselineCalibration"`, `"importBaselines"`, `"dispose"` match `ClassifierMethods` constants used on the Dart side. ✓
- **Argument keys**: `"baselines"` matches `NeiryArgs.baselines`. ✓
- **Serialization round-trip**: Dart `PhysiologicalStatesBaselines.toMap()` produces `ts` (int), `alpha`/`beta`/`alphaGravity`/`betaGravity`/`concentration` (double, sentinel -1.0). Swift `importBaselines` casts `Int` → `Int64` and `Double` → `Float` — matches. ✓
- **Sentinel handling**: Swift floats arrive as `num` in Dart; `orNull()` handles both `int` and `double` via `(v as num).toDouble()` and returns `null` for negatives. ✓
- **Threading**: all `send()` calls dispatch to main thread via `DeviceStreamHandler.send()`. ✓
- **Error propagation**: all throwing bridge methods are wrapped in `do/catch` at the dispatch layer, catching `FlutterError` and generic errors. ✓

### Issues

None found.

REVIEW_PASS
