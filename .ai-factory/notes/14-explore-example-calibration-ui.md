# Explore: NFB Calibration Tab — UI & Provider Design

Research findings for the `NFB tab + calibration` example app milestone.

## Per-stage elapsed timer

`CalibrationEvent` stream emits only on stage completion — no ticks. The UI timer is purely client-side.

Pattern: `Timer.periodic` owned by a `StateNotifier`, reset on each stage start:

```dart
class CalibrationTimerNotifier extends StateNotifier<({int elapsed, CalibrationStage? stage})> {
  Timer? _timer;

  CalibrationTimerNotifier() : super((elapsed: 0, stage: null));

  void startStage(CalibrationStage stage) {
    _timer?.cancel();
    state = (elapsed: 0, stage: stage);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = (elapsed: state.elapsed + 1, stage: state.stage);
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    state = (elapsed: 0, stage: null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
```

**Critical:** cancel `_timer` in `dispose()` — otherwise the Timer fires after provider is gone.

## CalibrationUiState — sealed class

Centralizes instruction text and stage label:

```dart
sealed class CalibrationUiState {}

final class CalibrationIdle extends CalibrationUiState {
  String get instruction => 'Press Start to begin calibration';
}

final class CalibrationStageActive extends CalibrationUiState {
  final CalibrationStage stage;
  final int elapsedSeconds;
  CalibrationStageActive(this.stage, this.elapsedSeconds);

  String get stageLabel => 'Stage ${stage.index + 1} / 4';

  String get instruction => switch (stage) {
    CalibrationStage.stage1 || CalibrationStage.stage3 => 'Close your eyes and relax',
    CalibrationStage.stage2 || CalibrationStage.stage4 => 'Open your eyes, look straight ahead',
  };
}

final class CalibrationDone extends CalibrationUiState {
  final IndividualNfbData data;
  CalibrationDone(this.data);
  bool get isValid => data.isValid;
}

final class CalibrationError extends CalibrationUiState {
  final String message;
  CalibrationError(this.message);
}
```

## Calibration provider: AsyncNotifier

Handles full calibration (stream), quick (future), and import/export in one place:

```dart
class CalibrationNotifier extends AsyncNotifier<IndividualNfbData?> {
  StreamSubscription<CalibrationEvent>? _sub;

  @override
  Future<IndividualNfbData?> build() async =>
      await NfbCalibrator.getCalibrationData();

  Future<void> startFull() async {
    await WakelockPlus.enable();
    state = const AsyncValue.loading();
    final completer = Completer<IndividualNfbData>();
    final timer = ref.read(calibrationTimerProvider.notifier);

    // Start timer for stage 1 before first event arrives
    timer.startStage(CalibrationStage.stage1);

    _sub = NfbCalibrator.calibrateIndividual().listen(
      (event) => switch (event) {
        CalibrationStageFinished(:final stage) => () {
            // Advance to next stage
            final next = CalibrationStage.values[stage.index + 1];
            if (stage.index < 3) timer.startStage(next);
          }(),
        CalibrationCompleted(:final data) => () {
            timer.stop();
            if (!completer.isCompleted) completer.complete(data);
          }(),
      },
      onError: (e) {
        timer.stop();
        if (!completer.isCompleted) completer.completeError(e);
      },
    );

    state = await AsyncValue.guard(() async {
      final data = await completer.future;
      await WakelockPlus.disable();
      return data;
    });
  }

  Future<void> startQuick() async {
    await WakelockPlus.enable();
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final data = await NfbCalibrator.calibrateIndividualQuick();
      await WakelockPlus.disable();
      return data;
    });
  }

  Future<void> abort() async {
    _sub?.cancel();
    _sub = null;
    ref.read(calibrationTimerProvider.notifier).stop();
    await WakelockPlus.disable();
    state = AsyncValue.data(await NfbCalibrator.getCalibrationData());
  }

  Future<void> importFromFile() async {
    final data = await CalibrationFileManager.importFromFile();
    if (data != null) {
      await NfbCalibrator.importCalibrationData(data);
      state = AsyncValue.data(data);
    }
  }

  Future<void> exportToFile() async {
    final data = state.value;
    if (data != null) await CalibrationFileManager.exportToFile(data);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
```

## File import/export

Packages needed:
```yaml
file_picker: ^8.0.0
path_provider: ^2.1.5
wakelock_plus: ^1.2.0
```

```dart
class CalibrationFileManager {
  static Future<File?> exportToFile(IndividualNfbData data) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/calibration_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(jsonEncode(data.toMap()));
    return file;
  }

  static Future<IndividualNfbData?> importFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null) return null;
    final json = await File(result.files.single.path!).readAsString();
    return IndividualNfbData.fromMap(jsonDecode(json) as Map<String, dynamic>);
  }
}
```

## NfbClassifier conditional provider

`NfbClassifier` requires device in `started` state:

```dart
final nfbClassifierProvider = Provider<NfbClassifier?>((ref) {
  final device = ref.watch(activeDeviceProvider);
  final isStarted = ref.watch(deviceIsStartedProvider);
  if (device == null || !isStarted) return null;

  final calibration = ref.watch(calibrationProvider).value;
  return NfbClassifier(device, calibration: calibration);
});
```

Returns `null` when device stops — widget shows "Waiting for device..." via `.when`.

## Screen sleep prevention

```dart
// Before calibration starts:
await WakelockPlus.enable();
// In finally block or abort:
await WakelockPlus.disable();
```

`wakelock_plus` works on both iOS (sets `isIdleTimerDisabled`) and Android (acquires wake lock) from pure Dart.

## Edge cases

**Abort mid-calibration:** cancel `_sub`, call `abort()`, disable wakelock, restore `AsyncValue.data` from `getCalibrationData()`.

**Device disconnect during calibration:** native EventChannel errors → stream `onError` → completer.completeError → `AsyncValue.error` in provider. UI shows error; timer and wakelock must be cleaned up in the error path.

**Overlapping requests:** SDK's `calibrateIndividual()` / `calibrateIndividualQuick()` cancels any active calibration on the native side automatically. No extra guard needed in Dart; just call the new method.

**Stage label on first event:** Timer starts for stage 1 before the first `CalibrationStageFinished` fires — start the timer manually at `startFull()` call time, not when the first event arrives.
