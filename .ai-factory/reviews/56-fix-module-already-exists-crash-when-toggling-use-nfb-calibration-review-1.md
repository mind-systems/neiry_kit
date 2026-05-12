# Code Review: 56-fix-module-already-exists-crash-when-toggling-use-nfb-calibration

**Plan:** `.ai-factory/plans/56-fix-module-already-exists-crash-when-toggling-use-nfb-calibration.md`
**Files reviewed in full:**
- `android/src/main/cpp/jni_productivity.cpp`
- `android/src/main/cpp/jni_device_locator.cpp` (for `throw_sdk_error` semantics)
- `android/src/main/cpp/CMakeLists.txt`
- `android/build.gradle.kts`
- `android/src/main/kotlin/com/neiry/neiry_kit/ProductivityBridge.kt` (consumer of the JNI symbol)
- `lib/src/api/classifiers/productivity_classifier.dart`
- `example/lib/providers/productivity_classifier_provider.dart`
- `example/lib/providers/cardio_classifier_provider.dart`
- `example/lib/providers/mems_classifier_provider.dart`
- `example/lib/providers/device_state_providers.dart`
- `example/lib/providers/nfb_calibration_provider.dart`
- `example/lib/screens/productivity_cardio_screen.dart`
- `example/lib/screens/mems_screen.dart`
- `example/analysis_options.yaml`

**Risk level:** 🟢 Low — the diagnosis, strategy, and implementation are correct and match the plan.

## Summary of changes

1. UX gate (`productivity_cardio_screen.dart`, `mems_screen.dart`): the `SwitchListTile` `onChanged` is set to `null` when `uiState == DeviceUiState.started`, with a "Stop streaming to change this setting" subtitle. Correct.
2. Snapshot calibration (`productivity_classifier_provider.dart`, `cardio_classifier_provider.dart`, `mems_classifier_provider.dart`): `ref.watch(nfbCalibrationProvider)` → `ref.read(nfbCalibrationProvider)`. Matches `nfb_classifier_provider.dart:22`. Correct.
3. JNI stub (`jni_productivity.cpp`): `nativeCreateProductivityWithIndividualData` now throws `9|clCProductivity_CreateWithIndividualData is not exported by the Android Capsule AAR` via `throw_sdk_error`. Parameters marked `[[maybe_unused]]`, single-line `TODO` retained. Correct.
4. Dart-side guard (`productivity_classifier.dart`): `Platform.isAndroid` check in `withCalibration` throws `UnsupportedError` before the bridge call. Correct.
5. Defensive fallback in `ProductivityClassifierNotifier.build()`: catches `UnsupportedError` and falls back to `ProductivityClassifier(device)`. Correct.

## Findings

### 1. `[[maybe_unused]]` requires C++17, and the build does not pin a C++ standard — minor portability risk

`android/src/main/cpp/jni_productivity.cpp:74-84` uses `[[maybe_unused]]` on each JNI parameter. This is a C++17 attribute (P0212R1). The project's CMake config does **not** set `CMAKE_CXX_STANDARD`, and `android/build.gradle.kts` does not pass `-std=c++17` via `cppFlags` (it explicitly sets `cppFlags += ""`).

In practice this compiles today: AGP 8.x + NDK r25+ ships Clang, which accepts `[[maybe_unused]]` even in C++14 mode as a vendor extension, and the NDK toolchain's default is `-std=gnu++17` since r19. So no current breakage. But the file's correctness now depends on an unpinned default. Either:

- Add `set(CMAKE_CXX_STANDARD 17)` (and `CMAKE_CXX_STANDARD_REQUIRED ON`) to `CMakeLists.txt` to make the requirement explicit, or
- Replace `[[maybe_unused]]` with the GCC/Clang attribute `__attribute__((unused))` (universally available since C++98), or
- Drop the attributes and add `(void)ts; (void)failReason; …` lines at the top of the function body.

The plan accepted `[[maybe_unused]]` so this is acknowledged as a tradeoff, but it deserves a one-line note if the project is ever cross-compiled with a stricter toolchain.

### 2. Silent fallback on Android Productivity has no user-visible signal — accepted, but worth re-confirming

