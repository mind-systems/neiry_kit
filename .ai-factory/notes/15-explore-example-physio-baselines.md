# Explore: Physio + Emotions Tab — Baselines & UI Patterns

Research findings for the `Physio + Emotions tab` example app milestone.

## Critical: plugin bug — baselines type is wrong

`PhysioClassifier.calibrated` currently returns `Stream<Uint8List>` and `importBaselines(Uint8List)` takes raw bytes. This is WRONG — `clCPhysiologicalStates_Baselines` is a structured C struct with 6 named fields, not opaque bytes.

**Plugin changes required BEFORE the example app can work:**

1. Create `lib/src/models/physio_baselines.dart` — new `PhysiologicalStatesBaselines` model
2. Change `PhysioClassifier.calibrated` from `Stream<Uint8List>` to `Stream<PhysiologicalStatesBaselines>`
3. Change `PhysioClassifier.importBaselines(Uint8List)` to `importBaselines(PhysiologicalStatesBaselines)`
4. Update iOS/Android bridges to emit baselines as a map (6 fields) not bytes
5. Export `PhysiologicalStatesBaselines` from `lib/neiry_kit.dart`

**`PhysiologicalStatesBaselines` model — map keys match C struct field names:**

```dart
class PhysiologicalStatesBaselines {
  final DateTime? timestamp;
  final double? alpha;
  final double? beta;
  final double? alphaGravity;
  final double? betaGravity;
  final double? concentration;

  Map<String, dynamic> toMap() => {
    'ts': timestamp?.millisecondsSinceEpoch ?? -1,
    'alpha': alpha ?? -1.0,
    'beta': beta ?? -1.0,
    'alphaGravity': alphaGravity ?? -1.0,
    'betaGravity': betaGravity ?? -1.0,
    'concentration': concentration ?? -1.0,
  };

  factory PhysiologicalStatesBaselines.fromMap(Map<Object?, Object?> map) =>
      PhysiologicalStatesBaselines(
        timestamp: _tsFromMap(map['ts']),
        alpha: orNull(map['alpha']),
        beta: orNull(map['beta']),
        alphaGravity: orNull(map['alphaGravity']),
        betaGravity: orNull(map['betaGravity']),
        concentration: orNull(map['concentration']),
      );
}
```

## ROADMAP correction needed

Line 47 (Physio + Emotions tab): "Import Baselines button (opaque Uint8List from file)" is wrong.
Correct: "Import/Export Baselines as JSON (6-field struct map: ts, alpha, beta, alphaGravity, betaGravity, concentration)"

## Import/Export flow

**Export (after calibration completes):**
1. `PhysioClassifier.calibrated` emits `PhysiologicalStatesBaselines`
2. User taps Export → `jsonEncode(baselines.toMap())` → write to Documents dir
3. File: `physio_baselines_<timestamp>.json`

**Import:**
1. User taps Import → `file_picker` → read file → `jsonDecode` → `PhysiologicalStatesBaselines.fromMap(map)`
2. Call `classifier.importBaselines(baselines)` → bridge deserializes map back to C struct
3. `clCPhysiologicalStates_ImportBaselines` has NO error param — silently fails on bad input.
   Bridge / Dart should validate ranges before calling.

## nfbArtifacts / cardioArtifacts display

`PhysiologicalStatesValue` already has both fields. Show as a separate "Signal Quality" row below the numeric values — artifacts are metadata, not measures.

```
Relaxation:      0.72
Fatigue:         0.18
Concentration:   0.65
...
────���────────────────
Signal Quality
NFB:    ● OK
Cardio: ● OK
```

Green `Icons.check_circle` when false, red `Icons.error` when true.

## 2-minute update UX

PhysiologicalStates fires every ~2 min. Show:
- "Last updated: HH:MM:SS" label below the values
- Reduce opacity to 0.5 while waiting for first update ("Waiting for first update...")
- No countdown — it's noisy and the SDK doesn't expose a next-update estimate

## Emotions vs Physio layout

Two separate `Card` widgets, Emotions on top (continuous updates), Physio below (2-min updates). Clear section headers with update frequency note. Slight visual distinction (e.g., different subtitle color) to communicate the different cadences.

Emotions card: no timestamp, no stale indicator — updates continuously.
Physio card: "Last updated: HH:MM:SS" + opacity reduction + artifacts quality row.
