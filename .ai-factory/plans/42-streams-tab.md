# Plan: Streams tab

## Context

Implement the Streams tab of the example app — five throttled Riverpod providers that wrap the plugin's data streams (EEG, PSD, resistance, battery, artifacts) and a screen that displays all of them with appropriate formatting and visual indicators.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Providers

- [x] **Task 1: Create stream providers**
  Files: `example/lib/providers/stream_providers.dart`

  Create a single file with all five stream providers. Import `rxdart` for `throttleTime`, `activeDeviceProvider` for the device handle, and `deviceIsStartedProvider` for the started gate.

  **`eegProvider`** — `StreamProvider<EegData>`. Watch `activeDeviceProvider`; if null return `Stream.empty()`. Apply `throttleTime(Duration(milliseconds: 100))` on `device.eegStream` BEFORE the provider exposes it (throttle first, no map/transform after — the `EegData` model is already decoded by the plugin). Yields 10 Hz to the UI.

  **`psdProvider`** — `StreamProvider<PsdData>`. Same pattern, `throttleTime(Duration(milliseconds: 500))` on `device.psdStream`. Yields 2 Hz.

  **`batteryProvider`** — `StreamProvider<int>`. `throttleTime(Duration(milliseconds: 1000))` on `device.batteryStream`. Yields 1 Hz.

  **`artifactsProvider`** — `StreamProvider<EegArtifactData>`. Unthrottled — `device.artifactsStream` passed directly. Bool flags need immediate feedback.

  **`resistanceMapProvider`** — `NotifierProvider<ResistanceMapNotifier, Map<String, double>>`. This is NOT a `StreamProvider` because resistance fires per-channel independently and must be accumulated into a single map.

  `ResistanceMapNotifier extends Notifier<Map<String, double>>`:
  - `build()`: watch `activeDeviceProvider` and `deviceIsStartedProvider`. Cancel any previous subscription. If device is null or not started, return empty map. Otherwise subscribe to `device.resistanceStream.listen((data) { ... })` and call `ref.onDispose` to cancel the subscription.
  - In the listener: iterate `data.channelNames` and `data.values` (both are `List`, indexed together — `ResistanceData` carries `channelNames: List<String>`, `values: List<double>`, `channelCount: int`). Merge each channel's latest value into `state`:
    ```dart
    final updated = Map<String, double>.of(state);
    for (var i = 0; i < data.channelCount; i++) {
      updated[data.channelNames[i]] = data.values[i];
    }
    state = updated;
    ```
  - Store the `StreamSubscription` in a field; cancel in `build()` before re-subscribing (Riverpod calls `build()` when watched dependencies change). Follow the same pattern as `deviceConnectionStateProvider` in `device_state_providers.dart`.

### Phase 2: UI

- [x] **Task 2: Implement StreamsScreen** (depends on Task 1)
  Files: `example/lib/screens/streams_screen.dart`

  Replace the stub with a `ConsumerWidget` (no local mutable state needed — all state lives in providers). Use `SingleChildScrollView` with a `Column` of `Card` widgets, one per data section. Follow the visual style of `device_screen.dart` (`Card` + `Padding` + section titles).

  **EEG section:**
  - `ref.watch(eegProvider)` → `AsyncValue<EegData>`. Use `.when(data: ..., loading: ..., error: ...)`.
  - Show "Channel count: N" as a subtitle.
  - For each channel (index 0..`channelCount-1`), show a row: "Ch N: X.XXX μV" using the last sample in `rawValues[channel].last`. Format to 3 decimal places.
  - Loading state: show "Waiting for EEG data..." text.

  **PSD section:**
  - `ref.watch(psdProvider)` → `AsyncValue<PsdData>`.
  - Compute average band power per band. For each of the five bands (delta, theta, alpha, smr, beta), use the corresponding `Lower`/`Upper` boundaries from the `PsdData` instance:
    1. Find indices in `psd.frequencies` where `frequencies[i] >= bandLower && frequencies[i] <= bandUpper`.
    2. Average `psd.values[ch][i]` across those indices, then average across all channels.
  - Display as a column of labeled rows: "Delta: X.XXX", "Theta: X.XXX", etc.
  - Extract band power computation into a private top-level helper `double _bandPower(PsdData psd, double lower, double upper)` to keep the widget clean.
  - Loading state: "Waiting for PSD data...".

  **Resistance section:**
  - `ref.watch(resistanceMapProvider)` → `Map<String, double>`.
  - If map is empty, show "No resistance data".
  - Otherwise show a `DataTable` or a `Column` of `ListTile`s: channel name, value in kOhm formatted to 1 decimal, and a color indicator — green circle (`Icons.circle`, color green) if value < 500, yellow if 500–1000, red if > 1000. Thresholds from the SDK docs: < 500 kOhm = good contact.

  **Battery section:**
  - `ref.watch(batteryProvider)` → `AsyncValue<int>`.
  - Show "Battery: N%" with a `LinearProgressIndicator` (value = N / 100).
  - Loading state: "Waiting for battery...".

  **Artifacts section:**
  - `ref.watch(artifactsProvider)` → `AsyncValue<EegArtifactData>`.
  - For each channel, show: "Ch N: artifact=Y quality=Z.ZZ". `artifacts` is `List<int>` (0 or 1 per channel), `qualities` is `List<double>` per channel.
  - Use red text or icon when `artifacts[i] != 0` for immediate visual feedback.
  - Loading state: "Waiting for artifacts...".

  All sections should gracefully handle the case when the device is not connected or not started — `StreamProvider`s will be in loading state until the first event arrives, which is correct UX.
