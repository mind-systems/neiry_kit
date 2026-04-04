## Plan Review: Productivity Models

**Plan:** `.ai-factory/plans/04-productivity-models.md`
**Files Reviewed:** 3 tasks targeting 3 new files in `lib/src/models/`
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md** — WARN: The folder structure example only lists `productivity_metrics.dart` in `models/`, not `productivity_indexes.dart` or `productivity_baselines.dart`. Non-blocking — the structure is illustrative, not exhaustive, and the roadmap explicitly names all three files.
- **RULES.md** — file does not exist. WARN (no conventions to check against).
- **ROADMAP.md** — WARN: The roadmap milestone description says "11 nullable floats" for `ProductivityMetrics`, but both the C header and the plan correctly count 10 float fields. Minor roadmap typo, not a plan defect.

### Verification Against C SDK Header

Checked `official/iOS/CapsuleClient.framework/Headers/CProductivity.h` line by line:

**ProductivityBaselines** — 6 sentinel floats + timestamp. Plan lists `gravity`, `productivity`, `fatigue`, `reverseFatigue`, `relaxation`, `concentration`. Matches `clCProductivity_Baselines` exactly. ✅

**ProductivityIndexes** — 2 enum ints (`relaxation` → `clCProductivity_RecommendationValue`, `stress` → `clCProductivity_StressValue`), 6 sentinel float baselines, 1 bool (`hasArtifacts`), + timestamp. Plan matches `clCProductivity_Indexes` exactly. ✅

**ProductivityMetrics** — 10 sentinel floats (`fatigueScore`, `reverseFatigueScore`, `gravityScore`, `relaxationScore`, `concentrationScore`, `productivityScore`, `currentValue`, `alpha`, `productivityBaseline`, `accumulatedFatigue`), 1 enum int (`fatigueGrowthRate` → `clCProductivity_FatigueGrowthRate`), 1 binary blob (`artifactsData` `uint8_t*` + `artifactsSize` → `Uint8List?`), + timestamp. Plan matches `clCProductivity_Metrics` exactly. ✅

### Pattern Consistency Check

Compared against implemented models (`NfbUserState`, `PhysiologicalStatesValue`, `EmotionsStates`):

- `@immutable` annotation + `import 'package:flutter/foundation.dart'` — specified. ✅
- `import 'internal/sentinel.dart'` for `orNull()` — specified. ✅
- `const` constructor with `required` named params for always-valid fields, optional for sentinel fields — specified. ✅
- `factory fromMap(Map<Object?, Object?> map)` signature — specified. ✅
- Timestamp decoded via `DateTime.fromMillisecondsSinceEpoch(map['ts'] as int)` — specified. ✅
- Sentinel floats decoded via `orNull(map[key])` — specified. ✅
- Constructor ordering (required first, optional after) matches `PhysiologicalStatesValue` — specified. ✅
- Field declaration ordering (timestamp → float scores → int/bool flags) matches `PhysiologicalStatesValue` — specified. ✅
- `Uint8List?` handling delegates size-zero → null to native bridge, Dart model only casts — correct design. ✅
- `import 'dart:typed_data'` for `Uint8List` in `ProductivityMetrics` — specified. ✅

### Scope Check

- Plan is correctly scoped to Dart models only (no barrel export, no tests, no native bridges) — these are separate roadmap milestones.
- No missing files: three C structs → three Dart classes, all accounted for.
- No missing fields: every field in each C struct has a corresponding Dart field.
- No extraneous fields: plan does not invent fields absent from the C header.

### Positive Notes

- Plan is precise about which fields are `required` vs optional, matching the SDK's guarantee semantics (enums/bools are always initialized, floats use sentinel).
- Explicit mention of doc comments referencing C struct names and sentinel-to-null behavior — maintains documentation consistency.
- Constructor and field ordering instructions are detailed enough to prevent implementation ambiguity.
- The `Uint8List?` boundary (native bridge sends null for size=0, Dart just casts) is the correct split of responsibility.

PLAN_REVIEW_PASS
