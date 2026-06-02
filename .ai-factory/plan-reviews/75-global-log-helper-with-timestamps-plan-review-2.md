# Plan Review 2: Global log helper with timestamps

**Plan:** `.ai-factory/plans/75-global-log-helper-with-timestamps.md`
**Files Reviewed:** plan + 12 target source files + `example/lib/` structure + ARCHITECTURE.md + plan-review-1
**Risk Level:** 🟡 Medium

## Status of prior review (review-1)

Both review-1 findings are correctly resolved in this revision:

- **Finding #1 (`error:`/`stackTrace:` forwarding).** Resolved. Task 1's signature now declares `Object? error, StackTrace? stackTrace` and forwards them to `log(...)`. The Context section calls this out explicitly, and Task 4 notes the 4 `sound_service_provider.dart` call sites now migrate cleanly. ✅
- **Finding #2 (barrel pollution).** Resolved the cleaner way. `nlog` is no longer exported from the barrel; the example app gets its own `example/lib/utils/nlog.dart` copy. Task 2, the Context, and the Notes all consistently state "do **not** export `nlog`." This honors ARCHITECTURE.md point 4 ("The barrel export is the public API… exports only what `mind_mobile` needs"). ✅

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`)** — `PASS`. Point 4 (public-API barrel) is now respected by keeping `nlog` internal + duplicating into the example. Point 6 ("Example app covers every feature") is unaffected — this is a diagnostic refactor, no feature surface change.
- **Rules (`.ai-factory/RULES.md`)** — not present. No rule gate to apply. `WARN` (optional file absent).
- **Roadmap (`.ai-factory/ROADMAP.md`)** — present. Internal diagnostic refactor, no user-facing feature; milestone linkage optional, not a blocker.

## Critical Issues

### 1. Task 4's per-directory import-path guidance is wrong for 9 of 10 files (build break)

`example/lib/utils/` sits **one** level below `example/lib/`. The directories holding the target files — `screens/`, `providers/`, `services/` — are all **siblings** of `utils/`, also one level below `example/lib/`. So every file under those three directories reaches the helper with a **single** `../`:

```
example/lib/utils/nlog.dart          ← target
example/lib/screens/device_screen.dart      → import '../utils/nlog.dart';
example/lib/providers/device_scan_provider.dart → import '../utils/nlog.dart';
example/lib/services/neiry_service.dart      → import '../utils/nlog.dart';
example/lib/router.dart                      → import 'utils/nlog.dart';   (no ../)
```

This is confirmed by an existing import in the repo:

```dart
// example/lib/providers/rate_providers.dart:3
import '../utils/rate_counter.dart';
```

`rate_counter.dart` lives in `example/lib/utils/`, and a file in `providers/` imports it with a single `../utils/`. The same depth applies to `nlog.dart`.

The plan's parenthetical guidance in Task 4 states the opposite:

> "…`../../utils/nlog.dart` from files under `example/lib/screens/` and `example/lib/providers/`, `../utils/nlog.dart` from `example/lib/services/` and `example/lib/router.dart`."

Mapping that against reality:

| File location | Plan says | Correct | Verdict |
|---|---|---|---|
| `example/lib/screens/*` (6 files) | `../../utils/nlog.dart` | `../utils/nlog.dart` | ❌ wrong — resolves to `example/utils/`, escapes `lib/`, won't compile |
| `example/lib/providers/*` (2 files) | `../../utils/nlog.dart` | `../utils/nlog.dart` | ❌ wrong — same |
| `example/lib/services/neiry_service.dart` | `../utils/nlog.dart` | `../utils/nlog.dart` | ✅ correct |
| `example/lib/router.dart` | `../utils/nlog.dart` | `utils/nlog.dart` | ❌ wrong — `router.dart` is directly in `lib/`; `../utils/` resolves to `example/utils/` |

Only `services/neiry_service.dart` is right. An implementer who follows the parenthetical "correct relative depth" produces unresolvable imports in 9 of the 10 example files (6 screens + 2 providers + router) → compile failure.

Note the leading instruction in the same task — *"add `import '../utils/nlog.dart';`"* — is actually correct for screens, providers, and services, and only wrong for `router.dart`. The damage comes from the parenthetical "correct relative depth" override, which inverts the screens/providers depth and mis-states router.

**Resolution.** Replace Task 4's path guidance with:

- `example/lib/screens/*`, `example/lib/providers/*`, `example/lib/services/*` → `import '../utils/nlog.dart';`
- `example/lib/router.dart` → `import 'utils/nlog.dart';`

(Alternatively, instruct the implementer to verify each import resolves rather than hard-coding depths — but since the plan chose to enumerate depths, the enumeration must be correct.)

## Verified Assumptions (correct)

- **File coverage is complete and exact.** `grep` for `log(` / `dart:developer` confirms Task 3's two `lib/src` files (`device.dart`, `device_locator.dart`) and Task 4's ten example files are the complete set — no missed call site under `lib/` or `example/lib/`. Counts: `neiry_service.dart` 28, `device_screen.dart` 12, `calibration_screen.dart` 7, `sound_service_provider.dart` 4, `device_scan_provider.dart`/`classifiers_screen.dart`/`productivity_cardio_screen.dart` 3 each, `router.dart`/`streams_screen.dart`/`mems_screen.dart` 1 each.
- **`error:`/`stackTrace:` sites are exactly the 4 in `sound_service_provider.dart`** (lines 18, 24, 30, 36) — matches the plan.
- **`device.dart:75` multi-line `log(...)`** is real and passes `name: 'neiry_kit'`; Task 3 correctly calls it out.
- **No leftover local timestamp helpers** in `device.dart` / `device_locator.dart` — Task 3's "remove if present (none currently exist)" is accurate.
- **`lib/src/util/` does not yet exist** — Task 1 creating the new dir is fine. (Existing example helpers live in `example/lib/utils/` — note `util` vs `utils`: plugin uses `lib/src/util/`, example uses `example/lib/utils/`; the plan spells both correctly and consistently, so no collision.)
- **Plugin API files import the helper with `../util/nlog.dart`** — `device.dart` and `device_locator.dart` are in `lib/src/api/`, so `../util/nlog.dart` → `lib/src/util/nlog.dart`. Task 3's stated import path is correct.

## Positive Notes

- Both review-1 findings addressed, and the barrel one was resolved the architecturally cleaner way (internal helper + example-local copy) rather than papering over it.
- Task ordering and dependencies are sound (helper → example copy → consumers).
- Single-commit scope and the "don't touch `test/`" constraint are correct (tests reference the public API, not `log()`).
- The accepted ~8-line duplication is explicitly justified against ARCHITECTURE.md point 4 — a deliberate, documented trade-off, not an oversight.

## Required Before Implementation

Fix the Task 4 import-path table (Critical Issue #1). It is a one-line correction but, as written, breaks the build in 9 of 10 example files. Everything else in the plan is accurate and ready.
