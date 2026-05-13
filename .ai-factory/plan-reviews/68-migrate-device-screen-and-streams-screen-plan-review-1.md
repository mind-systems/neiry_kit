# Plan Review: 68-migrate-device-screen-and-streams-screen

## Code Review Summary

**Files Reviewed:** 1 plan file + verified targets (`device_screen.dart`, `main.dart`, `streams_screen.dart`, `neiry_service_provider.dart`, `neiry_service.dart`, `stream_providers.dart`, `device_state_providers.dart`)
**Risk Level:** 🟢 Low

### Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`):** Present but not strictly enforced for this kind of provider-wiring change. No architectural concerns: the plan stays inside the `example/` app and keeps the established split (screens → providers → service → SDK). No new layer dependencies introduced.
- **Rules (`.ai-factory/RULES.md`):** No `RULES.md` present. No project rule violations to flag.
- **Roadmap (`.ai-factory/ROADMAP.md`):** Plan aligns with the **"Migrate device_screen and streams_screen"** item under "Example app architecture refactor" (line 92). The plan's scope matches that bullet exactly. No missing roadmap linkage.
- **Skill-context (`.ai-factory/skill-context/aif-review/SKILL.md`):** Not present. Defaults apply.

### Critical Issues

None. The plan is internally consistent and matches what's on disk.

### Major Findings

None. The plan's stated facts were verified against the codebase:

- `example/lib/providers/active_device_provider.dart` is indeed deleted (`ls` confirms). ✓
- The only remaining references are in `main.dart` and `device_screen.dart` (grep confirms — no other files reference `activeDeviceProvider`). ✓
- `neiryServiceProvider` is wired exactly as described (file present, returns `NeiryService`, `ref.onDispose(s.dispose)` registered). ✓
- `NeiryService.connect / start / stop / disconnect / dispose` semantics match the plan's claims (verified in `services/neiry_service.dart`):
  - `start()` throws `StateError('Not connected')` when no device — see line 285.
  - `stop()` is a no-op when `_device == null` — see line 294.
  - `disconnect()` is a no-op when `_device == null` — see line 233.
  - `dispose()` is idempotent (early-return on `_disposed = true`) — see line 304. ✓
- All five providers `streams_screen.dart` imports (`eegProvider`, `psdProvider`, `batteryProvider`, `artifactsProvider`, `resistanceMapProvider`) are still defined in `stream_providers.dart` and all already source from `neiryServiceProvider`. ✓
- `deviceConnectionStateProvider`, `deviceModeProvider`, `deviceUiStateProvider`, `deviceIsStartedProvider` are all already routed through `NeiryService`. ✓

### Minor Concerns (Non-blocking)

1. **`connect()` does not forward `IndividualNfbData`.** `NeiryService.connect(serial, {nfbData})` accepts an optional `IndividualNfbData?` that determines whether classifiers are instantiated `withCalibration` (see `neiry_service.dart` lines 105–144). The plan calls `connect(serial)` with no `nfbData`, which means the "Use NFB Calibration" toggle in the MEMS and Productivity screens cannot take effect — calibration data is now a connect-time decision (per milestone 64 design and ROADMAP line 88). The downstream milestone ("Migrate classifiers_screen, mems_screen, productivity_cardio_screen") notes that the toggle becomes a "preference only, takes effect on next connect", but that wiring requires `device_screen._connect()` to read the toggle/`nfbCalibrationProvider` and pass it through. This plan **defers** that work without acknowledging it. Suggest adding a one-line note in Task 1 like: *"Calibration data wiring is intentionally deferred — `_connect()` calls `connect(serial)` without `nfbData`; the next milestone will thread `nfbCalibrationProvider` through."* This is documentation, not a code change.

2. **`_start()` silent-no-op → SnackBar regression.** The old `_start()` early-returned on `device == null`. After this plan, `NeiryService.start()` throws `StateError('Not connected')`, which the generic `catch (e)` in `_start()` will surface to the user as a SnackBar reading roughly *"Bad state: Not connected"*. In practice the **Start** button is only enabled when `uiState == DeviceUiState.connected`, so the path should be unreachable; but if a connection drops between tap and async resolution, the user will see an unfriendly error. Acceptable as-is for an example app, but worth noting. (Mirror concern for the now-removed `_stop()` null-guard, except `stop()` is a no-op so it's fine.)

3. **`_container.read(neiryServiceProvider)` may instantiate on dispose.** Task 2 calls `_container.read(neiryServiceProvider).dispose()` inside `_cleanupAndDispose()`. If for any reason the provider was never read during the app session (e.g. the app crashed before any screen built), reading it here will lazily construct a fresh `NeiryService` (which constructs `DeviceLocator`) only to immediately dispose it. Harmless in practice — every screen watches the provider, so this branch is unreachable in normal flow — but slightly ugly. Not worth changing.

4. **Task 3 is a verification step, not work.** Task 3 reads as an assertion rather than an action ("Confirm the file still imports …"). That's fine for a small migration, but consider explicitly stating "No edit required — listed only for traceability." The contingency clause ("If any of these provider names have moved…") is dead code given the verified state of `stream_providers.dart`, but it does no harm.

### Positive Notes

- The plan correctly identifies that `streams_screen.dart` needs **zero** edits because milestone 65 already moved provider sources to `neiryServiceProvider`.
- The double-dispose concern (explicit `await dispose()` + implicit `ref.onDispose(s.dispose)` on `_container.dispose()`) is anticipated and correctly resolved by leveraging `NeiryService.dispose`'s `_disposed` guard.
- Scope is tight: the plan explicitly refuses to fix the other broken screens (`classifiers_screen`, `mems_screen`, `productivity_cardio_screen`) that grep confirms still reference deleted classifier providers — that work is correctly deferred to the next ROADMAP bullet.
- Imports paths match the file tree exactly (`'../providers/neiry_service_provider.dart'` from `screens/`, `'providers/neiry_service_provider.dart'` from `main.dart`).
- The plan preserves `log(..., name: 'Neiry')` diagnostic calls from milestone 60 — important for manual on-device testing.
- Task 4 (compile-check) is included and bounded — analyzer noise outside the three in-scope files is correctly out-of-scope.

PLAN_REVIEW_PASS
