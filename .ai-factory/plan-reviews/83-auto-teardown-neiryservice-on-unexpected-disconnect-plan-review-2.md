# Plan Review 2 — Auto-teardown NeiryService on unexpected disconnect

## Code Review Summary

**Plan:** `.ai-factory/plans/83-auto-teardown-neiryservice-on-unexpected-disconnect.md`
**Files Reviewed:** 4 (plan + `neiry_service.dart`, `device_screen.dart`, `device_state_providers.dart`, `lib/src/api/device.dart`)
**Risk Level:** 🟢 Low

This is a second-pass review; plan review 1 already folded its findings into the plan (clear stale scan on the spontaneous path, `finally`-reset of `_tearingDown`, re-entrancy guard). I re-verified every assumption against the current codebase and the spec note (`notes/36-...`). The plan is accurate, minimal, and correctly scoped.

### Context Gates

- **Architecture** (`ARCHITECTURE.md` present): WARN-free. The change stays inside the example app's service/UI layers (`example/lib/services/`, `example/lib/screens/`) and adds no cross-boundary dependency. `NeiryService` remains Riverpod-free (no `ref`), consistent with its milestone-88 contract; UI reset is correctly pushed to `device_screen.dart`. No native/plugin change — matches note 36 ("Pure Dart; no native change needed").
- **Rules** (`.ai-factory/RULES.md`): not present → WARN (optional file absent). No explicit rule violations detectable.
- **Roadmap** (`ROADMAP.md`): aligned. The plan maps 1:1 to the open item at `ROADMAP.md:132` ("Auto-teardown NeiryService on unexpected disconnect") under the "Unexpected disconnect handling" group, and correctly pairs with the completed note-35 connect-guard (`ROADMAP.md:130`). Linkage is explicit and correct.

### Verified Assumptions (all hold)

- **Trigger exists.** `Device._startStateTracking()` (`lib/src/api/device.dart:138-144`) listens to the native `connectionStatus` EventChannel and sets `_connected = false` on `disconnected` — confirming the SDK does emit `NeiryConnectionState.disconnected` on a spontaneous drop, which the new internal subscription will receive. Matches note 36's on-device verification (~7 s latency, SM A705FN).
- **Broadcast stream, multiple listeners OK.** `connectionStateStream` (`device.dart:275`) returns the `late final _connectionStateStream` built from `EventChannel.receiveBroadcastStream(...).map(...)` — a broadcast stream cached once per `Device`. A second `.listen()` (the internal one) alongside the fan-in is safe; `receiveBroadcastStream` is invoked at most once. Plan's claim is correct.
- **Synthesized event cannot re-trigger the internal listener.** The internal listener subscribes to `_device!.connectionStateStream` (the device EventChannel), while `disconnect()`'s synthesized event is added to `_connectionStateController` (`neiry_service.dart:271-273`) — a different stream. Keeping `_internalConnSub` out of `_activeSubscriptions` is the right call. The `_tearingDown` flag is a redundant-but-correct second guard.
- **Re-entrancy ordering is sound.** Calling an `async` `disconnect()` runs its body synchronously up to the first `await`; placing `if (_tearingDown) return; _tearingDown = true;` at the top means the flag is set before any suspension, so a second `_onDeviceConnectionState` (or a user tap) is correctly short-circuited. `_device` is nulled only at the end (`neiry_service.dart:354`), so the `_device == null` early-return and the `_tearingDown` guard cover the full teardown window.
- **`finally` reset is correct.** Resetting `_tearingDown` in `finally` (not a trailing assignment) prevents a stuck flag if any step throws — important because a permanently-`true` flag would silently disable all future auto-teardown for the instance.
- **Stale-device path stays intact.** `connect()`'s `if (_device != null) await disconnect();` (`neiry_service.dart:127-130`) runs before `_internalConnSub` is recreated; that `disconnect()` sets/clears `_tearingDown` itself and cancels/nulls the internal sub, so the fresh connect re-subscribes cleanly.
- **UI-reset references are exact.** `_disconnect()` resets started + `_clearScan()` (`device_screen.dart:157-158`); `_clearScan()` is `mounted`-guarded with setState-before-post-frame-invalidate and is idempotent (`183-194`); the existing `deviceModeProvider` `ref.listen` sits at line 203; the Connect button enables on `_selectedSerial != null && uiState == idle` (`344-346`). All line numbers in the plan are accurate. `deviceUiStateProvider` already derives `idle` from connection state (`device_state_providers.dart:42-46`), so no extra UI work is needed beyond the started flag + scan clear.
- **`_clearScan()` is genuinely required on the spontaneous path.** Auto-teardown reuses the same `disconnect()` that recreates the locator (`neiry_service.dart:364-371`), invalidating the cached device list exactly as the manual path does — so leaving `_scanParams`/`_selectedSerial` set would let Connect fire against a stale serial on a freshly recreated locator. Plan's Important #1 reasoning is correct and matches the existing comment at `device_screen.dart:176-178`.
- **Imports already available.** `dart:async` (for `unawaited`/`StreamSubscription`) and `nlog` are already imported in `neiry_service.dart` (lines 1, 5).

### Critical Issues

None.

### Minor Observations (non-blocking)

1. **`unawaited(disconnect())` swallows escaping errors as unhandled zone errors.** The new guard wraps the `disconnect()` body in `try { ... } finally { ... }` with **no `catch`** (deliberate, per review Minor #2, so an escaping throw still resets the flag and propagates). On the *manual* path the caller `await`s and handles it; on the *spontaneous* path the call is fire-and-forget via `unawaited`, so any escaping exception becomes an unhandled async error. In practice every step inside `disconnect()` (synthesized add, steps 1–5, `_locator.dispose()`) is individually wrapped in try/catch + `nlog`, so nothing realistically escapes — but to be defensive, consider having `_onDeviceConnectionState` attach a `.catchError((e) => nlog(...))` to the scheduled future (or wrap in its own try/catch). Cheap insurance; does not block.

2. **Other screens still hold stale classifier/calibration state on a spontaneous drop.** This plan converges only `device_screen.dart`. Calibration UI is already handled separately (milestone at `ROADMAP.md:116`, `CalibrationNotifier` listens to `deviceConnectionStateProvider` and resets on `disconnected`), so that screen converges for free via the same forwarded event. No other screen appears to need explicit handling, but worth confirming during QA that the classifier tabs read `null` cleanly after auto-teardown. Out of scope for this plan; noted only for the verify step.

3. **Cancel placement for `_internalConnSub`.** The plan says cancel/null it "alongside step 2." Ensure the cancel sits *inside* the new `try` block (part of teardown) and that only `_tearingDown = false` lives in `finally`. The plan text implies this correctly; calling it out so the implementer does not accidentally hoist the cancel into `finally`.

### Positive Notes

- Reusing the single existing `disconnect()` (rather than a parallel teardown) honors note 36's explicit guard ("the spontaneous path must go through `disconnect()`, not a parallel teardown") and avoids the double-locator-dispose pitfall.
- Keeping `NeiryService` Riverpod-free and delegating UI reset to `device_screen.dart` respects the established layering — no `ref` smuggled into the service.
- Folding `_tearingDown` into a dual-purpose re-entrancy guard also closes the pre-existing race where a user Stop/Disconnect tap overlaps an auto-teardown — a genuine correctness win beyond the stated feature.
- Idempotency reasoning (double `_clearScan`, re-setting `false`) is explicitly thought through, so the listener firing for both synthesized and spontaneous events is harmless.

PLAN_REVIEW_PASS
