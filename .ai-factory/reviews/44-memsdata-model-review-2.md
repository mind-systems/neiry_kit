# Code Review: MemsData model (round 2)

**Plan:** `.ai-factory/plans/44-memsdata-model.md`
**Changed files:** `lib/src/models/mems_data.dart` (new), `lib/neiry_kit.dart` (modified)

## Previous review issue

**Barrel export ordering — FIXED.** `mems_data.dart` is now at line 19, correctly between `individual_nfb_data.dart` and `neiry_error.dart`.

## Verified

- **Model structure** — `@immutable`, `const` constructor, `factory fromMap(Map<Object?, Object?>)` follow established pattern (`EegData`, `PpgData`, etc.).
- **No sentinels** — All fields non-nullable, correct per milestone spec (MEMS data is always valid when received).
- **Map keys** — `ax/ay/az/gx/gy/gz/ts` match what native bridges will serialize from `clCPoint3d` + `GetTimestampMilli`.
- **Type safety** — `num.toDouble()` handles both `int` and `double` from `StandardMessageCodec`. `ts` cast as `int` is correct for milliseconds-since-epoch.
- **No duplicate EventChannel** — `NeiryEvents.memsData` already exists at `channel_names.dart:42`; no duplicate added.
- **Barrel ordering** — alphabetically correct after the fix.
- **Record types** — New pattern vs existing flat-field models, but appropriate for 3D coordinate data. Dart 3 records supported by project SDK constraint.

REVIEW_PASS
