# Plan: Device tab

## Context
Build the Device tab of the example app — scan for BLE devices, create/connect/start/stop a single device, and expose the full device lifecycle as Riverpod providers so state survives tab switches via `StatefulShellRoute.indexedStack`.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Providers

- [x] **Task 1: Device scan provider**
  Files: `example/lib/providers/device_scan_provider.dart`
  Create `deviceScanProvider` as `FutureProvider.family<List<DeviceInfo>, (NeiryDeviceType, int)>`. It watches `deviceLocatorProvider`, calls `locator.requestDevices(type: type, searchTime: searchTime).first`, and returns the one-shot result. `AsyncValue.loading` = scan in progress, `AsyncValue.data` = scan complete. To re-scan, the UI calls `ref.invalidate(deviceScanProvider((type, time)))`. Follow the existing pattern in `device_locator_provider.dart` (imports from `neiry_kit`, provider as top-level final). Note: `deviceLocatorProvider` returns non-nullable `DeviceLocator` — no null guard needed when reading it.

- [x] **Task 2: Active device provider**
  Files: `example/lib/providers/active_device_provider.dart`
  Create `ActiveDeviceNotifier extends Notifier<Device?>` exposed as `activeDeviceProvider`. `build()` returns `null`. Method `createAndConnect(String serial, {bool bipolarChannels = false})`: reads `deviceLocatorProvider` (non-nullable — no null check), calls `createDevice(serial)`, then `device.connect(bipolarChannels: bipolarChannels)`, sets `state = device`. Before storing a new device, enforce one-device-at-a-time: if `state != null`, call `stop()` → `disconnect()` → `dispose()` on the old device (wrapped in try/catch, best-effort). Method `disconnectAndDispose()`: calls `stop()` → `disconnect()` → `dispose()` on current device, sets `state = null`. Register `ref.onDispose` in `build()` that synchronously calls `state?.dispose()` as a last-resort safety net (async cleanup happens explicitly before container disposal — see Task 6).

- [x] **Task 3: Connection state, started flag, and composite UI state providers**
  Files: `example/lib/providers/device_state_providers.dart`
  Create three providers in one file:

  1. `deviceConnectionStateProvider` as `StreamProvider<NeiryConnectionState>`: watches `activeDeviceProvider`, if null returns `Stream.value(NeiryConnectionState.disconnected)`, otherwise listens to `device.connectionStateStream`.

  2. `deviceIsStartedProvider` as `StateProvider<bool>` defaulting to `false`. Set manually by action handlers after `device.start()` / `device.stop()` — not derived from a stream (the SDK has no "started" stream).

  3. `DeviceUiState` enum (`idle`, `connected`, `started`) defined in this file. `deviceUiStateProvider` as `Provider<DeviceUiState>`: watches `deviceConnectionStateProvider` and `deviceIsStartedProvider`. Logic: if connection is **not** `NeiryConnectionState.connected` → `idle` (this covers both `disconnected` and `unsupportedConnection`); if connected and `isStarted` → `started`; if connected and not started → `connected`. On loading/error from `deviceConnectionStateProvider` → `idle`.

### Phase 2: UI

- [x] **Task 4: Device screen widget**
  Files: `example/lib/screens/device_screen.dart`
  Replace the stub with a `ConsumerWidget`. Layout (single scrollable column):

  **Scan section:** A row with a `NeiryDeviceType` dropdown (default `any`), a "Search time" numeric field (default `5`), and a "Scan" `ElevatedButton`. Pressing Scan invalidates `deviceScanProvider` with current params. Below the row, show scan results as a `ListView` of `ListTile`s (title = `deviceInfo.name`, subtitle = `deviceInfo.serial`). While `AsyncValue.loading`, show a `CircularProgressIndicator`. On error, show the error message.

  **Device actions section:** Four buttons in a row or wrap: Connect, Disconnect, Start, Stop. Enabled state derived from `deviceUiStateProvider`:
  - Connect: enabled when a device is selected from the scan list AND state is `idle`
  - Start: enabled when `connected`
  - Stop: enabled when `started`
  - Disconnect: enabled when `connected` or `started`

  Connect taps the selected `DeviceInfo.serial` and calls `ref.read(activeDeviceProvider.notifier).createAndConnect(serial)`. Start calls `device.start()` then sets `ref.read(deviceIsStartedProvider.notifier).state = true`. Stop calls `device.stop()` then sets `deviceIsStartedProvider` to `false`. Disconnect calls `ref.read(activeDeviceProvider.notifier).disconnectAndDispose()` and resets `deviceIsStartedProvider` to `false`.

  **Status section:** Show current `DeviceUiState` as a text label (e.g., "Status: connected"). Show connection state from `deviceConnectionStateProvider` as secondary info.

  Keep a local `selectedSerial` as widget state (either via `useState` with hooks, or a plain `StatefulWidget` local variable, or a simple `StateProvider<String?>`) to track which scanned device the user tapped.

- [x] **Task 5: Error handling in device actions**
  Files: `example/lib/screens/device_screen.dart`
  Wrap all async button handlers (`createAndConnect`, `start`, `stop`, `disconnectAndDispose`) in try/catch. On `NeiryException` or generic error, show a `SnackBar` with the error message. If connect fails, reset `activeDeviceProvider` to null. If start fails, keep `deviceIsStartedProvider` as false. This prevents the UI from entering an inconsistent state.

### Phase 3: App lifecycle cleanup

- [x] **Task 6: Async disposal in app State.dispose()**
  Files: `example/lib/main.dart`
  Convert `NeiryExampleApp` from `StatelessWidget` to a plain `StatefulWidget` (not `ConsumerStatefulWidget` — the cleanup reads from `_container` directly and never uses `ref`). Create a `ProviderContainer` explicitly in `initState()`. Pass it as `parent` to `ProviderScope`. In `dispose()`, run async cleanup before container disposal: read `activeDeviceProvider` — if non-null, call `stop()` → `disconnect()` → `dispose()` on the device (each in try/catch). Do **not** dispose `DeviceLocator` here — `ref.onDispose` in `device_locator_provider.dart` already handles it when `_container.dispose()` runs, and `DeviceLocator.dispose()` is not idempotent (calling it twice throws `StateError`). After device cleanup completes, call `_container.dispose()` which triggers all `ref.onDispose` callbacks including the locator's.

## Commit Plan
- **Commit 1** (after tasks 1-3): "Add device lifecycle Riverpod providers"
- **Commit 2** (after tasks 4-6): "Implement Device tab UI with scan, connect, and cleanup"
