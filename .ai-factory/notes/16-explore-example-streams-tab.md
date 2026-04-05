# Explore: Streams Tab — EEG Throttle & Resistance Accumulation

Research findings for the `Streams tab` example app milestone.

## EEG throttle: rxdart throttleTime

At 250 Hz, without throttling the UI freezes immediately. Use `rxdart`'s `throttleTime`:

```yaml
# pubspec.yaml
dependencies:
  rxdart: ^0.27.0
```

```dart
final eegProvider = StreamProvider<EegData>((ref) {
  final device = ref.watch(activeDeviceProvider);
  if (device == null) return const Stream.empty();
  return device.eegStream.throttleTime(const Duration(milliseconds: 100));
});
```

`throttleTime` emits the first value immediately, then ignores subsequent values for the duration. No sample is ever "missed" from a display perspective — the latest value is always what the user sees.

**Do NOT** use `debounceTime` — that waits for silence and would never emit from a continuous 250 Hz stream.

## Recommended throttle rates per stream

| Stream | Throttle | Display rate | Rationale |
|---|---|---|---|
| EEG (250 Hz) | 100 ms | 10 Hz | Human perception limit for diagnostic text |
| PSD | 500 ms | 2 Hz | Band powers are smooth; 2 Hz is visually responsive |
| Resistance | none | as-is | Per-channel events are infrequent; accumulate all |
| Battery | 1000 ms | 1 Hz | Integer % changes rarely |
| Artifacts | none | as-is | Boolean flags — immediate feedback important |
| Connection/mode | none | as-is | State change events, not high-frequency |

## Resistance accumulation: NotifierProvider

`resistanceStream` fires per-channel independently, NOT as a batch. To display a channel→kΩ table, accumulate latest value per channel in a `NotifierProvider`:

```dart
final resistanceMapProvider =
    NotifierProvider<ResistanceMapNotifier, Map<String, double>>(
        ResistanceMapNotifier.new);

class ResistanceMapNotifier extends Notifier<Map<String, double>> {
  StreamSubscription? _sub;

  @override
  Map<String, double> build() {
    final device = ref.watch(activeDeviceProvider);
    final isStarted = ref.watch(deviceIsStartedProvider);

    _sub?.cancel();
    if (device == null || !isStarted) return {};

    _sub = device.resistanceStream.listen((data) {
      // ResistanceData: one channel per event
      state = {...state, data.channelName: data.kOhm};
    });
    ref.onDispose(() => _sub?.cancel());
    return {};
  }
}
```

**Why NotifierProvider and not StreamProvider:** `StreamProvider` only exposes the most recent event — it cannot accumulate state across events. When channels fire at different times, you need a map that holds ALL channels' latest values simultaneously.

Good contact threshold: < 500 kΩ. Show a colored indicator per channel.

## StreamProvider vs ref.listen

For UI display: **StreamProvider + select()** — minimizes rebuilds.

```dart
// Only rebuild when the timestamp changes, not on every field update
final lastEegTs = ref.watch(
  eegProvider.select((async) => async.valueOrNull?.timestampMilli),
);
```

For side effects (logging, chart buffer updates): **ref.listen** — executes callback without rebuild.

## Throttle placement: throttle BEFORE expensive work

```dart
// Wrong: expensive work at 250 Hz
device.eegStream
    .map((eeg) => computeSpectrum(eeg))  // 250 calls/sec
    .throttleTime(const Duration(milliseconds: 100))

// Correct: throttle first
device.eegStream
    .throttleTime(const Duration(milliseconds: 100))
    .map((eeg) => computeSpectrum(eeg))  // 10 calls/sec
```

## GC pressure

At 250 Hz with 4 channels × 8 samples: ~64 KB/sec raw allocation. Dart's generational GC handles this trivially. The real GC killer is **String formatting** — don't format `"0.234 μV"` 250 times/sec. Format only on throttled events (which this pattern already ensures).

## High-frequency streams in StatefulShellRoute

Since `StatefulShellRoute.indexedStack` keeps all tabs mounted, stream providers on the Streams tab stay subscribed even when the user switches to other tabs. This is intentional — data flows continuously. The throttled `StreamProvider` state will reflect the latest value whenever the user returns to the Streams tab.
