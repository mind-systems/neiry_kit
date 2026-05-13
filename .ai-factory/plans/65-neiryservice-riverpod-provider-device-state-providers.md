# Plan: NeiryService Riverpod provider + device state providers

## Context
Wire the existing `NeiryService` (in `example/lib/services/neiry_service.dart`) into Riverpod as the single device-layer entry point. Replace the legacy `DeviceLocator`/`ActiveDevice` provider duo and re-source all device-scoped stream providers from the new service so the example app no longer reads `Device` directly from Riverpod.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Service provider + scan rewire

- [x] **Task 1: Create `neiryServiceProvider`**
  Files: `example/lib/providers/neiry_service_provider.dart` (new)
  Add a single-file Riverpod provider:
  ```dart
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import '../services/neiry_service.dart';

  final neiryServiceProvider = Provider<NeiryService>((ref) {
    final s = NeiryService();
    ref.onDispose(s.dispose);
    return s;
  });
  ```
  Plain `Provider` (not `NotifierProvider`) — `NeiryService` is a stateful object whose lifecycle is fully owned by itself; Riverpod only needs to hand out the same instance and dispose it on container teardown. No other code in this task.

  Note on disposal: `NeiryService.dispose()` returns `Future<void>`, but `ref.onDispose` does not await its callback — the future is fire-and-forget. This is acceptable because final teardown is awaited explicitly by `main.dart`'s `_cleanupAndDispose()` (updated in milestone #92 to `await ref.read(neiryServiceProvider).dispose()`). The `ref.onDispose` registration here is a fallback for container disposal during the lifetime of the app (e.g. tests), not the primary disposal path.

- [x] **Task 2: Rewire `deviceScanProvider` to NeiryService** (depends on Task 1)
  Files: `example/lib/providers/device_scan_provider.dart`
  Replace the body so it reads `neiryServiceProvider` instead of `deviceLocatorProvider`. Keep the `FutureProvider.family<List<DeviceInfo>, (NeiryDeviceType, int)>` signature and the public name `deviceScanProvider` unchanged so callers (`device_screen.dart`) need no changes. New implementation:
  ```dart
  final deviceScanProvider =
      FutureProvider.family<List<DeviceInfo>, (NeiryDeviceType, int)>(
    (ref, params) {
      final service = ref.read(neiryServiceProvider);
      final (type, searchTime) = params;
      return service.scan(type: type, searchTime: searchTime).first;
    },
  );
  ```
  Note: use `ref.read` (not `watch`) — the service is a long-lived singleton; re-watching would only matter if the service identity could change, which it cannot. Drop the `import 'device_locator_provider.dart';` and replace with `import 'neiry_service_provider.dart';`.

### Phase 2: Device state providers re-sourced from NeiryService

- [x] **Task 3: Rewrite `device_state_providers.dart`** (depends on Task 1)
  Files: `example/lib/providers/device_state_providers.dart`
  Replace the `activeDeviceProvider` reads with `neiryServiceProvider` reads. Source `deviceConnectionStateProvider` from `neiryService.connectionStateStream` and `deviceModeProvider` from `neiryService.modeStream`. Both stay as `StreamProvider`s.
  - `deviceConnectionStateProvider`:
    ```dart
    final deviceConnectionStateProvider = StreamProvider<NeiryConnectionState>(
      (ref) => ref.watch(neiryServiceProvider).connectionStateStream,
    );
    ```
    The service's broadcast `_connectionStateController` is opened at construction and never closed until `dispose`, so the stream is always safe to subscribe to. The previous fallback `Stream.value(NeiryConnectionState.disconnected)` is no longer needed — the controller simply emits nothing until `connect()` wires it up; consumers already handle `AsyncValue.loading`.

    Behavior change confirmation: before this plan, consumers saw `AsyncData(disconnected)` immediately. After this plan, they see `AsyncLoading` until the service emits. Verified consumers: only `deviceUiStateProvider` reads `deviceConnectionStateProvider` (grep confirmed — `streams_screen.dart` and other screens watch `deviceUiStateProvider` / `deviceModeProvider` instead). `deviceUiStateProvider` uses `whenOrNull(data: ...)` (see `device_state_providers.dart:46-57`), so loading → `idle`, matching the previous `disconnected` → `idle` mapping. No `startWith` shim needed; behavior is safe.
  - `deviceModeProvider`:
    ```dart
    final deviceModeProvider = StreamProvider<NeiryDeviceMode>(
      (ref) => ref.watch(neiryServiceProvider).modeStream,
    );
    ```
  - `deviceIsStartedProvider` — unchanged (`StateProvider<bool>((ref) => false)`); will be flipped manually by `device_screen.dart` in the later migration milestone.
  - `DeviceUiState` enum and `deviceUiStateProvider` derivation — unchanged.
  - Remove the `import 'active_device_provider.dart';` line.

### Phase 3: Stream providers re-sourced from NeiryService