`productivity_classifier_provider.dart:48-58` swallows `UnsupportedError` and falls back to the plain factory; the only signal is a single `debugPrint` line on classifier creation. On Android, when the user has nfbData and toggles "Use NFB Calibration" on, Cardio receives calibration but Productivity silently does not. The user sees the toggle on with subtitle "Using individual NFB calibration" — which is half-true.

The plan's acceptance criterion explicitly chose this design ("the `ProductivityClassifierNotifier` catches the `UnsupportedError` and falls back to the plain `ProductivityClassifier(device)` so neither Productivity nor any sibling classifier dies. The shared toggle remains visible and enabled because it still gates the Cardio classifier"). The plan-review v2 issue #3 surfaced the same concern and the resolution was documented. So this is a deliberate UX tradeoff, not a bug — but the implementer of the consumer app (`mind_mobile`) needs to know that on Android the Productivity side will be feature-mismatched with the toggle state. Worth flagging in the roadmap follow-up.

### 3. `Cardio` and `MEMS` calibrated factories still rely on the UX gate alone — defense-in-depth gap

Unlike `ProductivityClassifier.withCalibration`, neither `CardioClassifier.withCalibration` nor `MEMSClassifier.withCalibration` has a `device.isStarted`-aware guard against being called against a streaming device. The plan's correctness argument relies on "the example app's `SwitchListTile` is locked while streaming." If `mind_mobile` or any future consumer of the plugin wires the toggle without the UX gate, they will re-introduce the same SIGABRT on Android — and the plugin will not stop them.

This isn't a regression introduced by this PR (the gap pre-existed), and the plan scopes itself to the example app. But the fix codifies the SDK invariant "the classifier is owned by Device for the duration of streaming" in code only on the Android-Productivity path. Consider adding a docstring on the three `*.withCalibration` factories (and the plain factories) that names the constraint, so consumers know the toggle-while-streaming pattern is unsafe before they trip on it. Non-blocking.

### 4. `parseSdkError` consumer side will see code `9`, not the `255` previously documented

`ProductivityBridge.kt:91-92` catches the JNI's `RuntimeException` and runs `parseSdkError(e.message ?: "255|Unknown error")`. The new JNI message is `9|clCProductivity_CreateWithIndividualData is not exported by the Android Capsule AAR` (because `clCError_ModuleIsNotSupported == 9`). The Kotlin fallback default "255" only fires if `e.message == null`, which it won't here. So the consumer sees a `FlutterError` with code `"9"` (or whatever `parseSdkError` maps `9` to). I did not read `parseSdkError`; verify it has a non-default mapping for code `9` if any callers branch on `FlutterError.code`. Non-blocking — the Dart-side `Platform.isAndroid` check fires first, so this path is only reachable from direct Kotlin callers.

### 5. Kotlin bridge still marshals 10 calibration fields the JNI now ignores — dead computation, accepted

`ProductivityBridge.kt:64-94` reads `ts`, `failReason`, `individualFrequency`, … from `calibrationData` and passes them to a JNI function that ignores all of them. This is a deliberate trade-off in the plan ("Keep the JNI signature unchanged so the Kotlin bridge does not need re-binding") and is the right call — re-binding the JNI signature would force a Kotlin-side change that breaks the symmetric Productivity contract. The wasted work is one `Map.get` and ten `(Number).toFloat()` calls, executed at most once per device-start, on a path that the Dart guard now prevents in production. No action needed; documenting this so a future cleanup pass does not assume the marshaling is load-bearing.

### 6. Subtitle nesting is now three levels deep and increasingly hard to read

`productivity_cardio_screen.dart:66-81` and `mems_screen.dart:29-44` use a triply-nested ternary for the subtitle. It's correct but at the readability edge. A small extracted helper would be cleaner:

```dart
Widget? _subtitleFor(bool hasNfbData, bool canEditToggle, bool useCalibration) {
  if (!hasNfbData) return const Text('Run calibration first to enable', style: TextStyle(color: Colors.grey));
  if (!canEditToggle) return const Text('Stop streaming to change this setting', style: TextStyle(color: Colors.grey));
  if (useCalibration) return const Text('Using individual NFB calibration', style: TextStyle(color: Colors.grey));
  return null;
}
```

