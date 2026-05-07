# Code Review: MemsData model

**Plan:** `.ai-factory/plans/44-memsdata-model.md`
**Changed files:** `lib/src/models/mems_data.dart` (new), `lib/neiry_kit.dart` (modified)

## Issues

### 1. Barrel export breaks alphabetical order (must fix)

**File:** `lib/neiry_kit.dart:17`

`mems_data.dart` is inserted between `eeg_data.dart` and `emotions_states.dart` — both start with `e`, and `m` sorts after both `e` and `i`. The plan review already flagged this exact problem, but it was not addressed during implementation.

Current (wrong):
```
export 'src/models/eeg_data.dart';           // e
export 'src/models/mems_data.dart';          // m  ← here
export 'src/models/emotions_states.dart';    // e
export 'src/models/individual_nfb_data.dart'; // i
export 'src/models/neiry_error.dart';        // n
```

Correct:
```
export 'src/models/eeg_data.dart';           // e
export 'src/models/emotions_states.dart';    // e
export 'src/models/individual_nfb_data.dart'; // i
export 'src/models/mems_data.dart';          // m  ← after i, before n
export 'src/models/neiry_error.dart';        // n
```

Move the `mems_data.dart` export from line 17 to between `individual_nfb_data.dart` (current line 19) and `neiry_error.dart` (current line 20).

## Verified (no issues)

- **Model structure** — `@immutable`, `const` constructor, `factory fromMap(Map<Object?, Object?>)` all follow the established pattern from `EegData`, `PpgData`, etc.
- **No sentinels** — Fields are non-nullable, matching the milestone spec that MEMS data is always valid when received.
- **Map keys** — `ax/ay/az/gx/gy/gz/ts` match what native bridges will serialize from `clCPoint3d` + `GetTimestampMilli`.
- **Type safety** — `num.toDouble()` handles both `int` and `double` from the platform channel codec. `ts` cast as `int` is correct for milliseconds-since-epoch.
- **No duplicate EventChannel** — `NeiryEvents.memsData` already exists at `channel_names.dart:42`; no duplicate was added.
- **Record types** — New pattern in the codebase but appropriate for grouping x/y/z triplets. Dart 3 records are supported by the project's SDK constraint.
