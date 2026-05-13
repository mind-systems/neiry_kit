# Code Review: Migrate classifiers_screen, mems_screen, productivity_cardio_screen (round 2)

Plan: `.ai-factory/plans/69-migrate-classifiers-screen-mems-screen-productivity-cardio-screen.md`
Previous review: `.ai-factory/reviews/69-migrate-classifiers-screen-mems-screen-productivity-cardio-screen-review-1.md`

Scope reviewed:
- `example/lib/services/neiry_service.dart` (Task 1)
- `example/lib/providers/classifier_stream_providers.dart` (Task 2)
- `example/lib/providers/nfb_calibration_provider.dart` (Task 3)
- `example/lib/screens/classifiers_screen.dart` (Task 4)
- `example/lib/screens/mems_screen.dart` (Task 5)
- `example/lib/screens/productivity_cardio_screen.dart` (Task 6)

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`)**: ✅ no violations. All edits stay in `example/` and use only the public `neiry_kit` barrel API.
- **Rules**: no `.ai-factory/RULES.md` and no `.ai-factory/skill-context/aif-review/SKILL.md` — no project-specific overrides to apply.
- **Roadmap (`.ai-factory/ROADMAP.md`)**: ✅ this is milestone 69/93; the `calibration_screen.dart` pre-existing analyzer errors are explicitly deferred to milestone 94 per Task 7.

## Risk Level: 🟡 Medium

The round-1 regressions about stale data + always-enabled buttons were addressed by adding an `isConnected` gate sourced from `deviceConnectionStateProvider`. Most of the migration is mechanically correct. However, one critical issue (`isConnected` does not actually flip back to `false` on user-initiated disconnect) and one carried-over latent issue (`AsyncData<void>(null)` equality skipping `ref.listen` callbacks) remain.

---

## Critical Issues

### 1. `isConnected` does not revert to `false` after user-initiated disconnect

**Files:**
- `example/lib/services/neiry_service.dart:246-287` (`disconnect()` order)
- `example/lib/screens/classifiers_screen.dart:41-42, 86-87`
- `example/lib/screens/mems_screen.dart:20-21`
- `example/lib/screens/productivity_cardio_screen.dart:103-104, 251-252`

The new `isConnected` gate in all three screens is sourced from `deviceConnectionStateProvider`, which watches `NeiryService.connectionStateStream` — a multiplexer fed by `_device!.connectionStateStream` only via a fan-in subscription wired in `connect()` (`neiry_service.dart:155-158`).

In `NeiryService.disconnect()` (`neiry_service.dart:247-252`), step 1 cancels every entry in `_activeSubscriptions` — **including the `connectionStateStream` subscription** — before step 3 calls `_device!.disconnect()` (`neiry_service.dart:277`). Even if the native SDK emits a `NeiryConnectionState.disconnected` event during device teardown, the multiplexer subscription is already gone, so `_connectionStateController` never receives it. (`lib/src/api/device.dart:182-193` confirms `Device.disconnect()` itself does not emit on the stream; it only updates an internal cache.)

Consequence: after a user taps "Disconnect", `deviceConnectionStateProvider` keeps the last cached `AsyncData(NeiryConnectionState.connected)` forever (or until the next successful connect overwrites it). Every screen reviewed here continues to render `isConnected == true`, which means:
- Stream `.when(data:, loading:)` keeps showing the **last seen metrics** from the closed session instead of falling back to "Waiting for device..." — exactly the round-1 regression #1 the gate was added to fix.
- All five action buttons (Start/Import Baseline on physio; Start Baseline/Reset Fatigue on productivity) stay visually enabled. Tapping them is a no-op inside the action notifiers (classifiers are already null), so the user sees enabled buttons that do nothing — exactly the round-1 regression #2.

This regression survives the fix because the gate's *source of truth* never updates on user-initiated disconnect.

**Minimal fix:** in `NeiryService.disconnect()`, manually push the disconnected state into the multiplexer before cancelling subscriptions, e.g.

```dart
Future<void> disconnect() async {
  if (_device == null) return;
  // Synthesize a disconnect event so consumers can react before we tear down.
  if (!_connectionStateController.isClosed) {
    _connectionStateController.add(NeiryConnectionState.disconnected);
  }
  for (final s in _activeSubscriptions) { ... }
  ...
}
```

Or alternatively, swap the gate's source from `deviceConnectionStateProvider` to `NeiryService.isConnected` exposed through a small `StateProvider` that's flipped in `connect()`/`disconnect()`.

This needs to land in this milestone — without it, the screens regress in the exact same way that motivated the round-1 fix.

---

### 2. Second cardio calibration in the same session — snackbar never fires (carried over from round 1)

**Files:**
- `example/lib/services/neiry_service.dart:227-230, 405-406`
- `example/lib/providers/classifier_stream_providers.dart:67-69`
- `example/lib/screens/productivity_cardio_screen.dart:255-261`

`_cardioCalibratedController` is a `StreamController<void>.broadcast()` and the fan-in subscription does `(_) => _cardioCalibratedController.add(null)`. Every cardio-calibrated event therefore becomes `AsyncData<void>(null)` in `cardioCalibratedProvider`.

Riverpod 3.x's `defaultUpdateShouldNotify(prev, next)` returns `prev != next`. `AsyncData.==` compares by `(runtimeType, _loading, valueFilled, _errorFilled)` plus value equality; two consecutive `AsyncData<void>(null)` instances are equal, so `updateShouldNotify` returns `false` and the `ref.listen` callback registered at `productivity_cardio_screen.dart:255` is **not** invoked on the second emission.

Repro: connect → wait for first cardio calibration → snackbar shows → disconnect → reconnect → cardio re-calibrates → no snackbar.

Round-1 flagged this; the current implementation still uses `add(null)` so it remains unfixed.

**Fix:** emit a discriminating value. Either:
- `StreamController<DateTime>.broadcast()` + `_cardioCalibratedController.add(DateTime.now())`, and update `cardioCalibratedStream` / `cardioCalibratedProvider` to `Stream<DateTime>` / `StreamProvider<DateTime>`. Update `ref.listen(cardioCalibratedProvider, ...)` signature in `_CardioCard` accordingly.
- Or a monotonic `int` counter incremented each time.

Either makes consecutive emissions non-equal so `ref.listen` always fires.

---

## Should Fix

### 3. Toggle subtitle promises a behavior that no caller delivers

**Files:**
- `example/lib/providers/nfb_calibration_provider.dart:12-21`
- `example/lib/screens/mems_screen.dart:30-39`
- `example/lib/screens/productivity_cardio_screen.dart:65-75`

`useMemsCalibrationToggleProvider` and `useCalibrationToggleProvider` are now plain `StateProvider<bool>` flags. The subtitle in both screens reads "Takes effect on next connect". Per the plan ("read sites are out of scope here"), no call site in `device_screen.dart` or anywhere else reads either provider when invoking `NeiryService.connect(...)`. The toggle persists across navigations but does not influence connect behavior.

End-user impact: the subtitle is currently misleading. Acceptable for a transitional milestone, but make sure milestone 94 (or whichever wires the read side) is explicitly tracked so this isn't forgotten. If milestone 94 only covers `calibration_screen.dart` and not the connect wiring, file a follow-up.

---

## Nice to Have / Minor

### 4. Physio "Waiting for first update" dimming was dropped

**File:** `example/lib/screens/classifiers_screen.dart:114`

The original physio `loading:` branch was `Opacity(opacity: 0.5, child: const Text('Waiting for first update...'))`. The new branch is `const Text('Waiting for device...')`. Per the plan this is intentional collapsing of two messages, but the dimmed styling and the more specific message ("first update" vs "device") are both gone. Cosmetic.

### 5. Productivity card renders two stacked "Waiting…" placeholders side-by-side

**File:** `example/lib/screens/productivity_cardio_screen.dart:117-194`

Indexes and Metrics are now each gated separately by `!isConnected` and each has its own `loading:` text. While disconnected, the user sees `'Waiting for device...'` then a `Divider()` then `'Waiting for device...'` again — two visually duplicated placeholders. Easy follow-up: hoist a single `!isConnected ? Text('Waiting for device...') : Column(children: [indexesWhen, divider, metricsWhen])`. Cosmetic.

---

## What looked correct

- `NeiryService` controller construction, fan-in wiring, and `dispose()` close-order are consistent with the existing pattern. The two new controllers (`_physioCalibratedController`, `_cardioCalibratedController`) sit next to the progress controllers, are subscribed inside the same `_activeSubscriptions.addAll([...])` block (`neiry_service.dart:223-230`), and are closed only in `dispose()` — never in `disconnect()` — matching the documented intent. (`physio.calibrated` does **not** suffer the equality problem of finding #2: `PhysiologicalStatesBaselines` has no `==` override, so identity equality treats each instance as distinct.)
- New `StreamProvider`s in `classifier_stream_providers.dart:62-69` source from the new getters and are correctly placed before `physioBaselinesProvider`.
- `nfb_calibration_provider.dart:12-21` adds the two `StateProvider<bool>` flags without disturbing `nfbCalibrationProvider`; doc comments cleanly describe semantics.
- All `log(..., name: 'Neiry')` calls from milestone 81 are preserved byte-identically across the three screens.
- `physioActionsProvider` / `productivityActionsProvider` `.notifier.method()` invocations use `ref.read(...)`; no accidental `ref.watch` on the notifier handle.
- `await ref.read(physioActionsProvider.notifier).importBaselines(result)` preserves the original SnackBar-after-await pattern.
- Import diffs are clean: each screen removed exactly the deleted providers and added the new ones.
- Toggle `value: useCalibration && nfbData != null` and `onChanged: nfbData == null ? null : ...` semantics correctly reflect that the toggle is only meaningful with calibration data present.

---

## Recommendation

Block on findings #1 and #2 — both produce user-visible regressions on the second connect cycle that the rest of the migration explicitly tried to prevent. #3 is a follow-up worth tracking. #4 and #5 are cosmetic.
