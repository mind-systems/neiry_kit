# Code Review: Migrate classifiers_screen, mems_screen, productivity_cardio_screen

Plan: `.ai-factory/plans/69-migrate-classifiers-screen-mems-screen-productivity-cardio-screen.md`

Scope reviewed:
- `example/lib/services/neiry_service.dart` (Task 1)
- `example/lib/providers/classifier_stream_providers.dart` (Task 2)
- `example/lib/providers/nfb_calibration_provider.dart` (Task 3)
- `example/lib/screens/classifiers_screen.dart` (Task 4)
- `example/lib/screens/mems_screen.dart` (Task 5)
- `example/lib/screens/productivity_cardio_screen.dart` (Task 6)

Verification: `flutter analyze` flags three pre-existing errors in `lib/screens/calibration_screen.dart` (`nfbClassifierProvider`, `nfbStateProvider`, missing import). These are explicitly out of scope per Task 7 — they belong to milestone 94. The six files touched by this milestone compile cleanly.

---

## Findings

### 1. Disconnect leaves stale classifier metrics frozen on screen (functional regression)

**Severity:** medium

**Files:**
- `example/lib/screens/classifiers_screen.dart:52-65` (Emotions card `.when`)
- `example/lib/screens/classifiers_screen.dart:103-130` (Physio card `.when`)
- `example/lib/screens/productivity_cardio_screen.dart:113-135` (Productivity indexes `.when`)
- `example/lib/screens/productivity_cardio_screen.dart:138-185` (Productivity metrics `.when`)
- `example/lib/screens/productivity_cardio_screen.dart:259-281` (Cardio state `.when`)
- `example/lib/screens/mems_screen.dart:47-99` (MEMS data `.when`)

The old code keyed "device present?" off `ref.watch(*ClassifierProvider) == null`. When the device disconnected, that provider became `null` and the screen reverted to `Text('Waiting for device...')`.

The new code keys "device present?" off the `loading` branch of the underlying `StreamProvider`. But `NeiryService` keeps every multiplexer `StreamController` **open across disconnect cycles** (intentional, per `neiry_service.dart:241` "Multiplexer controllers stay open so the next [connect] call can re-feed them" and confirmed by the fact that close-on-controllers only happens in `dispose()`, not `disconnect()`).

Consequence: once any classifier stream has emitted at least one event during the lifetime of the `NeiryService` instance, the `StreamProvider` holds `AsyncData(lastValue)` **forever** until app exit. When the user disconnects, every screen that uses these `.when(loading:, data:)` patterns will keep rendering the **last seen metrics from the disconnected session** — frozen heart rate, frozen attention, frozen "Last updated: 14:32:01" timestamp — with no visual indication the device is gone.

Reproduction: connect → wait for data → disconnect → observe the classifier cards still show the stale metrics from the previous session instead of "Waiting for device...".

Note: the milestone description's suggestion `ref.watch(emotionsStateProvider).valueOrNull != null` has the same flaw; the alternative it offered — "or a dedicated `isEmotionsActiveProvider`" — would have avoided this by sourcing from `deviceConnectionStateProvider`. The implementation chose the simpler path consistent with the description's primary option, but the regression is real and user-visible.

A minimal fix: gate the body on `ref.watch(deviceConnectionStateProvider).valueOrNull == NeiryConnectionState.connected`, falling back to "Waiting for device..." when not connected — independent of stream caching.

### 2. Action buttons remain clickable when no device is connected (UX regression)

**Severity:** low

**Files:**
- `example/lib/screens/classifiers_screen.dart:144-194` (Start Baseline / Import Baselines / Export Baselines)
- `example/lib/screens/productivity_cardio_screen.dart:199-223` (Start Baseline / Reset Fatigue)

The Phase 3 restructure moved the four physio buttons and two productivity buttons out of the `else ...[ ... ]` arm of the deleted `if (classifier == null)`. They are now unconditional siblings of the `.when(...)` widget.

