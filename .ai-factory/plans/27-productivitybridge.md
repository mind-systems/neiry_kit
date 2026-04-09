# Plan: ProductivityBridge

## Context
Implement the iOS native bridge (`ProductivityBridge.swift`) that wraps the `clCProductivity` C API and wire it into `NeiryKitPlugin.swift`, completing the last missing iOS classifier bridge. The bridge converts Dart method calls into C SDK calls and streams classifier output back to Dart via EventChannels. Also fix a type mismatch on the Dart side where `individualNfbStream` would crash at runtime.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Dart-side fix

- [x] **Task 1: Fix ProductivityClassifier individualNfbStream type**
  Files: `lib/src/api/classifiers/productivity_classifier.dart`
  The `_individualNfbStream` field (line 148) currently decodes events with `NfbUserState.fromMap`, but the native `SetOnIndividualNFBUpdateEvent` callback delivers only a handle with no data — the bridge will emit an empty map (`[:]`). Calling `NfbUserState.fromMap` on an empty map crashes (`map['ts'] as int` → `TypeError`).

  Fix by matching the `PhysioClassifier` pattern (physio_classifier.dart lines 94–97):
  - Change the cached stream field from:
    ```dart
    late final Stream<NfbUserState> _individualNfbStream = _eventStream(
      const EventChannel(NeiryEvents.productivityIndividualNfb),
      NfbUserState.fromMap,
    );
    ```
    to:
    ```dart
    late final Stream<void> _individualNfbStream =
        const EventChannel(NeiryEvents.productivityIndividualNfb)
            .receiveBroadcastStream({NeiryArgs.serial: _serial})
            .map((_) {});
    ```
  - Change the public getter return type from `Stream<NfbUserState>` to `Stream<void>` (line 225).
  - Update the getter's doc comment to: `/// Emits a notification whenever the productivity classifier refreshes its internal NFB state. Carries no data — use it as a trigger only.`
  - Remove the now-unused `nfb_user_state.dart` import (line 10) since no other field in this file references `NfbUserState`.

### Phase 2: Bridge implementation

- [x] **Task 2: Create ProductivityBridge.swift — class scaffolding, factory methods, and dispose**
  Files: `ios/Classes/classifiers/ProductivityBridge.swift`
  Create the bridge class following the same structure as `CardioBridge.swift` and `EmotionsBridge.swift`:

  **Class scaffolding:**
  - `private static weak var activeBridge: ProductivityBridge?` — C callbacks reach the instance through this static reference (same pattern as all other classifier bridges).
  - `private var productivity: OpaquePointer?` — the `clCProductivity` handle.
  - Six `DeviceStreamHandler` instances with channel IDs: `neiry_kit/events/productivityMetrics`, `neiry_kit/events/productivityIndexes`, `neiry_kit/events/productivityBaselines`, `neiry_kit/events/productivityCalibrationProgress`, `neiry_kit/events/productivityCalibrated`, `neiry_kit/events/productivityIndividualNfb`.
  - `allStreamHandlers()` returning all 6 `(String, FlutterStreamHandler)` pairs.
  - `requireProductivity() throws -> OpaquePointer` guard helper (same pattern as `PhysioBridge.requirePhysio()`).

  **Factory method — plain path (`create`):**
  - If handle already exists, call `unregisterCallbacks()` first.
  - Set `productivity = clCProductivity_Create(device, &error)` with `clCError` out-param — store the returned handle explicitly.
  - `try checkCError(error)`.
  - Call `registerCallbacks()` (non-throwing — see Task 3).

  **Factory method — calibrated path (`createCalibrated`):**
  - If handle already exists, call `unregisterCallbacks()` first.
  - **Key difference from CardioBridge/NfbBridge:** Productivity takes `clCIndividualNFBData*` directly — NOT a calibrator handle. No `clCNFBCalibrator_CreateOrGet` call needed.
  - Build `var data = clCIndividualNFBData()` from the `calibrationData` dictionary using the same field mapping as `CardioBridge.createCalibrated`: `ts` → `Int64`, `failReason` → `clCIndividualNFBCalibrationFailReason(rawValue:)`, 8 float fields via `as? Double` → `Float(v)`.
  - Set `productivity = clCProductivity_CreateWithIndividualData(device, &data, &error)` — store the returned handle explicitly.
  - `try checkCError(error)`.
  - Call `registerCallbacks()`.

  **Dispose:**
  - `unregisterCallbacks()`, set `productivity = nil`.
  - No `clCProductivity_Destroy` exists in the SDK — callback cleanup is all that's needed.

