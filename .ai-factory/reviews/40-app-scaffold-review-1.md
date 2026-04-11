## Code Review: 40-app-scaffold

**Files reviewed:** 8 changed (4 new screens, 1 new provider, 1 new router, 1 modified main.dart, 1 modified pubspec.yaml, 1 modified widget_test.dart, 1 modified pubspec.lock)
**Risk Level:** Low

### Reviewed Files

| File | Verdict |
|---|---|
| `example/pubspec.yaml` | OK |
| `example/lib/main.dart` | OK |
| `example/lib/router.dart` | OK |
| `example/lib/providers/device_locator_provider.dart` | OK |
| `example/lib/screens/device_screen.dart` | OK |
| `example/lib/screens/streams_screen.dart` | OK |
| `example/lib/screens/classifiers_screen.dart` | OK |
| `example/lib/screens/calibration_screen.dart` | OK |
| `example/test/widget_test.dart` | OK |

### Critical Issues

None.

### Observations

1. **Riverpod version constraint: `^3.2.0` vs `^3.3.0`** — The ROADMAP milestone specifies `riverpod: ^3.3.0` / `flutter_riverpod: ^3.3.0`, but pubspec.yaml uses `^3.2.0`. This was an intentional change (presumably because 3.3.0 is not yet published on pub.dev). The constraint `^3.2.0` allows `>=3.2.0 <4.0.0`, so it will pick up 3.3.0 when available. Non-blocking.

2. **Async dispose in synchronous callback** — `ref.onDispose(() => locator.dispose())` discards the `Future<void>` returned by `DeviceLocator.dispose()`. This is a known Riverpod limitation (documented in `notes/13-explore-example-device-providers.md`): `ref.onDispose` is synchronous and cannot await. Acceptable for app-shutdown cleanup — the native destroy call fires and will complete, but the Dart side doesn't wait for it. No fix needed.

3. **Provider created but not yet consumed** — `device_locator_provider.dart` is not imported by any screen or by `main.dart`. Expected: screens are empty stubs in this milestone; the Device tab milestone will be the first consumer. No action needed.

### Verification

- **`dart analyze lib/`**: 0 issues.
- **StatefulShellRoute.indexedStack** correctly used over `ShellRoute` — each branch gets its own `Navigator` so tab widgets stay mounted during switches (essential for live EEG streams in later milestones).
- **NavigationBar** (Material 3) used, not `BottomNavigationBar` (Material 2). Correct per plan.
- **Branch order matches destination order** in `NavigationBar` (Device=0, Streams=1, Classifiers=2, Calibration=3). Tab index consistency verified.
- **`DeviceLocatorNotifier.build()`** uses closure-captured `locator` reference in `ref.onDispose` (not `state`), which is safer — if `state` were ever reassigned, the captured reference still disposes the correct instance.
- **`DeviceLocator()` factory constructor** returns singleton — safe to call from `Notifier.build()` even on re-initialization after invalidation: the old `onDispose` fires first (disposing and nulling `_instance`), then the new `build()` creates a fresh instance.
- **Nested Scaffold pattern** (outer in `_RootScaffold` for nav bar, inner in each screen for app bar) is the standard shell route layout. No visual issues.
- **GoRoute builders** use Dart 3 wildcard `_` parameters — correct syntax, no name collisions.
- **Import paths**: provider file imports from `package:neiry_kit/neiry_kit.dart` (barrel export), never from `lib/src/`. Matches ARCHITECTURE.md dependency rules.
- **widget_test.dart** replaced with placeholder `void main() {}` — old test tested the removed spike screen. Appropriate for "Testing: no" milestone setting.

REVIEW_PASS