When no device is connected, the buttons render as fully enabled (`ElevatedButton`/`OutlinedButton`). Tapping them logs the action (visible in logcat) and then no-ops inside the action notifier (`physioActionsProvider.notifier.startBaselineCalibration()` calls `service.physioClassifier?.startBaselineCalibration()` — null-safe). The user sees a fully active button that does nothing.

Export Baselines (`classifiers_screen.dart:181`) already has the correct guard via `baselines == null ? null : ...` — but Start/Import don't.

Suggested gate: derive disabled state from `ref.watch(deviceConnectionStateProvider).valueOrNull != NeiryConnectionState.connected` and pass `null` for `onPressed` accordingly. Same fix could double for finding #1.

### 3. Second cardio calibration in the same app session won't show snackbar

**Severity:** low (latent, easy to hit on a disconnect→reconnect cycle)

**Files:**
- `example/lib/providers/classifier_stream_providers.dart:68-69` (`cardioCalibratedProvider`)
- `example/lib/screens/productivity_cardio_screen.dart:239-245` (`ref.listen(cardioCalibratedProvider, ...)`)

`cardioCalibratedProvider` is `StreamProvider<void>`. The fan-in in `NeiryService` (`neiry_service.dart:227-230`) does `(_) => _cardioCalibratedController.add(null)` — so every cardio-calibrated event becomes `AsyncData<void>(null)`.

Riverpod 3.2.1 (the resolved version in `pub-cache`) uses `defaultUpdateShouldNotify(prev, next) => prev != next` (`riverpod-3.2.1/lib/src/core/element.dart:360`). `AsyncValue.==` (`async_value.dart:648`) compares `runtimeType`, `_loading`, `valueFilled`, and `_errorFilled`. Two consecutive `AsyncData<void>(null)` values compare equal → listeners are **not** notified.

Consequence: first cardio calibration after fresh service construction fires the snackbar. After disconnect→reconnect within the same app session, the second cardio calibration completion emits another `AsyncData<void>(null)`, which equals the cached state, so the `ref.listen` callback never fires. The user gets no feedback that cardio re-calibrated.

Suggested fix: emit a discriminating value instead of `null`. Either `Stream<DateTime>` with `DateTime.now()`, or a monotonic counter, so consecutive emissions differ and `prev != next` holds.

This does not affect physio: `PhysiologicalStatesBaselines` (`lib/src/models/physio_baselines.dart`) does not override `==`, so it falls back to identity equality — two emissions are always non-equal.

### 4. `cardioCalibratedProvider` misses calibration events on first navigate-in

**Severity:** low (pre-existing pattern, but newly exposed)

**Files:**
- `example/lib/providers/classifier_stream_providers.dart:68-69`
- `example/lib/services/neiry_service.dart:227-230`

Cardio internal calibration runs automatically after `connect()` — there is no UI button that triggers it. The first emission to `_cardioCalibratedController` happens on the SDK's schedule.

