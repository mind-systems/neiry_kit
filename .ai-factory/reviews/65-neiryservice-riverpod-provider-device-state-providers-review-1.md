# Code Review: NeiryService Riverpod provider + device state providers

**Plan:** `.ai-factory/plans/65-neiryservice-riverpod-provider-device-state-providers.md`
**Scope reviewed:** all changes in `git diff HEAD` for the milestone — `neiry_service_provider.dart` (new), `device_scan_provider.dart`, `device_state_providers.dart`, `stream_providers.dart`, `neiry_service.dart`, plus deletions of `active_device_provider.dart` and `device_locator_provider.dart`.

## Summary

Implementation matches the plan task-by-task:

- `neiryServiceProvider` is a plain `Provider<NeiryService>` with `ref.onDispose(s.dispose)` (Task 1).
- `deviceScanProvider` reads `neiryServiceProvider` via `ref.read` and calls `service.scan(...).first` (Task 2).
- `deviceConnectionStateProvider` and `deviceModeProvider` now watch `neiryServiceProvider` directly; `deviceIsStartedProvider` + `deviceUiStateProvider` unchanged (Task 3).
- `eegProvider`/`psdProvider`/`batteryProvider`/`artifactsProvider` swap `activeDeviceProvider` → `neiryServiceProvider`, throttle timings preserved bit-for-bit (Task 4).
- `ResistanceMapNotifier.build()` rewritten to subscribe to `service.resistanceStream`; accumulation logic preserved (Task 5).
- `active_device_provider.dart` + `device_locator_provider.dart` deleted (Task 6).
- `NeiryService` gains `_artifactsController` field (line 53), fan-in subscription in `connect()` (lines 163–166), `artifactsStream` getter (line 323), and `_artifactsController.close()` in `dispose()` (line 297) — placed after `_batteryController.close()`, before the classifier controllers, per the plan.

`rxdart` import preserved in `stream_providers.dart:5`. No accidental regressions in throttle timings (100/500/1000 ms).

## Findings

### 1. Expected broken imports — verified to match plan scope

Per Task 6, the example app will not compile after this milestone until follow-ups land. Grep confirms eight files import the deleted providers, all of which are explicitly scoped to later milestones:

| File | Cleanup milestone |
|---|---|
| `example/lib/main.dart` | #92 |
| `example/lib/screens/device_screen.dart` | #92 |
| `example/lib/providers/cardio_classifier_provider.dart` | #90 |
| `example/lib/providers/emotions_classifier_provider.dart` | #90 |
| `example/lib/providers/mems_classifier_provider.dart` | #90 |
| `example/lib/providers/nfb_classifier_provider.dart` | #90 |
| `example/lib/providers/physio_classifier_provider.dart` | #90 |
| `example/lib/providers/productivity_classifier_provider.dart` | #90 |

The set exactly matches the plan's eight-file enumeration. No unexpected consumer surfaced — Task 6's verification clause is satisfied. The build break is intentional milestone scoping, not a correctness defect.

### 2. Minor UI text behavior change in `device_screen.dart` Status section

Before this milestone, `deviceConnectionStateProvider` emitted `Stream.value(NeiryConnectionState.disconnected)` immediately when no device was active, so `device_screen.dart`'s status section (`device_screen.dart:349-353`) rendered "Connection state: disconnected". After this milestone, the provider proxies `NeiryService.connectionStateStream`, which emits nothing pre-connect, so the same code path renders "Connection state: …" (the `loading` branch).

The plan acknowledged this and verified that `deviceUiStateProvider` (the only other consumer of `deviceConnectionStateProvider`) maps loading → `idle` via `whenOrNull(data:)`, preserving the prior UI-state mapping. The status-text branch in `device_screen.dart:349-353` is a separate direct consumer that wasn't in the plan's verified-consumers list, but `device_screen.dart` is being rewritten wholesale in milestone #92, so this text regression is short-lived and out of scope to fix here. Worth recording for #92 to ensure the new screen handles the loading state explicitly.

### 3. Dispose-order placement of `_artifactsController.close()` doesn't match field/subscription order — cosmetic only

The plan instructed placing the close call "after `_batteryController.close()`, before the classifier controllers" and the implementation does so (line 297). However, the field declaration (line 53) and the fan-in subscription wiring (lines 163–166) place `artifactsStream` between `psdStream` and `resistanceStream`, grouping it with EEG-derived streams. So:

- Fields/subscriptions: `eeg → psd → artifacts → resistance → battery → …`
- `dispose()` closes: `… → resistance → battery → artifacts → physio → …`

Order does not affect correctness — all broadcast controllers are independent and idempotent on close — but the inconsistency makes future maintenance slightly harder. Implementation matches the plan literally; flagging for awareness only.

### 4. `ResistanceMapNotifier.build()` returns `{}` on every rebuild — preserved pre-existing behavior

`build()` returns an empty map and registers a fresh `ref.onDispose` callback every time it runs (`stream_providers.dart:60`). For the stable `neiryServiceProvider` singleton, `build()` runs once, so callbacks don't accumulate and accumulated resistance state isn't wiped in practice. If the service provider is ever invalidated (e.g., in tests), the accumulated map is reset and a new onDispose callback piles up.

This is **identical** to the pre-existing implementation's pattern (which also returned `{}` and re-registered onDispose on every build), so no regression. Not flagging as a defect to fix in this milestone — noting for future hardening if invalidation semantics ever need to differ.

### 5. Disposal of `NeiryService` is unawaited via `ref.onDispose` — plan-acknowledged, becomes the only path post-#92

`ref.onDispose(s.dispose)` in `neiry_service_provider.dart:7` registers a `Future<void>`-returning callback that Riverpod does not await. The plan acknowledges this and notes milestone #92 will reintroduce an explicit `await ref.read(neiryServiceProvider).dispose()` in `main.dart`'s `_cleanupAndDispose()`. Until that lands, `main.dart` still references the (now deleted) `activeDeviceProvider` and will not compile, so this concern is moot in the broken-build interim. Acceptable per plan. No action needed.

### 6. `service.scan(...).first` ignores `_disposed` state after subscription — pre-existing behavior

`NeiryService.scan` calls `_checkNotDisposed()` synchronously but the returned stream is then consumed via `.first` in `deviceScanProvider`. If `dispose()` is called after the scan starts, the stream is from `_locator.requestDevices(...)` whose lifecycle is owned by `_locator.dispose()` — disposal of the locator may complete the scan stream prematurely or surface an error. This is **inherited** from the legacy `deviceLocatorProvider` implementation; not a regression introduced by this milestone. No change required here.

## Verdict

The diff faithfully implements the plan with no correctness defects introduced. The expected-error set from Task 6 exactly matches the eight imports the plan called out, confirming Task 6's verification gate is satisfied. The four other findings are pre-existing patterns, planned follow-up work, or cosmetic placement notes — none warrant a code change in this milestone.

REVIEW_PASS
