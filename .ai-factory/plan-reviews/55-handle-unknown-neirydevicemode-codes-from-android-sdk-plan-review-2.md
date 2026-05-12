# Plan Review #2: Handle unknown NeiryDeviceMode codes from Android SDK

Plan: `.ai-factory/plans/55-handle-unknown-neirydevicemode-codes-from-android-sdk.md`

## Verification Summary

| Plan claim | Verified against | Status |
|---|---|---|
| `enums.dart` lines 57–65: `NeiryDeviceMode.fromCode` throws `ArgumentError` for unknown codes | `lib/src/channel/enums.dart:57-65` | ✅ confirmed |
| `NeiryDeviceType.fromCode` / `NeiryConnectionState.fromCode` remain throwing | `lib/src/channel/enums.dart:28-33, 86-91` | ✅ confirmed (untouched per plan) |
| `device.dart:65-68`: `_modeChangedStream` built via `_eventStream` | `lib/src/api/device.dart:65-68` | ✅ confirmed |
| `device.dart:130-132`: `_modeChangedStream` listener in `_startStateTracking` | `lib/src/api/device.dart:130-132` | ✅ confirmed |
| `device.dart:231`: public `modeChangedStream` getter | `lib/src/api/device.dart:231-234` | ✅ confirmed |
| `_eventStream<T>` is generic and does not perform null-filtering | `lib/src/api/device.dart:112-119` | ✅ confirmed |
| `dart:developer` is not yet imported in `device.dart` | `lib/src/api/device.dart:1-12` (only `dart:async` + flutter/services) | ✅ confirmed — plan correctly tells implementer to add it |
| Test file groups for `fromCode throws…` at lines 285–294 | `test/channel_names_test.dart:285-294` | ✅ confirmed |
| `test/api_test.dart` asserts `modeChangedStream is Stream<NeiryDeviceMode>` | `test/api_test.dart:227-232` | ✅ confirmed — survives the change because outer stream type is preserved |
| No other Dart code calls `NeiryDeviceMode.fromCode` | `Grep NeiryDeviceMode.fromCode` → only `device.dart:67` + tests | ✅ confirmed |

### Context Gates

- **ARCHITECTURE.md** — present; no boundary/dependency conflict (change is confined to the Dart-side public API surface, no native bridge changes). No issues.
- **RULES.md** — absent. `WARN` (informational only — no project rules to apply).
- **ROADMAP.md** — task is anchored in the "Bug fixes & hardening" section at line 76 and reads as the source of this plan. ✅ aligned.

## Critical Issues

### 1. `Stream.whereType<T>()` does not exist — Task 2 example will not compile

The plan's Task 2 prescribes filtering nulls via `.whereType<NeiryDeviceMode>()` and calls this "single-call, idiomatic Dart — preferred over a separate `.where(!= null).cast<>()` two-step". This is incorrect.

`whereType<T>()` is an `Iterable` extension method — it is **not** defined on `Stream` in `dart:async`. Verified against the project's Dart SDK (3.11.0):

```text
Error: The method 'whereType' isn't defined for the type 'Stream<int?>'.
 - 'Stream' is from 'dart:async'.
```

Following the plan literally produces a compile error in `lib/src/api/device.dart`. The roadmap entry at `.ai-factory/ROADMAP.md:76` also assumes `whereType` works on streams, so the same correction propagates from there.

**Fix the plan to use one of:**

- **Two-step `where + cast` (simplest, idiomatic):**
  ```dart
  .map((raw) {
    final code = (raw as Map<Object?, Object?>)['mode'] as int;
    final mode = NeiryDeviceMode.fromCode(code);
    if (mode == null && _loggedUnknownModeCodes.add(code)) {
      developer.log(
        'Ignoring unknown NeiryDeviceMode code $code from native SDK',
        name: 'neiry_kit',
      );
    }
    return mode; // NeiryDeviceMode?
  })
  .where((m) => m != null)
  .cast<NeiryDeviceMode>();
  ```
  Verified to compile and produce the expected output on Dart 3.11.

- **`expand` emitting `[mode]` or empty:**
  ```dart
  .expand<NeiryDeviceMode>((raw) { ... return mode == null ? const [] : [mode]; })
  ```

Either is fine; the first matches the plan's intent more closely. The plan's own dismissal of `.where + .cast` as a "two-step" workaround is moot because it is the canonical Stream equivalent of `Iterable.whereType` and there is no one-step alternative in the core SDK.

This must be corrected before implementation, otherwise the implementer either ships broken code or has to invent the fix on their own — at which point the plan is no longer authoritative.

## Minor Issues

### 2. Wrong class name in Task 2

Task 2 says "Add a private field on `_NeiryDevice` (next to other per-instance state near the top of the class)". The actual class is `Device` (no leading underscore, no `Neiry` prefix) — see `lib/src/api/device.dart:31`. There is no `_NeiryDevice` symbol in the codebase. Cosmetic but worth fixing so the implementer is not searching for a class that does not exist.

### 3. `Logging: minimal` setting + `developer.log` choice

The plan declares `Logging: minimal` in its Settings block and then adds a `developer.log` call with a once-per-unknown-code gate. The gating is good and matches the "minimal" intent. No change required, but worth a one-line note in the plan that the single `developer.log` per unknown code is the intentional realisation of the "minimal logging" requirement — this was flagged by review #1 and remains slightly under-explained.

## Positive Notes

- Correct decision to leave `NeiryDeviceType.fromCode` and `NeiryConnectionState.fromCode` throwing — those flow through `createDevice` / connection state paths where an unknown code really is a bug; only mode events have the "transient noise from native SDK" property.
- Correct decision to scope the de-duplication set to a `Device` instance — a reconnect produces a fresh `Device`, so any new burst of unknowns will be re-logged once, which is the right operational signal.
- Correct decision to avoid placeholder enum values like `unknown7(7)` — future undocumented codes are handled in one place.
- Test maintenance (Task 3) is precise: removes the now-stale `NeiryDeviceMode.fromCode(999) throws` assertion while preserving the `NeiryDeviceType` and `NeiryConnectionState` cases that still throw, and adds positive coverage for both the real-world `7` and the synthetic `999`.
- Outer `Stream<NeiryDeviceMode>` type is preserved, so the public API (`modeChangedStream` getter, the listener in `_startStateTracking`, and `test/api_test.dart:227-232`) keeps working without further touch-ups.
- Tasks are correctly ordered with explicit `depends on Task 1` markers.

## Verdict

Plan is architecturally correct and well-scoped. **One blocker remains:** the prescribed `.whereType<NeiryDeviceMode>()` call on a `Stream` will not compile under Dart 3.11. Once Task 2's example is rewritten to use `.where((m) => m != null).cast<NeiryDeviceMode>()` (or equivalent), and the class-name typo in Task 2 is corrected, the plan is ready for implementation.
