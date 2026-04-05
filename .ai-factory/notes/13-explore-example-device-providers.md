# Explore: Device Tab — Riverpod Provider Design

Research findings for the `Device tab` example app milestone.

## Provider hierarchy

```
deviceLocatorProvider  (singleton, NotifierProvider)
    ↓
deviceScanProvider     (FutureProvider.family — one-shot scan)
    ↓
activeDeviceProvider   (NotifierProvider<Device?> — managed instance)
    ├── deviceConnectionStateProvider  (StreamProvider)
    ├── deviceIsStartedProvider        (StateProvider<bool> — manual flag)
    ├── deviceUiStateProvider          (Provider — composite enum)
    └── eegBufferProvider              (NotifierProvider — persistent subscription)
```

## DeviceLocator provider

```dart
final deviceLocatorProvider =
    NotifierProvider<DeviceLocatorNotifier, DeviceLocator?>(() => DeviceLocatorNotifier());

class DeviceLocatorNotifier extends Notifier<DeviceLocator?> {
  @override
  DeviceLocator? build() {
    final locator = DeviceLocator();
    ref.onDispose(locator.dispose);  // synchronous — DeviceLocator.dispose() must be sync
    return locator;
  }
}
```

Do NOT create DeviceLocator in `main()` before `runApp()`. Let Riverpod manage its lifecycle.

## Device scanning: FutureProvider, not StreamProvider

`requestDevices()` emits once then closes — this is NOT a continuous stream. Model it as a Future:

```dart
final deviceScanProvider = FutureProvider.family<List<DeviceInfo>, (DeviceType, int)>(
  (ref, params) async {
    final locator = ref.watch(deviceLocatorProvider);
    if (locator == null) throw StateError('Locator not ready');
    final (type, searchTime) = params;
    return await locator.requestDevices(type: type, searchTime: searchTime).first;
  },
);
```

`AsyncValue.loading` = scanning in progress. `AsyncValue.data` = scan complete. Automatic.

To trigger a new scan: `ref.invalidate(deviceScanProvider((type, time)))`.

## Active device: NotifierProvider with cleanup

```dart
final activeDeviceProvider =
    NotifierProvider<ActiveDeviceNotifier, Device?>(() => ActiveDeviceNotifier());

class ActiveDeviceNotifier extends Notifier<Device?> {
  @override
  Device? build() => null;

  Future<void> createDevice(String serial) async {
    final locator = ref.read(deviceLocatorProvider);
    if (locator == null) throw StateError('No locator');
    final device = await locator.createDevice(serial);
    state = device;
  }
}
```

StateProvider<Device?> cannot be used here — no dispose hook. NotifierProvider is required.

## Button state machine

`connectionStateStream` only tells you connected/disconnected. "Started" is a separate dimension:

```dart
// Manual started flag — set by action handlers on start()/stop()
final deviceIsStartedProvider = StateProvider<bool>((ref) => false);

enum DeviceUiState { idle, connected, started }

final deviceUiStateProvider = Provider<DeviceUiState>((ref) {
  final connAsync = ref.watch(deviceConnectionStateProvider);
  final isStarted = ref.watch(deviceIsStartedProvider);
  return connAsync.when(
    data: (conn) {
      if (conn == ConnectionState.disconnected) return DeviceUiState.idle;
      return isStarted ? DeviceUiState.started : DeviceUiState.connected;
    },
    loading: () => DeviceUiState.idle,
    error: (_, __) => DeviceUiState.idle,
  );
});
```

Button enabled/disabled derived from `deviceUiStateProvider`:
- Connect: enabled when `idle`
- Start: enabled when `connected`
- Stop: enabled when `started`
- Disconnect: enabled when `connected` or `started`

Action handlers set `deviceIsStartedProvider` explicitly after calling `device.start()`/`device.stop()`.

## Stream subscriptions lifecycle

Two patterns depending on frequency:

**Low-frequency streams** (connection state, mode, battery): use `StreamProvider` — auto-subscribes, auto-cancels.

**High-frequency streams** (EEG at 250 Hz): use `NotifierProvider` with a persistent subscription, NOT `StreamProvider`. `StreamProvider` re-subscribes on every rebuild → missed samples + GC pressure.

```dart
final eegBufferProvider =
    NotifierProvider<EEGBufferNotifier, EegData?>(() => EEGBufferNotifier());

class EEGBufferNotifier extends Notifier<EegData?> {
  StreamSubscription? _sub;

  @override
  EegData? build() {
    final device = ref.watch(activeDeviceProvider);
    final isStarted = ref.watch(deviceIsStartedProvider);
    if (device == null || !isStarted) return null;

    _sub?.cancel();
    _sub = device.eegStream.listen((data) => state = data);
    ref.onDispose(() => _sub?.cancel());
    return null;
  }
}
```

Subscribe only when `isStarted == true`. Cancel on stop or device removal.

## Async disposal order — critical gotcha

`ref.onDispose()` is **synchronous**. You cannot `await` inside it. The correct cleanup order:

```dart
await device.stop();
await device.disconnect();
device.dispose();
deviceLocator.dispose();
```

...cannot be expressed in `ref.onDispose`. Use a pre-disposal hook in the app's `State.dispose()`:

```dart
class _MyAppState extends State<MyApp> {
  late final ProviderContainer _container;

  @override
  void initState() {
    super.initState();
    _container = ProviderContainer();
  }

  @override
  void dispose() {
    _performCleanup().then((_) => _container.dispose());
    super.dispose();
  }

  Future<void> _performCleanup() async {
    final device = _container.read(activeDeviceProvider);
    if (device != null) {
      try {
        await device.stop();
        await device.disconnect();
        device.dispose();
      } catch (_) {}
    }
    _container.read(deviceLocatorProvider)?.dispose();
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
    parent: _container,
    child: MaterialApp.router(routerConfig: appRouter),
  );
}
```

## Critical gotcha: only one active device at a time

All EventChannels use shared static channel names. Flutter's EventChannel supports only one active `receiveBroadcastStream` per channel name at a time. Creating a second `Device` while the first is still streaming causes data loss on the first. Enforce single-device-at-a-time in `ActiveDeviceNotifier.createDevice()`: stop and dispose any previous device before storing the new one.
