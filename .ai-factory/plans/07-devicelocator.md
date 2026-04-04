# Plan: DeviceLocator

## Context

Implement the `DeviceLocator` Dart API class — the first public API class in `lib/src/api/`. It wraps the native `clCDeviceLocator` lifecycle (create, scan, create device, threading, dispose) via the existing channel contract, exposing an idiomatic Dart interface with singleton semantics, stream-based discovery, and safe dispose/cancel behavior.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Channel contract additions

- [x] **Task 1: Add missing DeviceLocator method names, argument key, and remove orphaned constant**
  Files: `lib/src/channel/channel_names.dart`
  Add four method name constants to `DeviceLocatorMethods`:
  - `create` — maps to `clCDeviceLocator_Create` / `CreateWithLogDirectory`
  - `createDevice` — maps to `clCDeviceLocator_CreateDevice` (the milestone requires this call to go through `NeiryChannels.deviceLocator`, not `NeiryChannels.device`, because the C API needs the locator handle)
  - `dispose` — maps to `clCDeviceLocator_Destroy`
  - `update` — maps to `clCDeviceLocator_Update`

  **Remove** `DeviceLocatorMethods.requestDevices` — it is unused because `requestDevices` goes through `EventChannel`, not `MethodChannel`. Leaving an orphaned constant without explanation will confuse later milestones.

  Add one argument key to `NeiryArgs`:
  - `logDirectory` — used by the factory constructor to pass the optional log path to native

  Leave the existing `DeviceMethods.createDevice` in place — it may be repurposed or removed in a later milestone when `Device` is implemented; do not delete it now.

### Phase 2: DeviceLocator class

- [x] **Task 2: Create DeviceLocator class**
  Files: `lib/src/api/device_locator.dart` (new file)
  Create the file under a new `lib/src/api/` directory. Follow the architecture's dependency rules: import from `lib/src/channel/` (constants, enums) and `lib/src/models/` (DeviceInfo) only.

  **Singleton factory.** Use a private constructor + static `_instance` field. The public `factory DeviceLocator({String? logDirectory})` returns the existing instance if already created, or creates a new one. On creation: instantiate the Dart object immediately, fire the native create call via `_channel.invokeMethod(DeviceLocatorMethods.create, ...)` passing `{NeiryArgs.logDirectory: logDirectory}` when non-null, and store the resulting `Future<void>` as `_nativeReady`.

  **`_nativeReady` failure recovery.** Chain `.catchError()` (or `.then(..., onError: ...)`) on the `_nativeReady` future so that if the native `create` call fails (e.g., Bluetooth framework unavailable, SDK init error), `_instance` is nulled out automatically. This way the next `DeviceLocator()` call retries creation instead of returning a permanently broken singleton. Methods that `await _nativeReady` will still see the error and throw — but the caller can recover by calling `DeviceLocator()` again.

  **Private channel fields.** Store both:
  - `static const _channel = MethodChannel(NeiryChannels.deviceLocator)` — avoids re-creating on every method call.
  - `static const _deviceListEventChannel = EventChannel(NeiryEvents.deviceList)` — cached for consistency with the MethodChannel pattern (EventChannel is lightweight, but caching is consistent and avoids re-instantiation on every `requestDevices` call).

  **`_checkNotDisposed()`** — private method that throws `StateError('DeviceLocator has been disposed')` if `_disposed` is true. Every public method (`requestDevices`, `createDevice`, `setSingleThreaded`, `update`, `dispose`) must call this first.

  **`requestDevices({NeiryDeviceType type = NeiryDeviceType.any, int searchTime = 5})`** → `Stream<List<DeviceInfo>>`:
  - Does NOT await `_nativeReady`. The `create` MethodChannel call is dispatched to the native platform thread before `receiveBroadcastStream`'s `onListen` message because `send()` calls through the binary messenger are FIFO on the platform thread. By the time `onListen` fires, the native locator handle exists. Add a code comment documenting this FIFO ordering assumption.
  - Must NOT make a separate MethodChannel call — the scan starts inside the native `StreamHandler.onListen`.
  - Pass arguments through `_deviceListEventChannel.receiveBroadcastStream({NeiryArgs.deviceType: type.code, NeiryArgs.searchTime: searchTime})`.
  - Must use a `StreamController<List<DeviceInfo>>` internally so that `_scanSubscription` is assigned synchronously (before any async gap), enabling cancel-on-overlap and cancel-in-dispose.
  - If `_scanSubscription` is already non-null when called, cancel the previous subscription before starting a new one (cancel-on-overlap).
  - Subscribe to the `receiveBroadcastStream` and forward mapped data to the controller. Capture the subscription in a local `thisSub` variable.
  - Wire `StreamController.onCancel` and the stream's `onDone` to cancel `thisSub` and clear `_scanSubscription` — but only if `identical(_scanSubscription, thisSub)` is true, so cancelling an old consumer's stream cannot kill a newer active scan.
  - The stream emits once (the device list) then completes — this is the native SDK's behavior.
  - Return `controller.stream`.

  **`createDevice(String serial)`** → `Future<void>`:
  - Awaits `_nativeReady`.
  - Calls `_channel.invokeMethod(DeviceLocatorMethods.createDevice, {NeiryArgs.serial: serial})`.
  - Returns void — the `Device` class wrapping will be done by the `Device` milestone. For now, the locator just tells native to create the handle.

  **`setSingleThreaded(bool enabled)`** → `Future<void>`:
  - Awaits `_nativeReady`.
  - Calls `_channel.invokeMethod(DeviceLocatorMethods.setSingleThreaded, {NeiryArgs.enabled: enabled})`.

  **`update()`** → `Future<void>`:
  - Awaits `_nativeReady`.
  - Calls `_channel.invokeMethod(DeviceLocatorMethods.update)`.
  - Only meaningful after `setSingleThreaded(true)` — the C SDK's `Update()` is a no-op in multi-threaded mode. Do not enforce this in Dart; just pass through.

  **`dispose()`** → `Future<void>`:
  - Calls `_checkNotDisposed()`, then sets `_disposed = true` immediately (prevents re-entrant calls).
  - Cancels `_scanSubscription` if non-null.
  - Awaits `_nativeReady` before sending the native `destroy` call. This ensures the native `create` has completed (or failed) before `destroy` is dispatched, avoiding a race where `destroy` arrives before `create` finishes. If `_nativeReady` completed with an error (singleton was already nulled by the recovery handler), catch the error and skip the native `destroy` call — there's nothing to destroy.
  - Calls `_channel.invokeMethod(DeviceLocatorMethods.dispose)`.
  - Nulls out `_instance` so a future `DeviceLocator()` call creates a fresh instance.
  - Returns `Future<void>` so callers can `await dispose()` before re-creating. This eliminates the race where a new `create` call could arrive on the native side before the old `destroy` completes.

- [x] **Task 3: Export DeviceLocator from barrel**
  Files: `lib/neiry_kit.dart`
  Add `export 'src/api/device_locator.dart';` to the barrel file. Place it above the existing model exports to group API classes at the top (they are a higher-level abstraction).
