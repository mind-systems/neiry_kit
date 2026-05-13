# Code Review: Migrate calibration_screen and CalibrationProvider

**Plan:** `.ai-factory/plans/71-migrate-calibration-screen-and-calibrationprovider.md`
**Scope:** `example/lib/screens/calibration_screen.dart` only
**Risk Level:** 🟢 Low (UI-only, example app)

## Changes reviewed

`git diff HEAD` shows three staged paths:

1. `.ai-factory/plan-reviews/71-migrate-calibration-screen-and-calibrationprovider-plan-review-1.md` — plan review doc, not code.
2. `.ai-factory/plans/71-migrate-calibration-screen-and-calibrationprovider.md` — plan doc, not code.
3. `example/lib/screens/calibration_screen.dart` — the only code change.

The code diff:

- Line 10: import swapped from `'../providers/nfb_classifier_provider.dart'` to `'../providers/classifier_stream_providers.dart'`.
- Lines 274–304 in `_NfbCard.build()`:
  - Removed `final classifier = ref.watch(nfbClassifierProvider);` and the `if (classifier == null) ... else` branch.
  - Replaced with a single `ref.watch(nfbStateProvider).when(loading/error/data)`.
  - `loading` text changed from `'Waiting for NFB data...'` to `'Waiting for device...'`.
  - `error` and `data` branches preserved verbatim (five `_BandRow`s for delta/theta/alpha/smr/beta).

## Correctness checks

### 1. Provider import resolves correctly

`example/lib/providers/classifier_stream_providers.dart:37` declares
`final nfbStateProvider = StreamProvider<NfbUserState>(...)` sourced from `neiryService.nfbStream`. The new import path is correct and the symbol exists. ✅

### 2. `_NfbCard` `.when(...)` is type-safe

`nfbStateProvider` is `StreamProvider<NfbUserState>` where `NfbUserState` is non-nullable. The `data:` callback receives `state` non-null, so `state.delta/theta/alpha/smr/beta` (themselves `double?`) flow into `_BandRow` which accepts `double?` and prints `—` for null. No null-deref risk. ✅

### 3. Behavior pre/post-connect

`NeiryService` constructs `_nfbController` (a broadcast `StreamController<NfbUserState>`) in the constructor and never closes it until `dispose()`. Before `connect()` there are no events on the controller, so `nfbStateProvider` stays in `AsyncLoading` and the UI shows `'Waiting for device...'`. This is the same end-user behavior the deleted `classifier == null` branch produced. ✅

After `connect()`, the fan-in subscription `_nfb!.stateStream.listen(_nfbController.add, ...)` (neiry_service.dart:203–206) starts forwarding events, the `AsyncValue` transitions through `AsyncLoading(hasValue: false)` → `AsyncData(NfbUserState)`, and the band rows render. ✅

After `disconnect()`, the fan-in subscription is cancelled (neiry_service.dart:254–258) but the controller stays open. The `AsyncValue` is sticky on its last `AsyncData(...)`, so the screen will continue to display the **last NFB sample seen** rather than reverting to `'Waiting for device...'`. This is a behavioral difference from the old code, which reset to `'Waiting for device...'` on disconnect (because the classifier handle became null). See "Findings" below.

### 4. No leftover references to deleted providers

Grep across `example/lib/` for `nfb_classifier_provider | nfbClassifierProvider | emotions_classifier_provider | physio_classifier_provider | cardio_classifier_provider | mems_classifier_provider | productivity_classifier_provider | device_locator_provider | active_device_provider` returns **zero matches**. The whole earlier-milestone migration is now consistent. ✅

### 5. `flutter analyze`

Ran `flutter analyze` inside `example/`:

```
Analyzing example...
No issues found! (ran in 6.6s)
```

Task 3's verification gate is genuinely clean. ✅

### 6. Code that was deliberately *not* touched is still correct

- `_CalibrationCard` / `_CalibrationCardState` (lines 39–114): unchanged. Still `ConsumerStatefulWidget` per the prior race-condition fix (ROADMAP item 84). `ref.listen` registrations on `calibrationTimerProvider` and `calibrationProvider` are inside the State's `build()` and remain stable across rebuilds.
- `_CalibrationDataCard` (lines 332–360): still reads `calibrationProvider.value ?? const IndividualNfbData()`, default-constructed fallback intact.
- `CalibrationNotifier` (`calibration_provider.dart`): untouched; `NfbCalibrator` is correctly used as a static class with no device dependency. The shared-state write to `nfbCalibrationProvider` is intact.
- `nfb_calibration_provider.dart`: untouched; still a plain `StateProvider<IndividualNfbData?>`.

