## Code Review: EmotionsClassifier

**Plan:** `.ai-factory/plans/11-emotionsclassifier.md`
**Changed files:** `lib/src/api/classifiers/emotions_classifier.dart` (new), `lib/neiry_kit.dart` (modified)
**Reference:** `lib/src/api/classifiers/nfb_classifier.dart` (established pattern)

### Structural verification

The implementation is a 1:1 structural copy of `NfbClassifier` with the calibration branch removed (correct per spec — emotions requires no calibration). Every substitution was verified:

| Element | NfbClassifier | EmotionsClassifier | Correct? |
|---|---|---|---|
| MethodChannel | `NeiryChannels.nfb` | `NeiryChannels.emotions` | Yes — `channel_names.dart:15` |
| State EventChannel | `NeiryEvents.nfbState` | `NeiryEvents.emotionsState` | Yes — `channel_names.dart:37` |
| Error EventChannel | `NeiryEvents.nfbError` | `NeiryEvents.emotionsError` | Yes — `channel_names.dart:60` |
| Model type | `NfbUserState` | `EmotionsStates` | Yes — `emotions_states.dart` |
| Model decoder | `NfbUserState.fromMap` | `EmotionsStates.fromMap` | Yes — `emotions_states.dart:38` |
| Calibration path | Optional `IndividualNfbData` | None | Correct per spec `04-dart-api-classifiers.md:63` |
| Error messages | `'NfbClassifier ...'` | `'EmotionsClassifier ...'` | Yes — all 3 messages updated |

### Line-by-line checks

- **Imports (1–7):** `dart:async` is technically redundant (auto-imported) but matches existing pattern in `nfb_classifier.dart:1`. No unused imports beyond that. `individual_nfb_data.dart` correctly omitted since there's no calibration.
- **Factory constructor (35–40):** Guards on `device.isStarted`, throws `StateError`, delegates to private constructor with `device.serial`. Identical to NfbClassifier.
- **Private constructor (42–50):** Fires async `ClassifierMethods.create` with serial, catches into `_createError`. No calibration branch — correct.
- **Cached streams (71–79):** Both use `_eventStream` helper with correct EventChannel IDs and decoders. `EmotionsStates.fromMap` signature matches (`Map<Object?, Object?>` → `EmotionsStates`).
- **Guards (83–91):** `_checkNotDisposed` and `_checkReady` throw `StateError` with class-specific messages.
- **`_eventStream` helper (95–102):** Passes `{NeiryArgs.serial: _serial}` as stream arguments. Identical to NfbClassifier.
- **Stream getters (107–118):** Both guarded by `_checkNotDisposed()` + `_checkReady()`. Return cached `late final` streams.
- **`dispose()` (126–138):** Idempotent, awaits `_nativeReady`, skips destroy on `_createError`, calls `ClassifierMethods.dispose`. Identical to NfbClassifier.

### Barrel file (`neiry_kit.dart`)

Export added at line 1, before `nfb_classifier.dart`. Alphabetical order within classifiers group: `emotions` < `nfb` < `physio`. Correct.

### Runtime considerations

- `receiveBroadcastStream` on an EventChannel without a native StreamHandler won't crash — it simply won't emit events until the native bridge is registered (same as existing classifiers pre-bridge). No runtime risk.
- The `EmotionsStates.fromMap` factory expects a `ts` key (int) and five double keys. If native sends a map missing `ts`, this will throw a `TypeError` at `map['ts'] as int`. This is the same behavior as all other classifiers — sentinel-to-null conversion handles missing double fields but timestamp is required. Consistent, not a bug.

### Critical issues

None.

### Non-critical issues

None.

REVIEW_PASS
