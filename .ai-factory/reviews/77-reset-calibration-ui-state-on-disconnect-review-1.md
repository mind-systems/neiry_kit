# Code Review: Reset calibration UI state on disconnect (round 1)

## Scope
Reviewed the only code change in the diff: `example/lib/providers/calibration_provider.dart` (the other staged files are plan/review artifacts, not code).

## Change summary
`CalibrationNotifier.build()` now registers `ref.listen(deviceConnectionStateProvider, …)` and sets `state = const AsyncValue.data(null)` when the connection state becomes `NeiryConnectionState.disconnected`. Adds `import 'device_state_providers.dart';`.

## Correctness analysis

- **Listener lifecycle is sound.** `ref.listen` inside an `AsyncNotifier.build()` is auto-disposed when the provider rebuilds/disposes — no leaked subscription. `calibrationProvider` is a non-autoDispose `AsyncNotifierProvider`, so it stays alive across disconnects and the listener keeps firing as intended.
- **No race with `build()`.** `ref.listen` (no `fireImmediately`) does not fire on the initial value, so it cannot clobber the `getCalibrationData()` return value during the pending build future. It only reacts to subsequent `disconnected` emissions.
- **Setting `state` from the callback is valid** for an `AsyncNotifier` and correctly drives the UI: `calibration_screen.dart` reads `calibrationProvider.value` (lines 67/338), so `AsyncValue.data(null)` returns the calibration card to idle and blanks the data card — matching the spec's verification.
- **`nfbCalibrationProvider` is untouched**, so the "Use NFB Calibration" toggles keep their portable data, as required.
- **No `ref.invalidate`** is used here, avoiding re-running `getCalibrationData()` against an absent device — correct per spec.
- **Only `disconnected` triggers the reset**; `connecting`/`connected` are ignored. Correct.

## Deviation from spec (informational, not a defect)
The spec specified `next.valueOrNull`; the implementation uses `next.whenOrNull(data: (s) => s)`. These are functionally equivalent for this case: the `StreamProvider` emits each connection state as a fresh `AsyncData` frame, so both expressions yield the emitted value when `disconnected` arrives. `whenOrNull(data:)` is arguably slightly stricter (it ignores any stale value retained on a loading/error frame), which is fine and does not change behavior. No action required.

## Other notes
- The unused `prev` callback parameter could be `(_, next)`, but this is stylistic and not flagged by the analyzer for closure parameters.

No correctness, security, or runtime concerns found.

REVIEW_PASS