- [x] **Task 4: Rewrite data stream providers in `stream_providers.dart`** (depends on Task 1)
  Files: `example/lib/providers/stream_providers.dart`
  Replace `activeDeviceProvider` watches with `neiryServiceProvider` watches for `eegProvider`, `psdProvider`, `batteryProvider`, and `artifactsProvider`. Each becomes:
  ```dart
  final eegProvider = StreamProvider<EegData>((ref) {
    final service = ref.watch(neiryServiceProvider);
    return service.eegStream.throttleTime(const Duration(milliseconds: 100));
  });

  final psdProvider = StreamProvider<PsdData>((ref) {
    final service = ref.watch(neiryServiceProvider);
    return service.psdStream.throttleTime(const Duration(milliseconds: 500));
  });

  final batteryProvider = StreamProvider<int>((ref) {
    final service = ref.watch(neiryServiceProvider);
    return service.batteryStream.throttleTime(const Duration(milliseconds: 1000));
  });
  ```
  **`artifactsProvider` — important:** `NeiryService` does **not** currently expose `artifactsStream`. Add a new broadcast controller `_artifactsController = StreamController<EegArtifactData>.broadcast()` to `NeiryService` (fields list near other `_*Controller` declarations), a `Stream<EegArtifactData> get artifactsStream => _artifactsController.stream;` getter, a fan-in subscription `_device!.artifactsStream.listen(_artifactsController.add, onError: _artifactsController.addError)` appended to the `_activeSubscriptions.addAll([...])` block inside `connect()`, and `await _artifactsController.close();` in `dispose()`.

  Placement note for `_artifactsController.close()` in `dispose()`: put it next to the other device-stream controllers (after `_batteryController.close()`, before the classifier controllers) so the close sequence stays grouped by source. Order doesn't affect correctness — all controllers are independent — but file-local grouping makes the surrounding code easier to scan.

  Then rewrite `artifactsProvider`:
  ```dart
  final artifactsProvider = StreamProvider<EegArtifactData>((ref) {
    final service = ref.watch(neiryServiceProvider);
    return service.artifactsStream;
  });
  ```
  Drop the `import 'active_device_provider.dart';` and replace with `import 'neiry_service_provider.dart';`. **Preserve the existing `import 'package:rxdart/rxdart.dart';`** — the `.throttleTime(...)` extension calls still need it; an over-aggressive rewrite must not strip this import.

  Keep all throttle timings identical to the current behavior.

- [x] **Task 5: Re-point `resistanceMapProvider` to NeiryService** (depends on Task 1)
  Files: `example/lib/providers/stream_providers.dart` (same file as Task 4)
  Inside the existing `ResistanceMapNotifier`, replace the `ref.watch(activeDeviceProvider)` lookup with `ref.watch(neiryServiceProvider)` and subscribe to `service.resistanceStream` instead of `device.resistanceStream`. The accumulation logic (per-channel map merge) stays bit-for-bit identical. Resulting `build()`:
  ```dart
  @override
  Map<String, double> build() {
    final service = ref.watch(neiryServiceProvider);
    _subscription?.cancel();
    _subscription = service.resistanceStream.listen((data) {
      final updated = Map<String, double>.of(state);
      for (var i = 0; i < data.channelCount; i++) {
        updated[data.channelNames[i]] = data.values[i];
      }
      state = updated;
    });
    ref.onDispose(() {
      _subscription?.cancel();
      _subscription = null;
    });
    return {};
  }
  ```
  The pre-connect empty-map default is preserved because the service's resistance controller simply emits nothing until `connect()` wires its fan-in subscription.

### Phase 4: Delete legacy providers

- [x] **Task 6: Delete `active_device_provider.dart` and `device_locator_provider.dart`** (depends on Tasks 2, 3, 4, 5)
  Files: `example/lib/providers/active_device_provider.dart` (delete), `example/lib/providers/device_locator_provider.dart` (delete)
  Both files are now unused by the providers rewritten in Tasks 2–5. Delete them outright (`rm`). Do **not** edit screens or other call sites in this plan — those migrations are explicitly assigned to later roadmap milestones (#92 device/streams screens, #93 classifier screens, #90 classifier stream providers).

  Expected `flutter analyze` errors after deletion: unresolved imports of `active_device_provider.dart` in **eight** files:
  1. `example/lib/main.dart`
  2. `example/lib/screens/device_screen.dart`
  3. `example/lib/providers/cardio_classifier_provider.dart`
  4. `example/lib/providers/emotions_classifier_provider.dart`
  5. `example/lib/providers/mems_classifier_provider.dart`
  6. `example/lib/providers/nfb_classifier_provider.dart`
  7. `example/lib/providers/physio_classifier_provider.dart`
  8. `example/lib/providers/productivity_classifier_provider.dart`

  Plus unresolved imports of `device_locator_provider.dart` in whatever files still reference it (verify with grep before deletion; the only known consumer was `device_scan_provider.dart` which Task 2 already detached).

  `classifiers_screen.dart` does **not** import `active_device_provider.dart` directly — it consumes the six classifier providers, so its breakage will cascade through them, not be a direct import error.

  These errors are expected and acceptable: the six classifier-provider files are slated for deletion in milestone #90 (the immediate next milestone), and the screen/main fixes land in #92/#93. Run `flutter analyze` after deletion only to confirm the error set matches the eight-file list above — if any other file shows a broken import of these two deleted files, that's an unexpected consumer and must be investigated before declaring the milestone done. Do not preemptively patch screens or classifier providers here.

## Commit Plan
- **Commit 1** (after tasks 1–2): "Add neiryServiceProvider and rewire device scan"
- **Commit 2** (after tasks 3–5): "Re-source device state and stream providers from NeiryService"
- **Commit 3** (after task 6): "Delete legacy active_device_provider and device_locator_provider"