The same helper would dedupe the identical pattern across both screens (currently copy-pasted). Style nit; non-blocking.

### 7. `productivity_classifier_provider.dart` is now the only file that imports `package:flutter/foundation.dart` for `debugPrint`

`example/lib/providers/productivity_classifier_provider.dart:3` adds `import 'package:flutter/foundation.dart' show debugPrint;`. Correct (the file doesn't transitively pick up `flutter/material.dart`). The plan flagged this and the implementation matches. No issue.

### 8. `mems_classifier_provider.dart` doc paragraph references "**not** started" without the toggle-name caveat — minor inconsistency

Both `cardio_classifier_provider.dart` and `mems_classifier_provider.dart` got the same generic paragraph, but on MEMS the relevant toggle is `useMemsCalibrationToggleProvider`, not the shared `useCalibrationToggleProvider`. The doc reads correctly in context, but a reader who jumps in cold may wonder which toggle "the example screens enforce." A one-word change (`the **MEMS** example screen enforces this`) would tighten it. Style nit; non-blocking.

### 9. The `ref.read(nfbCalibrationProvider)` pattern intentionally diverges from the standard Riverpod recommendation

`flutter_lints` (the only enabled lint set per `example/analysis_options.yaml`) does not flag `ref.read` inside `Notifier.build()`. The pattern is internally consistent with the existing `nfb_classifier_provider.dart:22`. Riverpod's own docs allow this when the snapshot semantics are deliberate, which they are here. Verified — no action needed.

## Runtime-failure analysis

I went through the failure modes the plan was designed to cover:

| Scenario | Behavior after fix | OK? |
|---|---|---|
| Toggle flipped while `isStarted == false`, then `Start` | Notifier builds once with the new toggle/calibration values; one `_Create` per device-start. | ✓ |
| Toggle flipped while `isStarted == true` | `onChanged: null` — flip is impossible from UI. | ✓ |
| `nfbCalibrationProvider` mutated by `CalibrationNotifier.importFromFile` while `isStarted == true` | Three notifiers `ref.read` the value, so the mutation does not trigger a rebuild. Existing classifiers keep running. New calibration takes effect on next `Stop`→`Start`. | ✓ |
| `nfbCalibrationProvider` mutated by `startQuick` / `startFull` while `isStarted == true` | Same as above. | ✓ |
| Android: `ProductivityClassifier.withCalibration` called | Throws `UnsupportedError` synchronously. Provider catches it, falls back to plain factory. JNI's `clCError_ModuleIsNotSupported` path is unreachable from Dart but is the right defense if reached from Kotlin. | ✓ |
| Stop → Start cycle | Notifier returns `null` on stop (disposing the old classifier), rebuilds fresh on start with the latest toggle and calibration snapshot. | ✓ |
| `useCalibration` toggle programmatically mutated mid-stream | No code path in the repo mutates it outside the two `SwitchListTile.onChanged` callbacks, both of which are UX-locked. The notifiers still `ref.watch` the toggle, so a hypothetical mutation would rebuild and SIGABRT on Android. Defense-in-depth gap noted in finding #3 but not exercised by current code. | ✓ for now |

No SIGABRT path I could find remains live after this patch under the current callers.

## Build correctness

- `clCError error{};` (value-initialization) compiles in C++11+. ✓
- `snprintf` is `#include <cstdio>` — already included at the top of the file. ✓
- `throw_sdk_error` is declared via `extern void throw_sdk_error(...)` at line 25. ✓
- `clCError_ModuleIsNotSupported` is defined in `CError.h:18`. ✓
- `dart:io` `Platform` is available on Flutter mobile targets. ✓
- `debugPrint` import is correct. ✓
- No new method-channel surface added, so no Kotlin/Swift re-binding needed. ✓

## Verdict

The fix correctly closes both SIGABRT paths (toggle-driven and calibration-import-driven) and replaces the Android Productivity silent fallback with an honest `UnsupportedError`. All findings above are either documentation/style nits or pre-existing gaps unrelated to this task. None block merge.

The single item worth a follow-up commit (or a roadmap entry) is finding #1: pin the C++ standard in `CMakeLists.txt` so the use of `[[maybe_unused]]` is not relying on a toolchain default. Everything else is non-blocking.

REVIEW_PASS
