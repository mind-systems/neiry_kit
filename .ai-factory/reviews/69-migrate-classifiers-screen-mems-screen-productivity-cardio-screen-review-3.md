# Code Review: Migrate classifiers_screen, mems_screen, productivity_cardio_screen (round 3)

Plan: `.ai-factory/plans/69-migrate-classifiers-screen-mems-screen-productivity-cardio-screen.md`
Previous reviews:
- `.ai-factory/reviews/69-migrate-classifiers-screen-mems-screen-productivity-cardio-screen-review-1.md`
- `.ai-factory/reviews/69-migrate-classifiers-screen-mems-screen-productivity-cardio-screen-review-2.md`

Scope reviewed:
- `example/lib/services/neiry_service.dart` (Task 1, plus round-2 fixes)
- `example/lib/providers/classifier_stream_providers.dart` (Task 2, plus round-2 fix)
- `example/lib/providers/nfb_calibration_provider.dart` (Task 3)
- `example/lib/screens/classifiers_screen.dart` (Task 4)
- `example/lib/screens/mems_screen.dart` (Task 5)
- `example/lib/screens/productivity_cardio_screen.dart` (Task 6)

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`)**: ✅ no violations. Edits stay in `example/`, all platform access goes through `NeiryService` / the public `neiry_kit` barrel.
- **Rules**: no `.ai-factory/RULES.md`; no `.ai-factory/skill-context/aif-review/SKILL.md`. Nothing project-specific to apply.
- **Roadmap (`.ai-factory/ROADMAP.md`)**: ✅ this is milestone 69/93. Pre-existing `calibration_screen.dart` analyzer errors remain deferred to milestone 94 per Task 7.

## Risk Level: 🟢 Low

Both round-2 critical findings were addressed:

- **Round-2 #1** — `disconnect()` now synthesizes a `NeiryConnectionState.disconnected` event into `_connectionStateController` (`neiry_service.dart:246-251`) *before* the fan-in subscriptions are cancelled. Because `_connectionStateController` is a `StreamController.broadcast`, the synthesized event is delivered synchronously to current listeners (Riverpod's `StreamProvider`), so `deviceConnectionStateProvider` transitions to `AsyncData(disconnected)` and the `isConnected` gates in all three screens correctly flip to `false` on user-initiated disconnect. The `!_connectionStateController.isClosed` guard is the right defensive check (the controller is only closed in `dispose()`, but `disconnect()` is also reachable from inside `dispose()` — fine because the close happens *after* the disconnect call returns).

- **Round-2 #2** — `_cardioCalibratedController` is now `StreamController<DateTime>.broadcast()` and emits `DateTime.now()` on each cardio-calibrated event (`neiry_service.dart:73, 227-230`). `cardioCalibratedProvider` is typed `StreamProvider<DateTime>` (`classifier_stream_providers.dart:67-69`). Consecutive `AsyncData<DateTime>(t1) != AsyncData<DateTime>(t2)` (DateTime equality is value-based but `DateTime.now()` resolves at microsecond granularity), so Riverpod's `defaultUpdateShouldNotify` returns `true` and the `ref.listen` callback in `_CardioCard` (`productivity_cardio_screen.dart:255-261`) fires on every calibration completion. `next.hasValue` semantics are unchanged.

I re-read every changed file in full. No new issues introduced by the round-2 fixes. The remaining items below are explicitly out of scope per the plan or cosmetic; flagging only for awareness.

## Open follow-ups (carried over, not blocking)

### Toggle subtitles still claim a behavior no caller delivers

**Files:**
- `example/lib/providers/nfb_calibration_provider.dart:12-21`
- `example/lib/screens/mems_screen.dart:30-39`
- `example/lib/screens/productivity_cardio_screen.dart:65-75`

`useMemsCalibrationToggleProvider` and `useCalibrationToggleProvider` exist; the SwitchListTile subtitles read "Takes effect on next connect"; no call site in the current codebase reads either provider before invoking `NeiryService.connect(...)`. Per the plan ("read sites are out of scope here") this is intentional, but the subtitle is currently a promise the codebase doesn't keep. Track a follow-up to wire the read side (likely in `device_screen.dart` next to the existing `nfbCalibrationProvider` read) when milestone 94 lands.

### Cosmetic: dimmed-loading and stacked-placeholder regressions

- `example/lib/screens/classifiers_screen.dart:114` — physio `loading:` no longer uses `Opacity(0.5)` and the message collapsed from "Waiting for first update..." to "Waiting for device...". Intentional per plan.
- `example/lib/screens/productivity_cardio_screen.dart:117-194` — when disconnected, Indexes and Metrics sections each render their own "Waiting for device..." placeholder separated by a `Divider`, giving a visually duplicated UI. Hoisting a single placeholder would tidy this.

Both cosmetic; safe to leave for a UX-polish pass.

## What looked correct

- The synthesized-disconnect fix is wired correctly: emission happens **before** subscriptions are cancelled and before the device is torn down, so the broadcast controller's synchronous delivery semantics propagate the event to current Riverpod listeners. The fan-in subscription on `_device!.connectionStateStream` is still alive during the synthesis, so any near-simultaneous native "disconnected" emission is also passed through — a harmless duplicate.
- `cardioCalibratedStream` type change is consistent across `NeiryService` (controller, getter), `classifier_stream_providers.dart` (provider type), and the listener in `_CardioCard` (uses `next.hasValue`, which is type-agnostic). No accidental references to the old `Stream<void>` shape remain (grepped: no `cardioCalibratedStream` usages outside the three touched files).
- `dispose()` close order still pairs each `add`-side controller with a matching `close()` after `disconnect()` returns — the two new controllers are appended at the end (`neiry_service.dart:343-344`), matching the documented intent that long-lived controllers stay open across connect cycles.
- All `log(..., name: 'Neiry')` calls remain byte-identical.
- `physioActionsProvider` / `productivityActionsProvider` `.notifier` invocations are correctly via `ref.read`, never `ref.watch`.
- `physioCalibratedProvider` is unaffected by the AsyncValue-equality issue because `PhysiologicalStatesBaselines` has no `==` override; each emission is a fresh instance, so identity inequality keeps `updateShouldNotify` returning `true`.
- The `!isConnected` gates and `onPressed: isConnected ? ... : null` guards in all three screens now reliably flip to the disabled state on user-initiated disconnect — the round-1 regression (`#1` stale data, `#2` no-op enabled buttons) is fully resolved.
- Toggle provider scope and naming (`useMemsCalibrationToggleProvider`, `useCalibrationToggleProvider`) match plan Task 3 exactly; doc comments correctly describe pure-preference semantics.

REVIEW_PASS
