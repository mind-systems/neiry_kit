# Plan Review: Auto-teardown NeiryService on unexpected disconnect

**Plan:** `.ai-factory/plans/83-auto-teardown-neiryservice-on-unexpected-disconnect.md`
**Scope:** `example/lib/services/neiry_service.dart`, `example/lib/screens/device_screen.dart`
**Risk Level:** 🟢 Low

## Verdict

The plan is well-reasoned and faithfully implements the verified spec in `notes/36-auto-teardown-on-unexpected-disconnect.md`. The core mechanism — a dedicated internal subscription on the **device's native** `connectionStateStream`, kept out of `_activeSubscriptions`, plus a `_tearingDown` intent flag — correctly distinguishes a genuine spontaneous drop from the synthesized/echoed `disconnected` that `disconnect()` itself produces. I verified every assumption against the codebase and found no incorrect file paths, no wrong API usage, and no architectural mistakes. There is one consistency gap worth a decision and two minor robustness items.

## Assumptions verified against the code

- **Synthesized event cannot reach the internal listener.** `disconnect()` adds `disconnected` to `_connectionStateController` (the multiplexer, neiry_service.dart:271-273), *not* to the device's native stream. The internal listener subscribes to `_device!.connectionStateStream` (a different stream). The plan's claim that "only genuine device-stream events" reach it is correct. ✅
- **Double-listen on a broadcast stream is safe.** `connectionStateStream` resolves to `_eventStream(...)` → `receiveBroadcastStream(...).map(...)` (device.dart:61-65, 127-134), a broadcast stream. The fan-in already listens once; `Device._startStateTracking()` listens a third time (device.dart:138). Adding `_internalConnSub` is fine. ✅
- **`unawaited` is available.** `dart:async` is imported (neiry_service.dart:1) and exports `unawaited`. ✅
- **`nlog(... name: 'neiry_kit')` is in scope.** Imported at neiry_service.dart:5. ✅
- **Task 3 provider names and line anchor are accurate.** `deviceConnectionStateProvider` and `deviceIsStartedProvider` exist (device_state_providers.dart:8, 21); the `deviceModeProvider` listener is at device_screen.dart:203 as the plan states. ✅
- **No double-teardown crash on the spontaneous path.** On a native `disconnected`, `Device._startStateTracking` already sets `_started=false`/`_connected=false` (device.dart:140-143). So in the auto-triggered `disconnect()`, step 1 (`isStarted`) is skipped and `device.disconnect()`'s `if (_connected)` guard (device.dart:260) is false — no native re-invoke. This matches the prior "crash on disconnect when already stopped" fixes. ✅
- **Trigger is real.** Roadmap + note 36 confirm the SDK emits `disconnected` ~7 s after power-off (verified on SM A705FN, GATT status=8). The plan does not depend on any unverified signal. ✅
- **Riverpod usage is legal.** Mutating `deviceIsStartedProvider` inside a `ref.listen` callback is allowed (the prohibition is only on mutating providers *during build*). ✅

## Context Gates

- **Architecture:** WARN (informational). `.ai-factory/ARCHITECTURE.md` governs the plugin (`lib/`); this change is confined to the `example/` app and introduces no plugin/boundary violation. No native change, consistent with note 36 ("Pure Dart").
- **Rules:** WARN — no `.ai-factory/RULES.md` present (optional). No convention gate applied.
- **Roadmap:** PASS — directly linked to the "Auto-teardown NeiryService on unexpected disconnect" milestone (ROADMAP.md:132) and its spec note 36. Scope (internal subscription + intent flag + reset `deviceIsStartedProvider`) matches the milestone description exactly.

## Findings

### Important (decide before implementing)

**1. Stale scan/selection state is not cleared on the spontaneous path — inconsistent with the manual disconnect path and with note 36's own acceptance test.**

The manual `_disconnect()` handler calls `_clearScan()` (device_screen.dart:156-158, 183-194), whose comment states this is *mandatory* after every disconnect: "the C SDK clears its internal device list on nativeReleaseDevice, so the old scan is stale." The auto-teardown reuses the very same `disconnect()` (release device → recreate locator), so it invalidates the cached device list the same way — but Task 3 only resets `deviceIsStartedProvider`. After a spontaneous drop the UI is left with `_scanParams`/`_selectedSerial` still set and the cached `deviceScanProvider` not invalidated. Because Connect is enabled when `_selectedSerial != null && uiState == idle` (device_screen.dart:344-346), the user can tap Connect against a now-stale serial on a freshly recreated locator that never scanned for it.

This directly bears on note 36's Verify step ("a subsequent Connect works without any stale-session errors"). The connect-guard from milestone 82 plus the recreated locator may prevent a *crash*, but a connect on a fresh locator with no prior scan can still fail with an error rather than reconnect cleanly.

Recommendation: have the Task 3 listener (on `AsyncData(disconnected)`) also clear scan/selection state, mirroring `_disconnect()` — e.g. call `_clearScan()`. If clearing is deliberately deferred, state that explicitly in the plan and in note 36's scope so the inconsistency is a documented choice rather than an oversight. Either resolution is fine; the plan should not leave it ambiguous.

### Minor (robustness)

**2. Reset of `_tearingDown` is not on a guaranteed path.** Task 2 places `_tearingDown = false` "on the normal completion path after the locator block." Each step inside `disconnect()` is individually try/caught, so an escaping throw is unlikely — but if one ever did, the flag would stay `true` and permanently disable future auto-teardown for the service instance. Prefer wrapping the body so the reset runs in a `finally` (set after the `_device == null` early return). Low risk, cheap to make bulletproof.

**3. Concurrent `disconnect()` re-entrancy is still unguarded.** `disconnect()` has no guard against two overlapping invocations. The auto-triggered teardown could overlap a user-initiated `disconnect()`/`stop()` if the button is tapped in the small window before `uiState` flips to idle. This race pre-exists the plan, but the plan slightly widens it by adding an automatic trigger. Optional hardening: early-return from `disconnect()` when a teardown is already in progress (the `_tearingDown` flag could double as that guard, given it is set right after the `_device == null` check). Not required for correctness here, but worth a sentence acknowledging it.

### Nits (no action required)

- Task 3 intentionally does not suppress the first emission (unlike the `deviceModeProvider` listener at device_screen.dart:204). That is fine — re-setting `deviceIsStartedProvider = false` is idempotent, as the plan notes.
- The native spontaneous `disconnected` reaches `deviceConnectionStateProvider` via the fan-in *before* `disconnect()` synthesizes its own, so Task 3 converges the UI even independent of the synthesized event. Redundant, harmless.

## Conclusion

The plan correctly targets the right files, uses the right APIs, makes only assumptions that the codebase and note 36 confirm, and reuses the existing idempotent teardown rather than building a parallel one. It is safe to implement essentially as written. Before implementation, resolve finding #1 (clear stale scan/selection state on the spontaneous path, or explicitly document deferral) and ideally fold in the two minor robustness items.
