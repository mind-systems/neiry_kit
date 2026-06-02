# Plan Review: Global log helper with timestamps

**Plan:** `.ai-factory/plans/75-global-log-helper-with-timestamps.md`
**Files Reviewed:** plan + 12 target source files + ARCHITECTURE.md
**Risk Level:** 🟡 Medium

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`)** — `WARN`. Line 89 confirms `example/` may import the plugin only via the barrel `neiry_kit.dart`, which validates Task 2/Task 4's barrel approach. However, line 110 states *"The barrel export is the public API. `neiry_kit.dart` exports only what `mind_mobile` needs."* Exporting an internal diagnostic helper (`nlog`) through the public barrel leaks a logging utility into the API surface that `mind_mobile` consumes. See finding #2.
- **Rules (`.ai-factory/RULES.md`)** — not present. No rule gate to apply.
- **Roadmap (`.ai-factory/ROADMAP.md`)** — present. This is a small internal diagnostic refactor (no user-facing feature); milestone linkage is optional and not required to block.

## Critical Issues

### 1. `sound_service_provider.dart` `log()` calls use `error:` / `stackTrace:` — `nlog` cannot accept them (build break)

Task 1 defines the helper as `void nlog(String message, {String name = 'neiry_kit'})`. Task 4 instructs replacing every `log(...)` with `nlog(...)`, "preserving any `name:` argument." But `sound_service_provider.dart` has 4 calls that pass **`error:` and `stackTrace:`** as well:

```dart
// example/lib/providers/sound_service_provider.dart:18, 24, 30, 36
log('playStageStart failed: $e', name: 'SoundService', error: e, stackTrace: st);
```

`nlog` does not declare `error` or `stackTrace` parameters, so a mechanical `log(` → `nlog(` swap that preserves those arguments **will not compile** ("no named parameter 'error'"). Stripping them silently drops structured error/stack-trace data from logcat — a regression for the one place in the example that actually logs caught exceptions with stack traces.

The plan does not mention this case at all. Resolve one of:

- **(Recommended)** Extend the helper to forward both:
  ```dart
  void nlog(String message, {String name = 'neiry_kit', Object? error, StackTrace? stackTrace}) {
    final n = DateTime.now();
    final ts = '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}:'
        '${n.second.toString().padLeft(2, '0')}.${n.millisecond.toString().padLeft(3, '0')}';
    log('[$ts] $message', name: name, error: error, stackTrace: stackTrace);
  }
  ```
  Then the four calls migrate cleanly.
- Or leave those four calls on raw `log()` — but this **contradicts** Task 4's own acceptance check ("verify no `dart:developer` import or raw `log(` call remains anywhere under `example/lib/`") and would require keeping `import 'dart:developer';` in that file. The plan is internally inconsistent until this is decided.

This single decision must be made explicit in Task 1 and Task 4 before implementation; otherwise the implementer hits either a compile error or a self-contradicting verification step.

## Warnings / Architectural Notes

### 2. Exporting `nlog` from the barrel pollutes the public API (ARCHITECTURE.md line 110)

Task 2 exports `nlog` from `lib/neiry_kit.dart`, making it part of the public API that `mind_mobile` will see. ARCHITECTURE.md says the barrel "exports only what `mind_mobile` needs." A diagnostic logger is plugin-internal.

The reason it's exported is solely so the **example** app can reach it (example can't import `lib/src/`). The referenced note (`25-global-log-helper.md`, step 4) explicitly offered the cleaner alternative: keep `nlog` internal to `lib/src/` (imported directly within `lib/`, no barrel export) and give the example app its own `example/lib/utils/nlog.dart`. That keeps the public API clean at the cost of one duplicated ~6-line helper.

This is a judgment call, not a blocker — but the plan picked the public-export route without acknowledging the architectural trade-off. Recommend either documenting why the export is acceptable, or switching to the example-local copy.

## Verified Assumptions (correct)

- **File coverage is complete.** Every file containing a `log(` call is accounted for: `lib/src/api/device.dart`, `lib/src/api/device_locator.dart` (Task 3) and all 10 example files (Task 4). No `log()` call site is missed elsewhere under `lib/` or `example/lib/`.
- **Barrel-import claim is accurate.** Of the Task 4 files, only `router.dart` and `sound_service_provider.dart` lack `import 'package:neiry_kit/neiry_kit.dart';` — exactly the two the plan says to add it to. The other eight already import the barrel.
- **No leftover `_ts()` helpers** exist in `device.dart` / `device_locator.dart`; Task 3's "remove if present" is correctly conditional.
- **`lib/src/util/` does not yet exist** — Task 1 creating `lib/src/util/nlog.dart` (new dir) is fine.
- The multi-line `log(...)` call at `device.dart:75` is the only non-single-line site; a mechanical replace must keep its `name:` argument (it does pass one).

## Positive Notes

- Tasks are correctly ordered with explicit dependencies (helper → export → consumers).
- The single-commit scope and "don't touch `test/`" constraint are appropriate and correct (tests reference the public API, not `log()`).
- Output-format example in Task 1 (`[NeiryService] [02:11:41.922] step 1`) is consistent with how `dart:developer log` renders the `name:` prefix plus the timestamped message; no conflict with the note's example (the difference is only the `name` value).

## Required Before Implementation

Address finding #1 (make the `error:`/`stackTrace:` handling explicit in Tasks 1 and 4). Consider finding #2. The rest of the plan is sound.
