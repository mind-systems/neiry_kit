# Plan: Migrate device_screen and streams_screen

## Context

Finish removing the legacy `activeDeviceProvider` from the example app by routing `device_screen.dart` and `main.dart` through `neiryServiceProvider`. `streams_screen.dart` already only consumes provider names re-exported from `stream_providers.dart` and needs no logic change — it just must continue to compile after the import surface is cleaned up.

Key facts gathered during exploration:

- `example/lib/providers/active_device_provider.dart` no longer exists on disk (deleted in milestone "NeiryService Riverpod provider + device state providers"). The two remaining references — `device_screen.dart` and `main.dart` — currently fail to compile.
- `neiryServiceProvider` lives in `example/lib/providers/neiry_service_provider.dart` and returns a `NeiryService` whose `connect/disconnect/start/stop/dispose` semantics already match what the screen needs (see `example/lib/services/neiry_service.dart`).
- `deviceIsStartedProvider` remains in `device_state_providers.dart` and is still a `StateProvider<bool>` set manually from the screen — keep that pattern.
- `stream_providers.dart` already sources from `neiryService` and exposes `eegProvider`, `psdProvider`, `batteryProvider`, `artifactsProvider`, and `resistanceMapProvider` — the exact names `streams_screen.dart` imports today. No file move is required.

## Settings
- Testing: no
- Logging: minimal (preserve existing `dart:developer` `log()` calls in `device_screen.dart`)
- Docs: no

## Tasks

### Phase 1: Wire screens to NeiryService

- [x] **Task 1: Migrate `device_screen.dart` to `neiryServiceProvider`**
  Files: `example/lib/screens/device_screen.dart`
  - Remove the import `'../providers/active_device_provider.dart';`.
  - Add `import '../providers/neiry_service_provider.dart';`.
  - In `_connect()`: keep the early `serial == null` guard and the pre-connect `deviceIsStartedProvider = false` reset; replace `ref.read(activeDeviceProvider.notifier).createAndConnect(serial)` with `await ref.read(neiryServiceProvider).connect(serial);`. Keep the existing `try/catch` that maps `NeiryException` → `_showError(e.message)` and falls back to `e.toString()`.
  - In `_start()`: drop the `final device = ref.read(activeDeviceProvider);` line and the `if (device == null) return;` guard; replace `device.start()` with `await ref.read(neiryServiceProvider).start();`; on success set `ref.read(deviceIsStartedProvider.notifier).state = true;`. Keep the existing `NeiryException` / generic catch branches.
  - In `_stop()`: same shape as `_start()` — call `await ref.read(neiryServiceProvider).stop();` then `ref.read(deviceIsStartedProvider.notifier).state = false;`. `NeiryService.stop()` is a no-op when no device is connected, so no extra null guard is needed.
  - In `_disconnect()`: replace `ref.read(activeDeviceProvider.notifier).disconnectAndDispose()` with `await ref.read(neiryServiceProvider).disconnect();`; keep the post-call `deviceIsStartedProvider = false` write and the existing error handling.
  - Leave `_scan()`, permission handling, and the `_buildScanResults` / `_buildActionsSection` / `_buildStatusSection` widgets unchanged. `deviceUiStateProvider` and `deviceConnectionStateProvider` are already routed through `neiryServiceProvider`, so `uiState` continues to drive button enable/disable logic correctly.
  - Preserve all existing `log(..., name: 'Neiry')` calls verbatim.

- [x] **Task 2: Update `main.dart` cleanup path** (depends on Task 1)
  Files: `example/lib/main.dart`
  - Remove the import `'providers/active_device_provider.dart';`.
  - Add `import 'providers/neiry_service_provider.dart';`.
  - In `_cleanupAndDispose()`, replace the manual `device.stop()` / `device.disconnect()` / `device.dispose()` sequence with a single `await ref.read(...)`-style call against the container: `await _container.read(neiryServiceProvider).dispose();`. `NeiryService.dispose()` already cancels subscriptions, stops streaming, disconnects, and disposes the locator internally, so no extra guards are required.
  - Wrap the `dispose()` call in `try { ... } catch (_) {}` to match the defensive style used elsewhere in the cleanup (the old code swallowed errors at each step).
  - Keep `_container.dispose()` as the final line — `ref.onDispose(s.dispose)` registered in `neiry_service_provider.dart` would also fire, but `NeiryService.dispose()` is idempotent (it returns immediately on `_disposed = true`), so the double-call is safe.
  - Leave the rest of `_NeiryExampleAppState` (initState, build, UncontrolledProviderScope) untouched.

### Phase 2: Verify streams screen and compile

- [x] **Task 3: Verify `streams_screen.dart` requires no changes** (depends on Task 2)
  Files: `example/lib/screens/streams_screen.dart`
  - Confirm the file still imports only `'../providers/stream_providers.dart';` and watches `eegProvider`, `psdProvider`, `resistanceMapProvider`, `batteryProvider`, `artifactsProvider`. All five names are defined in `stream_providers.dart` today and source from `neiryServiceProvider`, so no edit is required.
  - If any of these provider names have moved out of `stream_providers.dart` in practice (e.g. into `classifier_stream_providers.dart`), update the import path accordingly — but do not modify any widget logic. Per the milestone description: "no logic changes in the screen itself".

- [x] **Task 4: Compile-check the example app** (depends on Task 3)
  Files: (no edits — verification only)
  - From `example/`, run `flutter analyze` and confirm there are no unresolved imports referencing the deleted `active_device_provider.dart` and no dangling `activeDeviceProvider` symbols anywhere in the project.
  - If analyzer flags remaining usages outside the three files in scope (device_screen, streams_screen, main), stop and report — those belong to a different milestone and should not be fixed here.