- [x] **Task 3: Implement callback registration and data serialization**
  Files: `ios/Classes/classifiers/ProductivityBridge.swift`
  Add `registerCallbacks()` and `unregisterCallbacks()` methods. ALL five `clCProductivity_SetOn*Event` functions take NO `clCError*` — use the `EmotionsBridge` pattern (trailing closures, no `var error` / `try checkCError`). Therefore `registerCallbacks()` is non-throwing.

  **`registerCallbacks()`:**
  Set `ProductivityBridge.activeBridge = self`, then register all 5 callbacks:

  1. **`SetOnMetricsUpdateEvent`** — receives `const clCProductivity_Metrics*`:
     - Read `data.pointee` fields into a map.
     - 10 float fields: `fatigueScore`, `reverseFatigueScore`, `gravityScore`, `relaxationScore`, `concentrationScore`, `productivityScore`, `currentValue`, `alpha`, `productivityBaseline`, `accumulatedFatigue` — send as `Float` values (Dart `orNull` handles sentinel `-1`).
     - `fatigueGrowthRate` — send as `Int` (raw enum value 0–3).
     - `ts` — send `timestampMilli` as `Int64`.
     - `artifactsData` — if `artifactsSize > 0`, create `Data(bytes: data.pointee.artifactsData!, count: Int(data.pointee.artifactsSize))` and send as `FlutterStandardTypedData(bytes:)`. If `artifactsSize == 0`, send `NSNull()` (Dart side handles nil).
     - Emit via `metricsHandler.send(map)`.

  2. **`SetOnIndexesUpdateEvent`** — receives `const clCProductivity_Indexes*`:
     - `ts` as `Int64`.
     - `relaxation` — `clCProductivity_RecommendationValue` enum, send `.rawValue` as `Int` (0–5).
     - `stress` — `clCProductivity_StressValue` enum, send `.rawValue` as `Int` (0–2).
     - `hasArtifacts` as `Bool`.
     - 6 float baseline fields: `gravityBaseline`, `productivityBaseline`, `fatigueBaseline`, `reverseFatigueBaseline`, `relaxationBaseline`, `concentrationBaseline`.
     - Emit via `indexesHandler.send(map)`.

  3. **`SetOnBaselineUpdateEvent`** — receives `const clCProductivity_Baselines*`:
     - Serialize the struct to a map with keys `ts`, `gravity`, `productivity`, `fatigue`, `reverseFatigue`, `relaxation`, `concentration` — emit via `baselinesHandler.send(map)`.
     - Also serialize the raw struct bytes to `Data(bytes:count:)` using `withUnsafePointer(to: baselines.pointee) { Data(bytes: $0, count: MemoryLayout<clCProductivity_Baselines>.size) }` — emit `["baselines": FlutterStandardTypedData(bytes: data)]` via `calibratedHandler.send(map)`. This is the opaque blob the Dart side persists and passes back via `importBaselines`.

  4. **`SetOnCalibrationProgressUpdateEvent`** — receives `float`:
     - Clamp to 0.0–1.0 with `max(0.0, min(1.0, progress))`.
     - Emit `["progress": clamped]` via `calibrationProgressHandler.send(map)`.

  5. **`SetOnIndividualNFBUpdateEvent`** — receives only the handle (no data):
     - Emit `[:]` (empty map) via `individualNfbHandler.send([:])`.

  **`unregisterCallbacks()`:**
  Set all 5 callbacks to `nil` — no `clCError*` needed (unlike PhysioBridge/CardioBridge):
  ```swift
  clCProductivity_SetOnMetricsUpdateEvent(productivity, nil)
  clCProductivity_SetOnIndexesUpdateEvent(productivity, nil)
  clCProductivity_SetOnBaselineUpdateEvent(productivity, nil)
  clCProductivity_SetOnCalibrationProgressUpdateEvent(productivity, nil)
  clCProductivity_SetOnIndividualNFBUpdateEvent(productivity, nil)
  ```
  Then clear `activeBridge` if `self`.

