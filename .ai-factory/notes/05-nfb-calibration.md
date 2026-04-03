# NFB Calibration Pipeline

**Date:** 2026-04-03
**Source:** SDK docs — calibration, classcapsule NFBCalibrator, _n_f_b_calibrator_8hpp, structcl_c_individual_n_f_b_data

## Key Findings

- 4-stage calibration: stage1+3 closed eyes (20s each), stage2+4 open eyes (20s each) — total 80 seconds
- Quick mode: 1 stage, 30 seconds, closed eyes only — less robust, not suitable as first calibration
- `clCIndividualNFBData` has NO sentinel fields — all floats have meaningful defaults; only timestamp can be -1
- Only NFB classifier strictly requires calibration data; Physio and Productivity use their own separate baseline calibration
- Calibration data can be imported from a previous session via `ImportIndividualNFBData()`
- 2 failure reasons: `TooManyArtifacts` (ask user to sit still) and `PeakFrequencyAtBorder` (atypical alpha peak)

## Details

### 4-Stage Flow

| Stage | Eyes | Duration | Purpose |
|---|---|---|---|
| 1 | Closed | 20s | Resting baseline — establish alpha power |
| 2 | Open | 20s | Visual engagement — measure alpha suppression |
| 3 | Closed | 20s | Confirm baseline consistency |
| 4 | Open | 20s | Confirm suppression consistency |

Callback after each stage: `SetOnIndividualNFBStageFinishedEvent`
Callback on completion: `SetOnIndividualNFBCalibratedEvent` → provides `IndividualNfbData`

### Quick Mode

- 1 stage, 30 seconds, closed eyes
- Produces same `IndividualNfbData` output but lower confidence
- Use for re-calibration or validation; never as first calibration
- Maps to `CalibrateIndividualNFBQuick()`

### IndividualNfbData fields

```dart
class IndividualNfbData {
  final DateTime timestamp;
  final NfbCalibrationFailReason failReason; // None=0, TooManyArtifacts=1, PeakAtBorder=2
  final double individualFrequency;          // alpha peak center (Hz), default 10.0
  final double individualPeakFrequency;      // same as above (legacy), default 10.0
  final double individualPeakFrequencyPower; // power at peak (μV²/Hz), default 10.0
  final double individualPeakFrequencySuppression; // closed/open ratio, default 2.0
  final double individualBandwidth;          // alpha band width (Hz), default 6.0
  final double individualNormalizedPower;    // 0–1 normalized, default 0.5
  final double lowerFrequency;               // band lower bound (Hz), default 7.0
  final double upperFrequency;               // band upper bound (Hz), default 13.0

  bool get isValid => failReason == NfbCalibrationFailReason.none;
  Map<String, dynamic> toMap() { ... }  // required: MethodChannel args + example Export
}
```

### Dart API

```dart
class NfbCalibrator {
  // Full 4-stage: sealed stream — CalibrationStageFinished x4, then CalibrationCompleted
  static Stream<CalibrationEvent> calibrateIndividual()

  // Quick 1-stage
  static Future<IndividualNfbData> calibrateIndividualQuick()

  // Import from previous session
  static Future<void> importCalibrationData(IndividualNfbData data)

  // Query state
  static Future<IndividualNfbData?> getCalibrationData()
  static Future<bool> isCalibrated()
}

// Sealed class — defined in note 02-dart-models.md
// CalibrationStageFinished(CalibrationStage stage)
// CalibrationCompleted(IndividualNfbData data)

enum CalibrationStage { stage1, stage2, stage3, stage4 }
enum NfbCalibrationFailReason { none, tooManyArtifacts, peakFrequencyAtBorder }
```

### Channel constants for calibration

```
MethodChannel:  neiry_kit/nfb_calibrator
Methods:        calibrateQuick, importCalibration, getCalibration, isCalibrated
EventChannel:   neiry_kit/events/nfbCalibration
                  {'type': 'stage', 'stage': 1..4}  →  CalibrationStageFinished
                  {'type': 'done',  'data': {...}}   →  CalibrationCompleted
```

### Failure handling

| Failure | Cause | Mitigation |
|---|---|---|
| `TooManyArtifacts` | Movement/muscle artifacts | Ask user to sit still, retry full calibration |
| `PeakFrequencyAtBorder` | Alpha peak at 7 or 13 Hz boundary | Retry or accept marginal result; try quick mode |

Check `HasCalibrationFailed()` and do not start NFB classifier if calibration is invalid.

### Platform notes

- iOS: prevent screen sleep during 80s calibration (`UIApplication.shared.isIdleTimerDisabled = true`)
- Android: acquire wake lock during calibration
- Both: provide haptic feedback on stage transitions
- If device disconnects mid-calibration: SDK fires failure callback → propagate as `PlatformException`
