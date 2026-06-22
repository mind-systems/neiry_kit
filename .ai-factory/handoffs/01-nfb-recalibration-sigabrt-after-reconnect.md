# Handoff — NFB re-calibration SIGABRT after reconnect (neiry_kit)

## 1. Frame
We are in `neiry_kit` (Flutter plugin wrapping the vendored Capsule/Neiry C SDK) debugging why a **repeat NFB calibration after a disconnect→reconnect cycle** fails. Four planned fixes (roadmap section "NFB re-calibration after reconnect", notes 29–32) are **implemented and committed**. After those fixes, the user re-tested **recalibration after reconnect on real hardware (SM A705FN)** and hit a **hard native crash**: a recursive `SIGABRT` loop entirely inside `libCapsuleClient.so` (the vendored SDK), with **zero app frames** in the backtrace. So the fixes did not fully solve it — the failure mode escalated from a catchable error (`code 255 "Calibration has already been started"`) to an **uncatchable process abort**. The chat is compacted (a huge crash log overflowed it); all durable knowledge is in the files referenced here — rehydrate from them, don't trust memory.

## 2. Read-first map

### Must-read now (minimal rehydration set)
- `.ai-factory/notes/29-recreate-locator-session-on-disconnect.md` — the core fix + the SDK facts (no reset API; device cached per-serial in locator; `clCDevice_Release` doesn't evict). Its **Open Question** ("state may live above the locator at the `clCCapsule` library level") is now the prime suspect — see §3.
- `.ai-factory/notes/30-…`, `31-…`, `32-…` — the other three implemented tasks (UI reset, subscription-cancel, single toggle). Read 32 for the toggle semantics.
- `.ai-factory/ROADMAP.md` → section **"NFB re-calibration after reconnect"** — the four contract lines, all now committed.
- `official/iOS/CapsuleClient.framework/Headers/CNFBCalibrator.h` — proves the SDK's whole NFB-calibrator C surface (no Stop/Reset/Abort).

### Read on demand
- `example/lib/services/neiry_service.dart` — `connect()`, `disconnect()` (now recreates the locator), `_locator` (now mutable). The lifecycle owner.
- `example/lib/providers/calibration_provider.dart` — `CalibrationNotifier` (full/quick/abort/import; `_sub`; UI-reset listener).
- `android/src/main/cpp/jni_nfb_calibrator.cpp` — `nativeStartCalibration` (calls `clCNFBCalibrator_CreateOrGet` + `CalibrateIndividualNFB`/`…Quick`), `nativeStopCalibration` (only detaches callbacks — no SDK reset exists), the stage/`on_calibrated` callbacks, file-static `g_calibrator`.
- `android/src/main/cpp/jni_device.cpp` / `jni_device_locator.cpp` — `nativeReleaseDevice`→`clCDevice_Release`; `nativeCreateDevice`→`clCDeviceLocator_CreateDevice`; `nativeDestroyLocator`→`clCDeviceLocator_Destroy`.
- `mind_mobile/.ai-factory/handoffs/06-bci-device-session-reset-on-reconnect.md` — the parallel handoff already delivered to the mobile team (same root cause; their `NeiryBciProvider._locator` has the same latent bug).
- Captured reproduction logs (untracked, in repo root): `logs00.tt`, `logs01.txt`, `logs02.txt`.

## 3. Current state

**Done (committed):**
- `c094ce4` Recreate the locator session on disconnect (task 29) — `NeiryService.disconnect()` now `await _locator.dispose()` + `_locator = DeviceLocator()` (guarded by `!_disposed`).
- `5e3c57e` Reset calibration UI state on disconnect (task 30) — `CalibrationNotifier.build()` listens to `deviceConnectionStateProvider`, sets `state = AsyncValue.data(null)` on `disconnected`; does NOT clear `nfbCalibrationProvider`.
- `baa6756` Cancel calibration stream subscription on completion (task 31) — `startFull()` cancels/nulls `_sub` in the `CalibrationCompleted` branch and `onError`.
- `8390554` Wire Use-NFB-Calibration toggle into connect (task 32) — single `useCalibrationToggleProvider` on the calibration screen; `connect(useCalibration:)` flag gates MEMS/Productivity/Cardio; MEMS- and Productivity-screen switches removed.
- Working tree is **clean**.

**Root cause established (with evidence):**
- The Capsule SDK has **no stop/reset/abort** for `clCNFBCalibrator` (verified across C, C++, and the official C#/Python wrappers). Only `CreateOrGet`, `CalibrateIndividualNFB(stage)`, `…Quick`, `Import`, `Get`, `IsCalibrated`, `HasCalibrationFailed`, two `SetOn*Event`.
- A **full** 4-stage calibration leaves the calibrator in an internal "started" state that is **not observable** (`IsCalibrated`/`HasCalibrationFailed` are identical before a working and a failing start) and is **never cleared**; a **quick** calibration clears it. Hence `quick→full` works, `full→full` fails.
- The SDK **caches `clCDevice` per serial inside the `clCDeviceLocator`**; `clCDevice_Release` does NOT evict it. Reconnecting via the same (process-wide singleton) `DeviceLocator` returns the **identical `clCDevice` pointer** and the identical session-scoped calibrator. Logs02 proof: `dev=0x776e1a4160` and `cal=0x776e974880` identical before release and after recreate; `sameInstanceAsPrev=1 IsCalibrated=1`; second full start → `E/Client … Calibration has already been started` / `code=255`.
- Timeline across runs: `quick ✓ → full ✓ → full ✗(255)`; reconnect did not help because the locator (the SDK "session") survived.

**NEW critical finding (after the fixes, this is the open problem):**
- Re-calibrate-after-reconnect now produces a **recursive `SIGABRT` inside `libCapsuleClient.so`** (`abort → __kernel_rt_sigreturn → abort → …`, hundreds of frames, no app frames). The SDK aborts itself and its abort handler re-aborts. **Uncatchable from Dart/JNI.**
- Implication: the "already started" condition can **escalate to a native abort**, and **fix 29 (locator dispose+recreate) did NOT prevent it**. That strongly suggests the stale calibrator state lives **above the locator** — at the `clCCapsule` library/global level — so destroying+recreating the locator is **not a sufficient reset**. (This is exactly note 29's Open Question, now likely confirmed.) Alternatively the locator recreate isn't actually producing a fresh native `clCDevice` — unverified, because the diagnostic pointer logging was reverted.

**Uncommitted working-tree state:** none.

## 4. Next step
Diagnose why recalibration-after-reconnect still crashes despite fix 29. Concretely:
1. **Re-add temporary native lifecycle logging** (it was reverted; see §6 for exactly what it was) — log the `clCDevice` pointer at `nativeCreateDevice`/`nativeReleaseDevice`, and at `nativeStartCalibration` log `cal` pointer + `sameInstanceAsPrev` + `IsCalibrated` + `HasCalibrationFailed` + the SDK error `code`/`message`. Tag `"Neiry"`, `log` lib already linked in `android/src/main/cpp/CMakeLists.txt`.
2. Reproduce **full-calibrate → Disconnect → Connect → Start → full-calibrate** and read the new logs. Decide between two hypotheses: **(a)** reconnect still returns the **same** `clCDevice` pointer (locator dispose didn't actually evict the SDK-side device → the SDK caches above the locator, at `clCCapsule`) vs **(b)** a **new** pointer but `IsCalibrated`/internal-started still set (state is library-global). Either way the conclusion is: **locator teardown is insufficient; the reset must go higher, or in-process re-calibration is simply unsupported by this SDK and the UX must prevent it** (e.g. disable re-calibrate without an app restart, or require quick-cal as a reset).
3. Confirm whether a **quick** calibration can run after the stuck full state (zero-code test in the app: after a failed full re-calibrate, press Start Quick). If quick still works, it can be used as an in-process reset before a full re-calibrate.
4. Whatever the fix, **verify it does not SIGABRT** — that is the new acceptance bar, stronger than "no code 255".

## 5. Working discipline
- **Never commit without explicit permission** (global rule). The four task commits were made with permission; do not auto-commit further.
- Commit messages: short noun-phrase/imperative, sentence case, no type prefixes, no body for single-concern. End with the `Co-Authored-By: Claude Opus 4.8 (1M context)` trailer only if the user asks to commit.
- All files in English regardless of chat language.
- Planning workflow: `/aif-plan` writes a plan file and STOPS; implementation happens in a separate `/aif-implement` session. (That is how tasks 29–32 were implemented.)
- `mind_api/proto/` is the single source of truth for protos — not relevant here, but don't create `.proto` elsewhere.
- The user works in Russian; reply in Russian, keep files English.

## 6. Error log (paths we already ruled out — do not repeat)
- **Assumed `stopCalibration` (or any "stop") resets the SDK.** False — `nativeStopCalibration` only detaches callbacks + resets our `g_currentStage`/`g_isQuickMode`; there is no SDK reset call and none exists in the API.
- **Assumed disconnect→reconnect yields a fresh session.** False — proven by the identical `clCDevice` pointer across release/recreate (logs02).
- **Assumed `IsCalibrated`/`HasCalibrationFailed` distinguish the stuck state.** False — both are identical (`1`/`0`) for a working and a failing start; the "started" flag is hidden.
- **Saw a phantom "Calibration complete — data received" with the PREVIOUS run's data right after a failed re-calibrate.** Root cause: `startFull()` never cancelled `_sub` on completion (only in `ref.onDispose`), so a stale terminal event replayed on the next run. Fixed by task 31. (Watch for analogous leaks elsewhere.)
- **Assumed fix 29 (locator recreate) would solve it.** It did NOT prevent the SIGABRT — so do not assume locator-level teardown is the reset; investigate `clCCapsule`-level / library-global state, or treat in-process re-calibration as unsupported.
- The diagnostic native logging used during investigation was intentionally **reverted** before the tasks were planned (the user wanted a clean baseline). It must be **re-added temporarily** to continue — it is not in the committed code.

## 7. Orientation (traps / confusables)
- **Three distinct "calibrations" — do not conflate:**
  1. **Individual NFB calibration** (`NfbCalibrator`, the Calibration screen): finds the user's alpha peak → `IndividualNfbData`. This is the one that gets stuck/crashes on reconnect.
  2. **Baseline calibration** (`PhysioClassifier.startBaselineCalibration()`, `ProductivityClassifier.startBaselineCalibration()`, the "Start Baseline Calibration" buttons): per-classifier personal baselines; runtime command; emits a portable `Uint8List` blob via `calibrated`, re-importable via `importBaselines`. Independent of the reconnect bug.
  3. **`resetAccumulatedFatigue`** on Productivity — unrelated.
- **"Release the device ≠ reset the session."** The locator caches the device; only destroying the locator *might* reset — and per the new crash, maybe not even that.
- **`Device.dispose()` double-disconnect** was a *separate* earlier crash (commit `7bcde88`, note 24): `dispose()` now guards `invokeMethod(disconnect)` with `if (_connected)`. Don't confuse that Fatal-signal-64 GATT crash with this recursive-abort calibrator crash.
- **Two handoffs exist:** this one (kit-side, continue the fix) and `mind_mobile/.ai-factory/handoffs/06-…` (mobile team, NFB intentionally omitted there). Keep them distinct.

## 8. Domain model spine (settled — don't re-litigate)
- **The `clCDeviceLocator` is the SDK session boundary; device lifetime ⊂ locator lifetime.** Pointer: `lib/src/api/device_locator.dart` (singleton + `dispose()`), evidence in logs02. (Caveat: the new SIGABRT suggests some calibrator state may live *above* the locator — that is the one piece still under investigation.)
- **The NFB calibrator has no reset and is session-scoped via `CreateOrGet(device)`.** Pointer: `CNFBCalibrator.h`. The official examples calibrate **once per session** and never re-run — re-calibration may simply be outside the SDK's supported envelope.
- **`nfbCalibrationProvider` holds portable `IndividualNfbData`** (exportable/importable, session-independent, in-memory only). It must survive disconnect (task 30 preserves it) because the single "Use NFB Calibration" toggle (task 32) consumes it at the next connect. Cross-session persistence today = manual Export/Import to file on the Calibration screen.
- **Toggle semantics (task 32):** one `useCalibrationToggleProvider` on the Calibration screen; gates calibration for MEMS+Productivity+Cardio at construct time; NFB classifier always receives `nfbData` if present; "takes effect on next connect" because calibration is a construction-time parameter (no SDK reconfigure). A fresh calibration/import overwrites `nfbCalibrationProvider`; the new profile applies to classifiers only on the next connect, not to live ones.

## 9. Hard rules
- No auto-commit; confirm first. English files. Don't modify anything under `official/` (vendored binaries/headers). `log` + `android` libs are already linked in the cpp `CMakeLists.txt`.

## 10. Cross-cutting invariants checklist
- On **disconnect** (`NeiryService.disconnect`): stop stream → cancel fan-in subs → dispose classifiers → `device.disconnect()` → `device.dispose()` → **`locator.dispose()` + recreate** (added by task 29) → calibration UI reset via the provider listener (task 30), **without** clearing `nfbCalibrationProvider`.
- On **connect**: build classifiers off the (now fresh) locator; pass `nfbData` + `useCalibration`.
- `DeviceLocator` is a process-wide singleton; `dispose()` resets `_instance`; never double-dispose (throws `StateError` — the `!_disposed` guard in `NeiryService` handles the full-teardown path).
- **New acceptance invariant to add to whatever fix lands:** recalibration after reconnect must **not** SIGABRT; and the reconnect must yield a device whose calibrator reads `IsCalibrated == false`.

## 11. Per-unit map with watch-points
- **task 29 / `NeiryService.disconnect`** — became: dispose+recreate locator at end, guarded by `!_disposed`. Watch-point: this is the fix that **did not stop the SIGABRT**; verify (with native pointer logs) whether the recreated locator actually yields a new `clCDevice`. If not, the SDK caches above the locator.
- **task 30 / `CalibrationNotifier.build`** — became: `ref.listen(deviceConnectionStateProvider)` → reset `calibrationProvider` only. Watch-point: must NOT clear `nfbCalibrationProvider` (would break task 32); confirm the toggle stays enabled across disconnect.
- **task 31 / `CalibrationNotifier.startFull`** — became: cancel+null `_sub` on terminal events. Watch-point: ensure completer resolves before cancel; no phantom completion on the next run.
- **task 32 / connect wiring + Calibration screen** — became: single toggle on Calibration screen, `connect(useCalibration:)` gates MEMS/Productivity/Cardio. Watch-point: MEMS/Productivity screens must no longer import/read the deleted `useMemsCalibrationToggleProvider`; `flutter analyze` should be clean.
