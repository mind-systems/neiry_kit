# Explore: Example App Navigation & Scaffold

Research findings for the `app scaffold` example app milestone.

## Navigation: StatefulShellRoute.indexedStack

Use `StatefulShellRoute.indexedStack` — NOT plain `ShellRoute`. Each branch gets its own `Navigator` stack. The `IndexedStack` keeps all tab widgets mounted but invisible, so live EEG streams survive tab switches without restarting.

`ShellRoute` shares a single Navigator → destroys and recreates on tab switch → kills stream subscriptions. Wrong for this app.

## Tab structure: 4 tabs

ROADMAP says 4 tabs, later milestones describe 5 UI sections. Resolution: keep 4 tabs, nest classifier screens inside tab 3:

```
Tab 1: /device        → device discovery, connect, lifecycle buttons
Tab 2: /streams       → live EEG, PSD, artifacts, resistance, battery
Tab 3: /classifiers   → NFB + Physio + Emotions (sub-navigation inside tab)
Tab 4: /calibration   → NFB calibration (full + quick) + import/export
```

Productivity + Cardio go inside /classifiers as a sub-page (PageView or nested GoRoute).

## Package versions

```yaml
dependencies:
  riverpod: ^3.3.0
  flutter_riverpod: ^3.3.0
  go_router: ^14.0.0
  cupertino_icons: ^1.0.8
```

go_router 14.x has a breaking change from 13.x: `onExit` callback signature changed. Use 14.x directly.

## Router skeleton

```dart
final GoRouter appRouter = GoRouter(
  initialLocation: '/device',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          _RootScaffold(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/device', builder: (_, __) => const DeviceScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/streams', builder: (_, __) => const StreamsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/classifiers', builder: (_, __) => const ClassifiersScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/calibration', builder: (_, __) => const CalibrationScreen()),
        ]),
      ],
    ),
  ],
);

class _RootScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const _RootScaffold({required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: navigationShell.goBranch,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.devices), label: 'Device'),
          NavigationDestination(icon: Icon(Icons.signal_cellular_alt), label: 'Streams'),
          NavigationDestination(icon: Icon(Icons.ssid_chart), label: 'Classifiers'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Calibration'),
        ],
      ),
    );
  }
}
```

Note: use `NavigationBar` (Material 3) not `BottomNavigationBar` (Material 2).

## DeviceLocator provider

`DeviceLocator` is a singleton — create once, keep alive, dispose on app close.

```dart
final deviceLocatorProvider = Provider<DeviceLocator>((ref) {
  final locator = DeviceLocator();
  ref.onDispose(locator.dispose);
  return locator;
});
```

`Provider` (not `StateNotifierProvider`) — it never changes, just provides. `ref.onDispose` handles cleanup.

`ProviderScope` wraps `runApp`:

```dart
void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(routerConfig: appRouter);
  }
}
```

## Critical gotcha: EEG stream in StreamBuilder

If `device.eegStream` is subscribed inside a `StreamBuilder` widget on the Streams tab, switching tabs cancels and restarts the subscription. Move all stream subscriptions to `StreamProvider` at the provider layer — providers survive tab switches.

```dart
// WRONG — subscription dies on tab switch
StreamBuilder<EegData>(stream: device.eegStream, ...)

// CORRECT — provider survives, widget just reads latest value
final eegProvider = StreamProvider<EegData>((ref) {
  final device = ref.watch(deviceProvider);
  if (device == null) return const Stream.empty();
  return device.eegStream;
});
```
