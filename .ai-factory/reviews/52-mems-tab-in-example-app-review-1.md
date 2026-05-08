## Code Review: MEMS tab in example app

**Plan:** `.ai-factory/plans/52-mems-tab-in-example-app.md`
**Changed files:**
- `example/lib/providers/mems_classifier_provider.dart` (new)
- `example/lib/screens/mems_screen.dart` (new)
- `example/lib/router.dart` (modified)

### Checklist

**Provider layer (`mems_classifier_provider.dart`)**

- [x] `MEMSClassifierNotifier` follows the established `CardioClassifierNotifier` pattern exactly — watches `activeDeviceProvider`, `deviceIsStartedProvider`, `nfbCalibrationProvider`, and a dedicated `useMemsCalibrationToggleProvider`; returns `null` when device not active/started; creates via correct factory paths; `ref.onDispose` captures local classifier instance.
- [x] `useMemsCalibrationToggleProvider` is a separate `StateProvider<bool>` (not shared with Productivity/Cardio) — correct, MEMS calibration toggle should be independent.
- [x] `memsProvider` as `StreamProvider<List<MemsSample>>` with `throttleTime(100ms)` from rxdart — matches `eegProvider` pattern in `stream_providers.dart`.
- [x] Returns `Stream.empty()` when classifier is null — correct.
- [x] Imports: `flutter_riverpod/legacy.dart` for `StateProvider` (Riverpod 3.x), `rxdart`, `neiry_kit` — all correct.

**Screen layer (`mems_screen.dart`)**

- [x] `MemsScreen extends ConsumerWidget` — correct.
- [x] `SwitchListTile` disabled when `nfbData == null` via `onChanged: null` — matches `productivity_cardio_screen.dart` pattern exactly.
- [x] `SwitchListTile` value is `useCalibration && nfbData != null` — correct, shows ON only when both conditions are met.
- [x] Subtitle logic for all three states (no calibration / calibration enabled / calibration available but off) — matches Productivity screen.
- [x] Empty-list guard: `samples.isEmpty` check at line 54 before calling `samples.last` — correctly prevents `StateError` on empty list.
- [x] Field access: `sample.accelerometer.x/y/z` and `sample.gyroscope.x/y/z` — matches `MemsSample` model which uses Dart records `({double x, double y, double z})`.
- [x] `_AxisRow` helper: private, local to file, consistent with the pattern of other screens using private helper widgets.
- [x] `toStringAsFixed(4)` — reasonable precision for MEMS sensor values.

**Router (`router.dart`)**

- [x] MEMS branch inserted at index 4 (between Productivity at 3 and Calibration at 5).
- [x] `NavigationDestination` with `Icons.sensors` and label `'MEMS'` at matching position index 4.
- [x] Branch count (6) matches destination count (6) — no index mismatch.
- [x] Calibration correctly remains the last tab.

**Barrel export**

- [x] `lib/neiry_kit.dart` already exports both `mems_classifier.dart` (line 3) and `mems_data.dart` (line 20) — no changes needed.

### Runtime correctness

- **Classifier creation timing**: `MEMSClassifier` fires the native `create` call asynchronously. `memsProvider` accesses `memsStream` synchronously. This is safe — the `EventChannel` listener is independent and starts emitting once the native side is ready. This matches the pattern of all other classifier providers.
- **Dispose lifecycle**: `ref.onDispose` calls `classifier.dispose()` synchronously (the returned Future is not awaited). This is safe — the SDK manages concurrent handles, and creating a new classifier before the old one finishes disposal is explicitly OK per the roadmap ("classifiers have no Destroy, creating a new instance while old exists is OK").
- **Provider invalidation chain**: Toggling `useMemsCalibrationToggleProvider` invalidates `memsClassifierProvider` (which watches it), which invalidates `memsProvider` (which watches the classifier). The old classifier is disposed, a new one is created with the correct factory path. This is correct.

### Issues

No bugs, security issues, or correctness problems found.

REVIEW_PASS
