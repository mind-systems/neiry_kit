# Dart API — Classifiers

**Date:** 2026-04-03
**Source:** SDK docs — classifiers, clcnfb, physiological_states, emotions, productivity_metrics, classcapsule classifier pages

## Key Findings

- No classifier has an explicit `start()`/`stop()` — all auto-activate when `Device.start()` is called
- Emotions is a pure wrapper around NFB internally — cannot function without NFB's alpha decomposition
- Physiological States and Productivity BOTH require baseline calibration before outputs are valid; values are -1 until calibrated
- Productivity emits 3 separate streams: baselines (calibration), indexes (continuous), metrics (continuous)
- Physiological States output interval: every 2 minutes; NFB and Emotions: continuous
- `ResetAccumulatedFatigue()` is Productivity-only — resets the fatigue counter back to zero

## Details

### NFB Classifier

```dart
class NfbClassifier {
  // clCNFB_Create(device) or clCNFB_CreateCalibrated(device, calibrator)
  factory NfbClassifier(Device device, {IndividualNfbData? calibration})

  Stream<NfbUserState> get stateStream     // clCNFB_SetOnUserStateChangedEvent
  Stream<String> get errorStream           // clCNFB_SetOnErrorEvent
}
```

- Without calibration: emits theta, alpha, beta only (4–30 Hz)
- With calibration: all 5 bands including delta, smr
- Output: `NfbUserState` (delta?, theta?, alpha?, smr?, beta?) — sentinel → null

### Physiological States Classifier

```dart
class PhysioClassifier {
  factory PhysioClassifier(Device device)

  Future<void> startBaselineCalibration()  // clCPhysiologicalStates_StartBaselineCalibration
  Future<void> importBaselines(Uint8List data)  // opaque blob from previous session

  Stream<PhysiologicalStatesValue> get stateStream  // fires every 2 minutes
  Stream<double> get calibrationProgress             // 0.0–1.0
  Stream<Uint8List> get calibrated                   // fires once with baselines blob
  Stream<NfbUserState> get individualNfbStream       // internal NFB updates
}
```

- Must call `startBaselineCalibration()` or `importBaselines()` before outputs are meaningful
- Calibration data is opaque `Uint8List` — store and reload between sessions

### Emotions Classifier

```dart
class EmotionsClassifier {
  factory EmotionsClassifier(Device device)

  Stream<EmotionsStates> get stateStream  // clCEmotions_SetOnEmotionalStatesUpdateEvent
  Stream<String> get errorStream
}
```

- No calibration required
- Internally uses NFB alpha decomposition — NFB must be active
- Output: `EmotionsStates` (attention?, relaxation?, cognitiveLoad?, cognitiveControl?, selfControl?)

### Productivity Classifier

```dart
class ProductivityClassifier {
  // Two creation paths
  factory ProductivityClassifier(Device device)
  factory ProductivityClassifier.withCalibration(Device device, IndividualNfbData nfbData)

  Future<void> startBaselineCalibration()
  Future<void> importBaselines(Uint8List data)
  Future<void> resetAccumulatedFatigue()  // clCProductivity_ResetAccumulatedFatigue

  Stream<ProductivityBaselines> get baselineStream    // during calibration
  Stream<ProductivityIndexes> get indexesStream       // continuous
  Stream<ProductivityMetrics> get metricsStream       // continuous
  Stream<double> get calibrationProgress              // 0.0–1.0
  Stream<Uint8List> get calibrated                    // fires once
  Stream<NfbUserState> get individualNfbStream
}
```

- `productivityScore` and `currentValue` are -1 (→ null) until calibration completes
- `ProductivityIndexes.relaxation` → `clCProductivity_RecommendationValue` enum (0–5)
- `ProductivityIndexes.stress` → `clCProductivity_StressValue` enum (0–2)

### Classifier event frequencies

| Classifier | Output interval |
|---|---|
| NFB | Continuous (~EEG rate) |
| Physiological States | Every 2 minutes |
| Emotions | Continuous |
| Productivity metrics/indexes | Continuous |

### Ordering constraint

```
Device.connect()
  → Device.start()
    → NfbClassifier(device)          // can start immediately
    → PhysioClassifier(device)       // can start, but outputs invalid until calibrated
    → EmotionsClassifier(device)     // can start, uses NFB internally
    → ProductivityClassifier(device) // can start, outputs invalid until calibrated
```

Never create classifiers before `Device.start()`.

### Cardio Classifier

```dart
class CardioClassifier {
  // Two creation paths (same as NFB)
  factory CardioClassifier(Device device)
  factory CardioClassifier.withCalibration(Device device, IndividualNfbData nfbData)

  Stream<CardioData> get stateStream    // clCCardio_SetOnCardioDataUpdatedEvent
  Stream<PpgData> get ppgStream         // raw PPG data stream
  Stream<String> get errorStream
}
```

- Pure C API (`clCCardio_*`), no C++ wrapper — same platform channel approach as other classifiers
- Optional calibration via `NFBCalibrator` (same `IndividualNfbData`) — without it, some metrics unavailable
- `CardioData` fields: `heartRate`, `stressIndex`, `kaplanIndex`; quality flags: `hasArtifacts`, `skinContact`, `motionArtifacts`, `metricsAvailable`
- Cardio is **5th classifier in v1** — included alongside NFB, Physio, Emotions, Productivity

## Resolved

- **`EmotionsClassifier` dependency:** No `NfbClassifier` required. `EmotionsClassifier(Device)` checks only `device.isStarted` — confirmed by implementation in `lib/src/api/classifiers/emotions_classifier.dart:36`.
