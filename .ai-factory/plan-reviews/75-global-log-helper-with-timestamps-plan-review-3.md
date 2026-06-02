# Plan Review: Global log helper with timestamps (iteration 3)

## Review Summary

**Plan:** `75-global-log-helper-with-timestamps.md`
**Files Targeted:** 2 new (`lib/src/util/nlog.dart`, `example/lib/utils/nlog.dart`) + 12 modified
**Risk Level:** 🟢 Low

This is the third review iteration. The plan now correctly incorporates the two findings
that shaped it (error/stackTrace forwarding, no barrel export). Every factual claim in the
plan was re-verified against the live codebase and all hold.

## Context Gates

### Architecture (`.ai-factory/ARCHITECTURE.md`) — PASS
- Plan cites "ARCHITECTURE.md line 110" for the public-API rule. Verified: the relevant rule
  is **#4 — "The barrel export is the public API. `neiry_kit.dart` exports only what
  `mind_mobile` needs. Internal `src/` classes are not re-exported."** The decision to keep
  `nlog` out of the barrel and give the example app its own copy is consistent with this
  boundary. `nlog` is a plugin-internal diagnostic, correctly kept off the public surface.
- Confirmed `lib/neiry_kit.dart` exports no utility/logging symbol today; the plan preserves that.

### Rules (`.ai-factory/RULES.md`) — WARN (file not present)
- No `RULES.md` found. No explicit-convention gate to apply. Non-blocking.

### Roadmap (`.ai-factory/ROADMAP.md`) — WARN (no linkage stated)
- This is a small internal tooling/refactor change (replacing `log()` with a timestamped
  helper); roadmap linkage is optional and its absence is non-blocking.

## Verification of Plan Claims

All claims checked directly against the codebase:

| Claim | Status |
|---|---|
| `lib/src/util/` does not yet exist (new directory) | ✅ Confirmed — `lib/src/` has `api/`, `channel/`, `models/`, `processing/` only |
| `example/lib/utils/` exists and holds `rate_counter.dart` | ✅ Confirmed |
| `dart:developer` imported in `device.dart` & `device_locator.dart` | ✅ Confirmed (line 2 in both) |
| Only the `log` symbol is used from `dart:developer` (no `Timeline`/`Service`/`inspect`) | ✅ Confirmed — safe to drop the import |
| Multi-line `log(...)` call at `device.dart:75` | ✅ Confirmed |
| 4 `log(...)` calls with `error:`/`stackTrace:` in `sound_service_provider.dart` (lines 18/24/30/36) | ✅ Confirmed — helper signature forwards both |
| Example Task-4 file list is complete | ✅ Confirmed — `grep` for `dart:developer` in `example/lib/` returns exactly the 10 listed files |
| 6 screens + 2 providers + 1 service + `router.dart` = 10 files | ✅ Confirmed exact match |
| Relative import paths (`../utils/nlog.dart`, `utils/nlog.dart`) | ✅ Confirmed against existing `import '../utils/rate_counter.dart';` |
| No raw `log(` usage outside `dart:developer` (no logger/catalog false positives) | ✅ Confirmed |

## Critical Issues

None.

## Minor Notes (non-blocking)

1. **Mechanical replace caution.** Task 3/4 say "replace every `log(...)` with `nlog(...)`".
   A naive global `log(` → `nlog(` substitution is safe here (verified: no `catalog(`,
   `backlog(`, `developer.log`, or other `log`-suffixed identifiers in the target files),
   but the implementer should replace at the call boundary rather than blind text-replace.

2. **Output-format example is cosmetic.** Task 1 states the line reads
   `[NeiryService] [02:11:41.922] step 1`. The `name:` prefix placement is rendered by the
   `dart:developer` / logcat formatter, not by `nlog` itself (which only prepends `[$ts] `
   to the message). This is descriptive only and does not affect correctness.

3. **Intentional duplication acknowledged.** The ~8-line helper is duplicated between plugin
   and example by design (example cannot import `lib/src/`, and barrel export is disallowed).
   The plan explicitly justifies this trade-off — accepted.

## Positive Notes

- Dependencies between tasks are correctly ordered (Task 2/3 depend on Task 1; Task 4 on Task 2).
- The plan correctly scopes out `test/` files and confirms no leftover local timestamp helpers exist.
- Single-commit guidance aligns with global commit conventions (no type prefix, imperative-ish phrase).
- Every file path, directory-existence assumption, and API-usage claim is accurate.

PLAN_REVIEW_PASS
