## Code Review Summary

**Plan Reviewed:** `45-memsclassifier-dart-api.md`
**Files Reviewed:** 7 (plan + 6 source files for context)
**Risk Level:** Low

### Context Gates

- **ARCHITECTURE.md:** WARN — no issues. Plan follows the established classifier pattern (api/ -> channel/ + models/), uses the correct MethodChannel/EventChannel contract, and places the new file in `lib/src/api/classifiers/` per the folder structure. Dependency rules are respected.
- **RULES.md:** file does not exist — WARN (non-blocking).
- **ROADMAP.md:** no issues. The plan implements the second sub-task of the "MEMS classifier" milestone (`MEMSClassifier Dart API`), which directly follows the already-completed `MemsData model` sub-task.

### Critical Issues

None.

### Issues

**1. Barrel file export placement breaks alphabetical order (Task 3)**

The plan says: *"Place it after the existing classifier exports (after `cardio_classifier.dart`, line 1) to keep alphabetical order among classifiers."*

Current barrel file order (lines 1-5):
```
1: cardio_classifier.dart
2: emotions_classifier.dart
3: nfb_classifier.dart
4: physio_classifier.dart
5: productivity_classifier.dart
```

Alphabetically, `mems_classifier.dart` sorts between `emotions` and `nfb` (e < **m** < n), so the export should go on **line 3** (after `emotions_classifier.dart`), not line 2 (after `cardio_classifier.dart`). Placing it after line 1 would produce `cardio → mems → emotions`, which breaks the alphabetical ordering the plan claims to maintain.

### Positive Notes

- The plan correctly identifies that `NeiryEvents.memsData` already exists (line 42 of `channel_names.dart`) and explicitly warns not to add a duplicate. Good attention to existing state.
- The `Stream<List<MemsSample>>` type is the right choice for timed data that delivers multiple samples per callback (matching the `clCMEMSTimedData` accessor pattern with `GetCount`), and the custom mapping (`cast raw to List, then .map(MemsSample.fromMap).toList()`) correctly deviates from the `_eventStream` helper used by single-value classifiers.
- The private constructor, `_nativeReady` / `_createError` pattern, `_checkNotDisposed()` / `_checkReady()` guards, and idempotent `dispose()` all match `CardioClassifier` exactly — verified line-by-line against the source.
- Scope is appropriately narrow: 3 tasks, Dart-only, no native bridge work (those are separate roadmap milestones). Clean separation of concerns.

PLAN_REVIEW_PASS
