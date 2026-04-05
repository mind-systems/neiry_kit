# Explore: Productivity + Cardio Tab — Shared State & Display Patterns

Research findings for the `Productivity + Cardio tab` example app milestone.

## Shared IndividualNfbData across tabs

`IndividualNfbData` is produced on the Calibration tab and needed on the Productivity+Cardio tab. Use a root-level `StateNotifierProvider`:

```dart
final nfbCalibrationProvider =
    StateNotifierProvider<NfbCalibrationNotifier, IndividualNfbData?>(
        NfbCalibrationNotifier.new);

class NfbCalibrationNotifier extends StateNotifier<IndividualNfbData?> {
  NfbCalibrationNotifier() : super(null);
  void set(IndividualNfbData data) => state = data;
  void clear() => state = null;
}
```

Calibration tab updates it when calibration completes:
```dart
ref.read(nfbCalibrationProvider.notifier).set(completedData);
```

Productivity/Cardio tab watches it to decide which factory to use:
```dart
final nfbData = ref.watch(nfbCalibrationProvider);
```

UI should show a notice when `nfbData == null`: "Go to Calibration tab first to enable NFB-calibrated mode."

## ProductivityMetrics.artifactsData

`artifactsData: Uint8List?` is an opaque blob with no documented structure. Display presence + size only:

```dart
Text(
  metrics.artifactsData != null
      ? 'Artifacts: ${metrics.artifactsData!.length} bytes'
      : 'Artifacts: none',
)
```

No hex dump — the blob is opaque to Dart consumers and serves no diagnostic purpose as raw bytes.

## ProductivityIndexes enum values

From the C SDK:

**relaxation → clCProductivity_RecommendationValue (0–5):**
- 0 = NoRecommendation
- 1 = Involvement
- 2 = Relaxation
- 3 = SlightFatigue
- 4 = SevereFatigue
- 5 = ChronicFatigue

**stress → clCProductivity_StressValue (0–2):**
- 0 = NoStress
- 1 = Anxiety
- 2 = Stress

Show enum names in UI, not raw integers:

```dart
const _recommendationLabels = [
  'No Recommendation', 'Involvement', 'Relaxation',
  'Slight Fatigue', 'Severe Fatigue', 'Chronic Fatigue',
];
const _stressLabels = ['No Stress', 'Anxiety', 'Stress'];

Text('Recommendation: ${_recommendationLabels[indexes.relaxation ?? 0]}')
Text('Stress: ${_stressLabels[indexes.stress ?? 0]}')
```

## PPG "last value" definition

`PpgData` arrives as a batch: `List<double> values`, `List<int> timestamps`. "Last value" = last sample in the most recent batch:

```dart
final last = ppgData.values.isNotEmpty ? ppgData.values.last : null;
final lastTs = ppgData.timestamps.isNotEmpty
    ? DateTime.fromMillisecondsSinceEpoch(ppgData.timestamps.last)
    : null;

Text(last != null ? 'PPG: ${last.toStringAsFixed(1)} @ ${lastTs!.toLocal()}' : 'PPG: —')
```

Show timestamp alongside the value to confirm real-time data flow (diagnostic purpose).

## Factory toggle UI

`Switch` disabled when `nfbCalibrationProvider` is null:

```dart
final nfbData = ref.watch(nfbCalibrationProvider);
final useCalibration = ref.watch(useCalibrationToggleProvider);

Switch(
  value: useCalibration && nfbData != null,
  onChanged: nfbData == null ? null : (val) {
    ref.read(useCalibrationToggleProvider.notifier).state = val;
    ref.invalidate(productivityClassifierProvider);  // recreate
  },
)
```

`StateProvider<bool>` for the toggle. Invalidating the classifier provider triggers recreation.

## Classifier recreation: safe to create second instance

Classifiers have no `Destroy()` — lifecycle is SDK-managed per handle. Creating a new instance while the old one exists is safe. Pattern: dispose old → create new:

```dart
class ProductivityClassifierNotifier extends Notifier<ProductivityClassifier?> {
  @override
  ProductivityClassifier? build() {
    final device = ref.watch(activeDeviceProvider);
    final isStarted = ref.watch(deviceIsStartedProvider);
    if (device == null || !isStarted) return null;

    final nfbData = ref.watch(nfbCalibrationProvider);
    final useCalibration = ref.watch(useCalibrationToggleProvider);

    // Provider rebuilds when any dependency changes — old instance GC'd automatically
    // since classifiers have no Destroy() and SDK manages handles
    return (useCalibration && nfbData != null)
        ? ProductivityClassifier.withCalibration(device, nfbData)
        : ProductivityClassifier(device);
  }
}
```

Note: since there's no explicit destroy, allow Riverpod to manage the rebuild cycle naturally. Old instances will be GC'd; SDK handles are reference-counted internally.

## Full dependency map for Productivity+Cardio tab

```
nfbCalibrationProvider (StateNotifierProvider<IndividualNfbData?>)
    ↑ set by CalibrationTab when calibration completes

useCalibrationToggleProvider (StateProvider<bool>)
    ↑ set by Switch in UI

activeDeviceProvider + deviceIsStartedProvider
    ↑ set by Device tab

productivityClassifierProvider (NotifierProvider)
    ← watches: activeDeviceProvider, deviceIsStartedProvider,
                nfbCalibrationProvider, useCalibrationToggleProvider
    → emits: ProductivityClassifier?

cardioClassifierProvider (NotifierProvider)
    ← watches: same + useCalibrationToggleProvider
    → emits: CardioClassifier?
```
