# SDK v2.0.72 — IndividualNFBData Field Comparison

## Verdict: Field-complete, no changes needed

Our `IndividualNfbData` Dart model and both platform bridges fully match the v2.0.72 struct.

## Field comparison

| Field | Our Dart model | v2.0.72 SDK (`IndividualNFBInfo`) | C struct (`clCIndividualNFBData`) |
|---|---|---|---|
| timestamp | `DateTime?` | `int timestampMilli` | `int64_t timestampMilli = -1` |
| failReason | `NfbCalibrationFailReason` | `IndividualNFBCalibrationFailReason` | `clCIndividualNFBCalibrationFailReason` |
| individualFrequency | `double` | `double` | `float` |
| individualPeakFrequency | `double` | `double` | `float` |
| individualPeakFrequencyPower | `double` | `double` | `float` |
| individualPeakFrequencySuppression | `double` | `double` | `float` |
| individualBandwidth | `double` | `double` | `float` |
| individualNormalizedPower | `double` | `double` | `float` |
| lowerFrequency | `double` | `double` | `float` |
| upperFrequency | `double` | `double` | `float` |

10 fields total — identical in all three representations.

## Only difference: timestamp representation

- Our model: `DateTime?` (nullable, converted from milliseconds epoch)
- SDK: `int timestampMilli` (non-nullable raw milliseconds)
- Both iOS and Android bridges already handle the epoch→DateTime conversion correctly
- Not a problem

## Bridge status

Both bridges populate all 10 fields correctly in both directions (Dart map → C struct and C struct → Dart map):
- iOS: `NfbCalibratorBridge.swift` lines 82-96 (import) and 188-200 (export)
- Android: `jni_nfb_calibrator.cpp` lines 112-122 (import) and 277-287 (export)