## Findings

### 🟡 Finding 1 — Stale NFB band readings persist after disconnect

**Severity:** Low (example-app polish, not a crash)

**Location:** `example/lib/screens/calibration_screen.dart:288`

**Behavior change.** With the old code, `_NfbCard` showed `'Waiting for device...'` whenever the classifier handle was null — including immediately after `disconnect()`. With the new code, `nfbStateProvider` (backed by the long-lived `_nfbController` in `NeiryService`) holds onto its last `AsyncData(NfbUserState)` until either:
- the app process restarts, or
- `ref.invalidate(nfbStateProvider)` is called somewhere (it isn't), or
- the provider itself is auto-disposed when no widgets watch it (it stays watched while this screen is mounted).

Result: after the user disconnects, the Calibration tab will continue to display the **last delta/theta/alpha/smr/beta values seen before disconnect**, frozen in place. This is misleading — a user could mistake stale readings for a live device.

**Why it slipped through.** The plan's Task 2 rationale explicitly acknowledged that the new architecture cannot distinguish "no device" from "device connected, stream silent" and chose to fold both into the loading branch. That reasoning is sound for the *pre-connect* path, but it doesn't cover the *post-disconnect* path, where the stream has previously emitted and `AsyncValue` therefore sits in `AsyncData`, not `AsyncLoading`.

**Architectural note — same issue exists elsewhere.** This is not a new bug introduced by this milestone; the same pattern applies to every other classifier-backed `StreamProvider` migrated in milestones 90–93 (physio, emotions, cardio, productivity, mems). After disconnect, their last value is also retained. Whether to fix this is a design call that should be made across all the migrated screens, not just this one. Two reasonable options:

1. **Watch `deviceConnectionStateProvider` (or `deviceIsStartedProvider`) and gate the data branch on connection state.** Cleanest fix; requires touching every classifier-consuming widget.
2. **In `NeiryService.disconnect()`, emit a sentinel/error or close-and-reopen each multiplexer controller on connect.** Closing isn't possible (the doc-comment explicitly says controllers stay open across connect cycles); emitting a sentinel would require nullable stream types.

**Recommendation.** Acceptable to ship as-is for this milestone — the issue is project-wide, not specific to this PR, and the plan's deliberate trade-off was approved in the plan review. But the team should track this as a separate roadmap item ("disconnect resets classifier stream UI to loading state") rather than considering it solved by this migration. No change required here.

### 🟢 Finding 2 — Loading text wording is now ambiguous (pre-connect)

**Severity:** Cosmetic

**Location:** `example/lib/screens/calibration_screen.dart:289`

The single `'Waiting for device...'` loading message covers two distinct states that the old code distinguished:

| State | Old text | New text |
|---|---|---|
| No device connected | `'Waiting for device...'` | `'Waiting for device...'` |
| Connected, no NFB sample yet | `'Waiting for NFB data...'` | `'Waiting for device...'` |

In practice, the NFB classifier emits its first sample within a fraction of a second after `start()`, so the "connected but waiting" state is usually invisible. The plan acknowledged this. No action needed.

### 🟢 Finding 3 — Indentation / formatting

`dart format` would likely keep the new shape, but the inner `.when(...)` call is now a top-level statement-child inside the `Column` `children:` list with two levels of nesting; the original `else` branch had three levels. Visually the diff is clean. No issue.

## Things checked and cleared

- No race conditions introduced: `_NfbCard` is a `ConsumerWidget` (rebuilds on every change of `nfbStateProvider`), no `ref.listen` is used here, so no listener-deregistration concern (unlike the historical `_CalibrationCard` issue from ROADMAP item 84).
- No security concern — UI-only change in the example app, no I/O, no DTOs.
- No migration concern — no schema or persisted data touched.
- No threading concern — `nfbStream` is a Dart `Stream` from a `StreamController.broadcast` running on the platform-channel isolate, marshalled through Flutter's binary messenger as usual.
- No leaked subscription — `ref.watch(nfbStateProvider)` is managed by Riverpod, not by the widget.
- Type system: `NfbUserState` confirmed non-nullable in `lib/src/models/nfb_user_state.dart` (band fields are `double?`).

## Summary

The implementation matches the plan exactly: import swap + null-check removal + `.when()` consolidation, nothing more. `flutter analyze` is clean. The one notable behavioral change (stale band values frozen post-disconnect) is a pre-existing architectural side effect of the NeiryService multiplexer-stream design that affects every migrated classifier screen, not a regression unique to this milestone. The plan's acknowledged trade-off was approved at the plan-review stage.

No blocking issues.

REVIEW_PASS
