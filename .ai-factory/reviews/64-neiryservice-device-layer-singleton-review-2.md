# Code Review 2: NeiryService — device layer singleton

**Plan:** `.ai-factory/plans/64-neiryservice-device-layer-singleton.md`
**Files reviewed:**
- `example/lib/services/neiry_service.dart` (369 lines, new)
- `lib/src/api/nfb_calibrator.dart` (modified — const constructor + `_NfbCalibratorHandle` + `handle` sentinel)

## Diff since review 1

The only changes since review 1 are to `.ai-factory/` documents (plan task checkmarks, review 1 itself). The two source files are byte-identical to what review 1 inspected. I re-read both files end-to-end to confirm.

## Re-verification of all tasks

- **Task 1** — `neiry_service.dart:15-78` — service class, no Flutter/Riverpod imports, all 13 controllers eagerly initialised, `_connecting` re-entry guard field present, `_calibrator` field present, `_checkNotDisposed()` guard correctly scoped (scan/connect/start only).
- **Task 2** — `neiry_service.dart:83-89` (scan), `:281-299` (dispose). Single-flag re-entry guard. All 13 controllers closed after `disconnect()` + `_locator.dispose()`.
- **Task 3** — `neiry_service.dart:99-202` — `_connecting` set under outer try/finally; createDevice-then-connect cleanup mirrors `active_device_provider.createAndConnect()`; classifiers constructed eagerly with calibration branching; `_safeProductivityWithCalibration` helper at `:359-368`; `_calibrator = NfbCalibrator.handle` set *before* fan-in subscriptions per plan review 2 issue 6; all 13 fan-in subscriptions wired with `onError` forwarding.
- **Task 4** — `neiry_service.dart:210-274` — disconnect ordering matches plan review 2 issue 2 (cancel subs → dispose classifiers concurrently → device stop/disconnect/dispose → reset fields). `start()` and `stop()` propagate errors as required (no try/catch swallowing). `stop()` returns `Future<void>` discarding the `bool` from `Device.stop()`.
- **Task 5** — `neiry_service.dart:304-344` — all 13 stream getters present with the exact types listed in the plan. Stream sources verified against `lib/src/api/classifiers/*.dart` and `lib/src/api/device.dart`. Out-of-scope streams (`artifactsStream`, calibration progress/completion, `ppgStream`) correctly omitted.
- **Task 6** — `neiry_service.dart:349-355` plus `nfb_calibrator.dart:41,47,304-306` — `physioClassifier`/`productivityClassifier` getters exposed; the other four are stream-only; `NfbCalibrator? get calibrator` returns the sentinel. SDK touch applies the const-constructor fix from plan review 2 issue 1.
- **Task 7** — verification step; no code change.

## Findings

No new findings. The four minor observations from review 1 (M1: `dispose()` not robust to `_locator.dispose()` throwing; M2: stale `_nfbData` after createDevice failure; M3: theoretical partial-classifier leak; M4: documented `_connecting`/disconnect race) are all still present and remain non-blocking — they are defensive hardening notes outside the plan's stated scope and the plan explicitly accepts the trade-offs.

Cross-cutting sanity checks from review 1 (double-listen safety on cached broadcast streams; `Future.wait` with per-element `.catchError` shape; `Device.stop()` bool discard; `NeiryDeviceType.any` presence; sentinel reachability via the existing barrel export; no Flutter/Riverpod imports) all continue to hold.

## Recommendation

Ship. The implementation faithfully realises the plan, including the plan-review-2 corrections (parent-class `const NfbCalibrator()`; classifier-before-device disconnect ordering; `stop()` error propagation; single-flag `_disposed` guard; `_calibrator` assigned before fan-in subscriptions). No bugs, type mismatches, or race conditions beyond the ones the plan documents as intentional.

REVIEW_PASS
