# Plan Review: NeiryService Riverpod provider + device state providers

**Plan:** `.ai-factory/plans/65-neiryservice-riverpod-provider-device-state-providers.md`
**Risk Level:** 🟡 Medium

## Context Gates

- **ARCHITECTURE.md:** Not present at `.ai-factory/ARCHITECTURE.md` — no boundary/dependency check possible. WARN.
- **RULES.md:** Not present at `.ai-factory/RULES.md` — no explicit rules to enforce. WARN.
- **ROADMAP.md:** Milestone #89 ("NeiryService Riverpod provider + device state providers") matches this plan's scope. Follow-up milestones #90 (classifier stream providers), #91 (action notifiers), #92 (device/streams screen migration), #93 (classifier screens migration), #94 (calibration screen) are explicitly downstream. Plan alignment ✅.

## Critical Issues

### 1. Task 6's "expected errors" enumeration is incomplete — six classifier providers also import `active_device_provider.dart`

The plan asserts (line 126):

> the only new errors are unresolved imports of the two deleted files from screens/main — those errors are expected and will be cleared by the follow-up milestones.

This is wrong. `active_device_provider.dart` is currently imported by **eight** consumers, not three:

- `example/lib/main.dart` (acknowledged)
- `example/lib/screens/device_screen.dart` (acknowledged)
- `example/lib/providers/cardio_classifier_provider.dart` (**missed**)
- `example/lib/providers/emotions_classifier_provider.dart` (**missed**)
- `example/lib/providers/mems_classifier_provider.dart` (**missed**)
- `example/lib/providers/nfb_classifier_provider.dart` (**missed**)
- `example/lib/providers/physio_classifier_provider.dart` (**missed**)
- `example/lib/providers/productivity_classifier_provider.dart` (**missed**)

After Task 6, `flutter analyze` will produce broken-import errors in all six classifier-provider files plus `device_screen.dart` and `main.dart`. The roadmap shows those six classifier-provider files are slated for deletion in milestone #90 (the very next milestone), so the cascade is acceptable strategically — but the plan must accurately describe the expected error set so the implementer doesn't think something went wrong. Update Task 6's note to list all eight files explicitly, or narrow the "expected errors" sentence so it doesn't claim "only screens/main".

`classifiers_screen.dart` does **not** import `active_device_provider.dart` directly (confirmed by grep) — the plan's mention of `classifiers_screen.dart` in Task 6 is actually incorrect on the opposite side (it lists it as a remaining consumer, but it consumes via the classifier providers, not directly). Minor wording fix.

## Other Issues

### 2. `_artifactsController.close()` placement in `dispose()` is unspecified

Task 4 says "add `await _artifactsController.close();` in `dispose()`" without specifying where in the existing close sequence. Order doesn't affect correctness (all controllers are independent), but for consistency, place it next to the other device-stream controllers (after `_batteryController.close()`, before the classifier controllers) so the file structure stays grouped. Worth calling out so the implementer doesn't append it after `_productivityMetricsController.close()` arbitrarily.

### 3. Subtle behavioral change for `deviceConnectionStateProvider`: lost immediate `disconnected` emission

The current provider returns `Stream.value(NeiryConnectionState.disconnected)` when no device is active — consumers see `AsyncData(disconnected)` immediately. After this plan, the provider watches the service's broadcast stream which **emits nothing** until `connect()` is called. So before connect, consumers see `AsyncLoading` instead of `AsyncData(disconnected)`.

Plan acknowledges this and verifies that `deviceUiStateProvider` (the only known consumer that branches on connection state) uses `whenOrNull(data: ...)` so loading → `idle`, which matches the previous `disconnected` → `idle` mapping. Confirmed correct by reading `device_state_providers.dart:46-57`.

However, the broader audit should also note: `streams_screen.dart` and other consumers don't read `deviceConnectionStateProvider` directly (verified via grep — only `deviceUiStateProvider` and `deviceModeProvider` are watched by screens for the connection-derived state). So the behavior change is safe. Worth adding a one-line confirmation in the plan: "Verified consumers: only `deviceUiStateProvider` reads `deviceConnectionStateProvider` — safe."

### 4. `ref.onDispose(s.dispose)` is fire-and-forget — disposal is unawaited

`NeiryService.dispose()` returns `Future<void>` (`neiry_service.dart:281`). `ref.onDispose` expects `void Function()`. Dart accepts `Future-returning` callbacks here, but the future is discarded — the `ProviderContainer.dispose()` call returns before classifiers/locator are actually disposed. This is the same pattern already used in `device_locator_provider.dart` (existing code) and `main.dart`'s `_cleanupAndDispose()` explicitly awaits things outside Riverpod for that reason.

Not a blocker — existing milestone #92 ("Migrate device_screen and streams_screen") explicitly updates `main.dart`'s `_cleanupAndDispose()` to `await ref.read(neiryServiceProvider).dispose()`. So the await happens at app-teardown time even if Riverpod's `onDispose` doesn't await. Plan doesn't need to change here, but a one-line note ("Disposal is awaited explicitly in `main.dart` via milestone #92; `ref.onDispose` is a fire-and-forget fallback") would prevent confusion.

### 5. `service.scan(...).first` — verify behavior on early scan invalidation

Task 2 uses `service.scan(...).first` which returns a `Future<List<DeviceInfo>>`. The scan stream (from `DeviceLocator.requestDevices`) emits one list when the timer fires. If `deviceScanProvider` is invalidated mid-scan, the previous future is dropped on the Riverpod side, but the underlying native scan continues until `searchTime` elapses, and `.first` on a then-orphaned subscription will still resolve. Since each invalidation creates a new `service.scan(...)` call into the locator, two scans may overlap briefly. This is the **same behavior** as the current implementation (the existing provider also calls `locator.requestDevices(...).first`), so no regression — just noting that the plan inherits an existing concern, not introduces a new one. No change required.

### 6. Missing import note in Task 4 for `rxdart`

Task 4 keeps `throttleTime` extension calls. The existing `stream_providers.dart` already imports `package:rxdart/rxdart.dart` (line 5), so the rewrite preserves the import. Plan should note "preserve existing `rxdart` import" so an over-aggressive rewrite doesn't strip it.

## Positive Notes

- Phasing is clean: Phase 1 introduces the singleton, Phases 2–3 re-source providers, Phase 4 deletes legacy code — each commit is independently meaningful and reviewable.
- Correctly identifies that `NeiryService` does not yet expose `artifactsStream` (verified in `neiry_service.dart` — there are 13 stream getters but no artifacts), and prescribes the field + getter + subscription + close additions in one place with code snippets matching the surrounding controller pattern.
- Correctly chooses `ref.read` over `ref.watch` for `neiryServiceProvider` in the scan callback and explains the rationale (long-lived singleton).
- Preserves throttle timings (100 / 500 / 1000 ms) bit-for-bit — these were tuned for SDK emission rates and shouldn't change.
- Acknowledges the breadcrumb to follow-up milestones #92/#93 instead of trying to migrate screens in the same plan — keeps this milestone scoped.
- Correctly drops the `device == null → Stream.value(disconnected)` fallback after verifying downstream UI handling.
- `ResistanceMapNotifier` rewrite preserves the accumulation logic exactly and the pre-connect empty-map default falls out naturally from the broadcast controller emitting nothing pre-connect.

## Verdict

Fix the Task 6 expected-errors enumeration (Critical Issue #1) — that's the one substantive correction needed. The remaining items are clarifications that would make the implementer's job easier but don't affect correctness. After updating Task 6's note to enumerate all eight broken imports (or to drop the "only screens/main" claim), the plan is ready to implement.