# Plan: Auto-teardown NeiryService on unexpected disconnect

## Context
When the headset powers off or the BLE link drops mid-session, `NeiryService` only forwards the SDK's `disconnected` event to consumers but never tears down the dead session, leaking classifiers/native modules and crashing the next connect with `module already exists`. This adds an internal reaction that runs the existing `disconnect()` teardown on a spontaneous drop and converges the UI to idle.

Plan review 1 (`.ai-factory/plan-reviews/83-...-plan-review-1.md`) verified every assumption against the codebase and rated the approach 🟢 Low risk. Its findings are folded in below: clear stale scan/selection state on the spontaneous path (Important #1), reset `_tearingDown` in a `finally` (Minor #2), and reuse `_tearingDown` as a concurrent-re-entrancy guard (Minor #3).

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: React to spontaneous disconnect inside NeiryService

- [x] **Task 1: Add an intent flag and an internal connection-state subscription**
  Files: `example/lib/services/neiry_service.dart`
  - Add a private re-entrancy flag near the other guards (next to `_connecting`), e.g. `bool _tearingDown = false;`. Its purpose: mark that a teardown the service itself initiated is in progress, so the spontaneous-disconnect listener does not re-enter `disconnect()`, and so two overlapping `disconnect()` calls cannot run concurrently.
  - Add a dedicated field to hold the internal subscription, e.g. `StreamSubscription<NeiryConnectionState>? _internalConnSub;` (kept separate from the `_activeSubscriptions` fan-in list so its lifetime is reasoned about explicitly).
  - Implement a private handler `void _onDeviceConnectionState(NeiryConnectionState state)` that:
    - returns immediately unless `state == NeiryConnectionState.disconnected`;
    - returns immediately if `_tearingDown` is `true` (the service already started teardown — this is the synthesized/echoed disconnect, not a new spontaneous one);
    - otherwise logs the spontaneous drop via `nlog(... name: 'neiry_kit')` and schedules teardown with `unawaited(disconnect())` (`unawaited` is available from the already-imported `dart:async`).
  - Do NOT mutate any Riverpod provider here — `NeiryService` has no `ref`; UI-side reset is handled in Task 3.

- [x] **Task 2: Wire the internal subscription in `connect()` and guard `disconnect()`** (depends on Task 1)
  Files: `example/lib/services/neiry_service.dart`
  - In `connect()`, after `_device` is connected and BEFORE/alongside wiring the fan-in subscriptions, subscribe the internal listener to the device stream directly:
    `_internalConnSub = _device!.connectionStateStream.listen(_onDeviceConnectionState);`
    Listening to the broadcast `connectionStateStream` a second time (the fan-in already listens) is fine. Keep this separate from `_activeSubscriptions` so the synthesized controller event in `disconnect()` cannot reach it — only genuine device-stream events do.
  - Make `_tearingDown` double as a concurrent-re-entrancy guard. At the very top of `disconnect()`, restructure the existing `if (_device == null) return;` guard so the flag is checked and set atomically before any teardown work, and reset in a `finally`:
    ```dart
    if (_device == null) return;
    if (_tearingDown) return; // teardown already in flight (auto + manual overlap)
    _tearingDown = true;
    try {
      // ... existing body (synthesized event → steps 1–5 → field reset → locator recreate) ...
    } finally {
      _tearingDown = false;
    }
    ```
    Setting the flag BEFORE the synthesized `_connectionStateController.add(NeiryConnectionState.disconnected)` call ensures neither the synthesized event nor any native `disconnected` arriving during teardown re-triggers `_onDeviceConnectionState`. The early-return on `_tearingDown` also closes the pre-existing race where a user `disconnect()`/`stop()` tap overlaps the auto-triggered teardown in the brief window before `uiState` flips to idle (review Minor #3).
  - Use a `finally` for the reset (as shown) rather than a trailing assignment, so an escaping throw from any step cannot leave the flag stuck `true` and permanently disable future auto-teardown for the service instance (review Minor #2).
  - Cancel and null the internal subscription as part of teardown (alongside step 2 where `_activeSubscriptions` are cancelled): `await _internalConnSub?.cancel(); _internalConnSub = null;` wrapped in the same try/catch+`nlog` style used for the fan-in cancels.
  - Verify the existing `connect()` stale-device path (`if (_device != null) await disconnect();`) still works: that `disconnect()` sets and clears `_tearingDown` itself within its `try/finally`, so the subsequent fresh connect re-subscribes the internal listener cleanly.

### Phase 2: Converge UI state on spontaneous disconnect

- [x] **Task 3: Reset started flag AND clear stale scan/selection on a spontaneous disconnect** (depends on Task 2)
  Files: `example/lib/screens/device_screen.dart`
  - The button handlers already reset `deviceIsStartedProvider` to `false` AND call `_clearScan()` on user connect/stop/disconnect (e.g. `_disconnect()` at device_screen.dart:156-158); the spontaneous path has neither. Add a `ref.listen<AsyncValue<NeiryConnectionState>>(deviceConnectionStateProvider, ...)` inside `build()` (next to the existing `deviceModeProvider` listener around line 203) that, when the new value is `AsyncData` with `NeiryConnectionState.disconnected`:
    - sets `ref.read(deviceIsStartedProvider.notifier).state = false;`
    - calls `_clearScan()`.
  - Why `_clearScan()` is required (review Important #1): the auto-teardown reuses the same `disconnect()` (release device → recreate locator), so it invalidates the cached device list exactly as the manual path does — its comment (device_screen.dart:176-178) states clearing is mandatory after every disconnect because "the C SDK clears its internal device list on nativeReleaseDevice, so the old scan is stale." Without this, `_scanParams`/`_selectedSerial` stay set and Connect (enabled when `_selectedSerial != null && uiState == idle`, device_screen.dart:344-346) can fire against a stale serial on a freshly recreated locator that never scanned for it — failing note 36's Verify step ("a subsequent Connect works without any stale-session errors").
  - `_clearScan()` is `mounted`-guarded and uses `setState` + a post-frame `ref.invalidate` (device_screen.dart:183-194), so it is safe to call from the `ref.listen` callback. It is idempotent: on a manual disconnect both the button handler and this listener may run, but the second `_clearScan()` no-ops because `_scanParams` is already `null`.
  - This listener fires for both the synthesized `disconnected` (user disconnect) and the spontaneous teardown's events, keeping `deviceUiStateProvider` and the started flag consistent (`deviceUiStateProvider` already derives `idle` from connection state, so no extra work there).
  - Keep the change minimal and idempotent — no need to suppress the first emission or diff `prev`/`next`; re-setting `false` / re-clearing an already-cleared scan is harmless.