`cardioCalibratedProvider` is non-auto-dispose but lazy: it does not subscribe to `cardioCalibratedStream` until its first watcher reads it. If the user is on the Device screen when the post-connect cardio calibration completes, the broadcast controller emits to **zero** subscribers (the StreamProvider hasn't been built yet). When the user later navigates to Productivity & Cardio, the StreamProvider initializes in `AsyncLoading`, then subscribes to a broadcast stream that has already emitted and dropped the event. The snackbar never shows for that session's first cardio calibration.

Same workaround as #3 (a discriminating value won't fix this; the underlying issue is broadcast semantics). A robust fix would either eagerly initialize the provider at app startup (e.g., read it from `main.dart` once the container is alive) or replay-cache the last event in `NeiryService` (e.g., a `BehaviorSubject` from rxdart).

### 5. Toggle providers exist but no caller reads them at connect time

**Severity:** documentation / informational

**Files:**
- `example/lib/providers/nfb_calibration_provider.dart:13-21`
- `example/lib/screens/mems_screen.dart:17-44`
- `example/lib/screens/productivity_cardio_screen.dart:54-82`

`useMemsCalibrationToggleProvider` and `useCalibrationToggleProvider` are now plain `StateProvider<bool>` flags with subtitles that promise "Takes effect on next connect". The plan explicitly notes the read site is out of scope ("read sites are out of scope here; this milestone only re-creates the providers and updates UI semantics"), and inspection confirms no call site reads either provider in `device_screen.dart` or anywhere else — `NeiryService.connect()` still receives `nfbData` from whatever the caller passes, which today does not consult these toggles.

End-user impact: the toggle visibly switches and persists across navigations, but flipping it to `true` and reconnecting does **not** actually pass `nfbData` to `NeiryService.connect()`. The subtitle is currently a lie until a follow-up milestone wires the read side. Flag in the milestone closeout / follow-up so it doesn't get lost.

### 6. Minor: physio "first update" placeholder lost its dimmed styling

**Severity:** cosmetic

**Files:**
- `example/lib/screens/classifiers_screen.dart:103-104`

Original physio `loading:` branch was `Opacity(opacity: 0.5, child: const Text('Waiting for first update...'))`. The new branch is `const Text('Waiting for device...')` — the dimming and the more specific message are both gone. Per the plan this is intentional (the loading branch is now overloaded for both "no device" and "device connected but no data yet"), but it's a visible UX flattening worth noting.

### 7. Minor: productivity card renders two stacked loading placeholders when disconnected

**Severity:** cosmetic

**Files:**
- `example/lib/screens/productivity_cardio_screen.dart:113-135` and `138-185`

When no device is connected (or before the productivity classifier has emitted), the card shows `Text('Waiting for indexes data...')` immediately followed by `const Divider()` and then `Text('Waiting for metrics data...')`. Visually this reads as two separate loading sections rather than one cohesive "Waiting for device..." state. Per spec, but flagged so the next pass can clean it up if desired.

---

## What looked correct

- `NeiryService` controller construction, fan-in subscription wiring, and `dispose()` close-order are all consistent with the existing pattern. The two new controllers (`_physioCalibratedController`, `_cardioCalibratedController`) are added next to the existing progress controllers, fan-in listeners are appended in the same `_activeSubscriptions.addAll([...])` block (`neiry_service.dart:223-230`), and they are closed in `dispose()` only — never in `disconnect()` — matching the documented intent.
- The two new `StreamProvider`s in `classifier_stream_providers.dart:62-69` correctly source from the new `NeiryService` getters and are placed before `physioBaselinesProvider` as specified.
- `nfb_calibration_provider.dart:12-21` adds the two new `StateProvider<bool>` flags without disturbing `nfbCalibrationProvider`.
- All `log(..., name: 'Neiry')` calls from milestone 81 are preserved byte-identically in the migrated screens (`classifiers_screen.dart:148, 161, 184`; `mems_screen.dart:40`; `productivity_cardio_screen.dart:78, 203, 216`).
- All `physioActionsProvider` / `productivityActionsProvider` notifier call sites use `ref.read(...).notifier.method()` correctly — no accidental `ref.watch` on a `NotifierProvider<…, void>`.
- The `await ref.read(physioActionsProvider.notifier).importBaselines(result)` keeps the existing pattern where the SnackBar fires only after the await completes (`classifiers_screen.dart:166-172`).
- Removing `device_state_providers.dart` from the two screens that previously imported it (mems, productivity+cardio) is consistent — `deviceUiStateProvider` / `canEditToggle` are gone with the toggle's gating logic.

---

## Recommendation

Findings #1 and #2 are user-visible regressions and worth fixing before closing this milestone (they share a fix). Findings #3, #4, and #5 are latent or out-of-scope — flag for the next milestone (#94, calibration_screen + final compile pass) or a small follow-up. Findings #6 and #7 are cosmetic.