# Plan Review: Reset calibration UI state on disconnect

**Plan:** `77-reset-calibration-ui-state-on-disconnect.md`
**Files Reviewed:** 1 (plan) + 4 codebase files cross-checked
**Risk Level:** 🟢 Low

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`):** present. The change lives entirely in the example app's Dart provider layer (`example/lib/providers/`) and touches no plugin boundary, native bridge, or channel contract. No boundary/dependency violation. — `OK`
- **Rules (`.ai-factory/RULES.md`):** not present. — `WARN` (optional file absent, non-blocking)
- **Roadmap (`.ai-factory/ROADMAP.md`):** present. The plan maps 1:1 to the active milestone at line 116 ("Reset calibration UI state on disconnect"), including the same approach (`ref.listen` → `state = const AsyncValue.data(null)`, no `ref.invalidate`, preserve `nfbCalibrationProvider`). Roadmap linkage confirmed. — `OK`

## Verification Performed

Every concrete assumption in the plan was checked against the codebase:

- ✅ **Target file & method exist** — `CalibrationNotifier.build()` in `example/lib/providers/calibration_provider.dart` is async, registers `ref.onDispose(...)`, then ends with `return NfbCalibrator.getCalibrationData();`. The insertion point described (after `onDispose`, before the `return`) is accurate and there is **no `await` before it**, so the listener is registered synchronously — correct for Riverpod.
- ✅ **`deviceConnectionStateProvider` exists** — defined in `example/lib/providers/device_state_providers.dart` as a `StreamProvider<NeiryConnectionState>`. Same `providers/` directory, so the suggested relative import `import 'device_state_providers.dart';` is correct.
- ✅ **Enum value is correct** — `NeiryConnectionState.disconnected` exists (`lib/src/channel/enums.dart:78`, code `0`). The enum has only `disconnected`/`connected`/`unsupportedConnection`; the plan correctly reacts only to `disconnected`.
- ✅ **`valueOrNull` is valid** — `flutter_riverpod: ^3.2.0`; `AsyncValue.valueOrNull` is part of the Riverpod 3 API. Using it to ignore loading/error frames is correct.
- ✅ **`NeiryConnectionState` already in scope** — `import 'package:neiry_kit/neiry_kit.dart';` is already present in the target file (line 5), so no extra import needed for the enum, as the plan states.
- ✅ **No spurious audio cue regression** — the audio cue listener in `calibration_screen.dart:55` guards with `if (!notifier.isRunning) return;`. A disconnect-driven `state = AsyncValue.data(null)` happens while `isRunning == false`, so it will **not** fire `playDone()`. The plan's reset is safe with respect to the existing cue logic.
- ✅ **No accidental teardown of the provider** — `calibrationProvider` is a plain (non-`autoDispose`) `AsyncNotifierProvider`. Using `ref.listen` (not `ref.watch`) on the connection stream does not cause `calibrationProvider` itself to rebuild on disconnect, so the cached listener survives and the reset is applied to the existing notifier instance. Correct.
- ✅ **Pairs-with claim holds** — the comment references the native locator-session reset; milestone 76 ("Recreate the locator session on disconnect", ROADMAP line 114) is `[x]` done, so `getCalibrationData()` returning stale data is genuinely the on-screen-only concern this plan addresses.

## Critical Issues

None.

## Minor Observations (non-blocking)

1. **Disconnect during an in-flight calibration.** If the device drops while a full/quick run is in the `loading` state, the listener sets `state = AsyncValue.data(null)`, but the still-pending `_fullCompleter`/`AsyncValue.guard` in `startFull`/`startQuick` can later resolve and overwrite the state back to a value (or `_writeToSharedProvider` may run). In practice a disconnect mid-run aborts the SDK stream with an error, so this is an edge case rather than a regression, and the end state after the error path is still acceptable. No action required, but worth being aware of during verification — the plan's verification steps only cover the disconnect-after-completion path, not disconnect-during-run.

2. **Listener only active once the provider has been created.** The reset depends on `calibrationProvider` having been read at least once (i.e. the user opened the Calibration screen). This is fine: if the screen was never opened, there is no cached "calibrated" result to reset, so the bug cannot manifest. No change needed.

## Positive Notes

- The plan correctly chooses `state = const AsyncValue.data(null)` over `ref.invalidate(...)`, and explains *why* (invalidate would re-run `getCalibrationData()` against an absent device and risk an error frame). This is the right call.
- Explicit, repeated guardrails to **not** touch `nfbCalibrationProvider` correctly protect the "Use NFB Calibration" toggle feature.
- Scope is minimal and surgical — a single registration in one method, with an exact insertion point, exact imports, and a clear verification procedure including `flutter analyze`.
- File paths, enum values, API surface, and provider names all match the actual codebase.

PLAN_REVIEW_PASS
