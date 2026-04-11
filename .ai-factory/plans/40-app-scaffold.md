# Plan: App Scaffold

## Context
Set up the example app with Riverpod state management, GoRouter navigation using `StatefulShellRoute.indexedStack` (so live streams survive tab switches), a Material 3 bottom nav bar with 4 tabs, a `deviceLocatorProvider`, and empty screen stubs for each tab.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Dependencies

- [x] **Task 1: Add packages to example/pubspec.yaml**
  Files: `example/pubspec.yaml`
  Add to the `dependencies:` section (below existing `cupertino_icons`):
  ```yaml
  riverpod: ^3.3.0
  flutter_riverpod: ^3.3.0
  go_router: ^14.0.0
  rxdart: ^0.27.0
  file_picker: ^8.0.0
  path_provider: ^2.1.5
  wakelock_plus: ^1.2.0
  ```
  Keep existing deps (`flutter` SDK, `neiry_kit` path, `cupertino_icons`). Run `flutter pub get` inside `example/` to resolve.

### Phase 2: Screen stubs and routing

- [x] **Task 2: Create 4 empty screen stubs** (depends on Task 1)
  Files: `example/lib/screens/device_screen.dart`, `example/lib/screens/streams_screen.dart`, `example/lib/screens/classifiers_screen.dart`, `example/lib/screens/calibration_screen.dart`
  Create `example/lib/screens/` directory. Each file exports a single `StatelessWidget` returning a `Scaffold` with an `AppBar` whose title matches the tab name ("Device", "Streams", "Classifiers", "Calibration") and a `Center(child: Text('...'))` body placeholder. Import only `package:flutter/material.dart`. All widgets are `const`-constructable.

- [x] **Task 3: Create GoRouter configuration** (depends on Task 2)
  Files: `example/lib/router.dart`
  Create `example/lib/router.dart` exporting a top-level `final GoRouter appRouter`. Use `StatefulShellRoute.indexedStack` (NOT `ShellRoute`) so each branch gets its own `Navigator` and tab widgets stay mounted (live EEG streams survive tab switches). Initial location: `/device`. Four branches:
  - `/device` -> `DeviceScreen`
  - `/streams` -> `StreamsScreen`
  - `/classifiers` -> `ClassifiersScreen`
  - `/calibration` -> `CalibrationScreen`

  The `builder` of the `StatefulShellRoute` returns a private `_RootScaffold` widget (defined in the same file) that wraps `navigationShell` in a `Scaffold` with a `NavigationBar` (Material 3, NOT `BottomNavigationBar`) as `bottomNavigationBar`. Four `NavigationDestination`s:
  - `Icons.devices` / "Device"
  - `Icons.signal_cellular_alt` / "Streams"
  - `Icons.ssid_chart` / "Classifiers"
  - `Icons.tune` / "Calibration"

  `selectedIndex: navigationShell.currentIndex`, `onDestinationSelected: navigationShell.goBranch`. Follow the exact skeleton from `.ai-factory/notes/12-explore-example-navigation.md`.

### Phase 3: State management and entry point

- [x] **Task 4: Create deviceLocatorProvider** (depends on Task 1)
  Files: `example/lib/providers/device_locator_provider.dart`
  Create `example/lib/providers/` directory. Define `deviceLocatorProvider` as a `NotifierProvider`. The `Notifier` subclass creates a `DeviceLocator` instance in its `build()` method and registers `ref.onDispose(() => state.dispose())` to ensure the native locator is destroyed when the provider is disposed. Import `DeviceLocator` from `package:neiry_kit/neiry_kit.dart` (barrel export, never import from `lib/src/` directly per ARCHITECTURE.md dependency rules).

- [x] **Task 5: Rewrite main.dart** (depends on Tasks 3, 4)
  Files: `example/lib/main.dart`
  Replace the entire spike screen with the app scaffold. `main()` calls `runApp(const ProviderScope(child: NeiryExampleApp()))`. `NeiryExampleApp` is a `StatelessWidget` returning `MaterialApp.router(routerConfig: appRouter)`. Remove all old imports (`flutter/services.dart`, `MethodChannel` usage). Import `flutter_riverpod` for `ProviderScope`, import `router.dart` for `appRouter`. The app should compile and show 4 tabs with empty scaffolds.

## Commit Plan
- **Commit 1** (after tasks 1-5): "Add Riverpod, GoRouter, and tabbed navigation scaffold to example app"