- [x] **Task 4: Implement command methods (calibration, baselines import, fatigue reset)**
  Files: `ios/Classes/classifiers/ProductivityBridge.swift`
  Add three command methods callable from the plugin's method dispatch:

  1. **`startBaselineCalibration()`:**
     - Call `requireProductivity()` to guard nil handle.
     - Call `clCProductivity_StartBaselineCalibration(productivity)` — no `clCError*` param, fire-and-forget. No `try`/`checkCError`.

  2. **`importBaselines(data: FlutterStandardTypedData)`:**
     - Call `requireProductivity()`.
     - Deserialize the raw bytes back to a `clCProductivity_Baselines` struct: create `var baselines = clCProductivity_Baselines()`, then `data.data.withUnsafeBytes { baselines = $0.load(as: clCProductivity_Baselines.self) }`. Validate that `data.data.count == MemoryLayout<clCProductivity_Baselines>.size` — if mismatched, throw `FlutterError(code: "INVALID_ARGS", message: "Baselines data size mismatch", details: nil)`.
     - Call `clCProductivity_ImportBaselines(productivity, &baselines, &error)` with `clCError` out-param.
     - `try checkCError(error)`.

  3. **`resetAccumulatedFatigue()`:**
     - Call `requireProductivity()`.
     - Call `clCProductivity_ResetAccumulatedFatigue(productivity, &error)` with `clCError` out-param.
     - `try checkCError(error)`.
     - Add a comment: "SDK does not guarantee atomicity — metrics may briefly show stale fatigue during the reset window."

### Phase 3: Plugin integration

- [x] **Task 5: Wire ProductivityBridge into NeiryKitPlugin.swift**
  Files: `ios/Classes/NeiryKitPlugin.swift`
  Follow the same wiring pattern used for `cardioBridge`:

  1. **Property:** Add `private var productivityBridge: ProductivityBridge?` alongside the other bridge properties (line ~16).

  2. **Initialization:** In `register(with:)`, add `instance.productivityBridge = ProductivityBridge()` after `cardioBridge` init (line ~32).

  3. **Method dispatch:** Add a `handleProductivityCall` method and wire it to `"neiry_kit/productivity"` in `handleMethodCall` — replace the current fall-through to `FlutterMethodNotImplemented`. Route these methods:
     - `"create"` → `deviceBridge.requireDevice()` then `productivityBridge.create(device:)`.
     - `"createCalibrated"` → first `guard let calibrationData = args?["calibrationData"] as? [String: Any] else { result(FlutterError(code: "INVALID_ARGS", message: "calibrationData is required", details: nil)); return }` — then `deviceBridge.requireDevice()` and `productivityBridge.createCalibrated(device:calibrationData:)`. Unlike CardioBridge, `calibrationData` is required (non-nil) since `clCProductivity_CreateWithIndividualData` always needs the struct; a nil dictionary would produce a zeroed `clCIndividualNFBData` silently defeating the purpose of calibration.
     - `"startBaselineCalibration"` → `productivityBridge.startBaselineCalibration()`.
     - `"importBaselines"` → extract `args?["baselines"] as? FlutterStandardTypedData`, call `productivityBridge.importBaselines(data:)`.
     - `"resetAccumulatedFatigue"` → `productivityBridge.resetAccumulatedFatigue()`.
     - `"dispose"` → `productivityBridge.dispose()`.
     All error-path methods use the standard `do/try/catch` pattern from other dispatch blocks.

  4. **EventChannel registration:** In `registerEventChannels()`, add a productivity handlers lookup block (same pattern as the cardio/physio/emotions blocks ~line 566):
     ```swift
     var productivityHandlers: [String: FlutterStreamHandler] = [:]
     if let bridge = productivityBridge {
         for (id, handler) in bridge.allStreamHandlers() {
             productivityHandlers[id] = handler
         }
     }
     ```
     Add `else if let handler = productivityHandlers[id]` to the handler resolution chain in the `for id in ids` loop, before the `StubStreamHandler` fallback.

  5. **Dispose chain:** In `handleDeviceLocatorCall` → `"dispose"` case, add `productivityBridge?.dispose()` alongside the other classifier disposals (line ~144), before `bridge.dispose()`.

## Commit Plan
- **Commit 1** (after task 1): "Fix ProductivityClassifier individualNfbStream to Stream<void> matching PhysioClassifier pattern"
- **Commit 2** (after tasks 2-5): "Add ProductivityBridge iOS implementation and plugin wiring"
