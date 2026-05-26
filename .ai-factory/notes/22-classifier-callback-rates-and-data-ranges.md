# Classifier Callback Rates and Data Ranges

**Date:** 2026-05-23
**Source:** conversation context

## Key Findings

- Classifier callbacks fire at **5–10 Hz**, not at the EEG sample rate (~250 Hz) or the SDK Update() ceiling (~25 Hz).
- The SDK event pump (`DeviceLocator.Update()`) runs at ~25 Hz (40 ms), but classifiers internally aggregate and emit at a lower cadence.
- **PhysiologicalStates** is hard-coded to emit once every 2 minutes — confirmed in SDK docs and Dart layer docs.
- **Productivity metrics** (fatigueScore, gravityScore, relaxationScore, etc.) are **not normalized to [0, 1]** — values freely exceed 1.0. Do not assume a unit range when designing UI gauges or API payloads.
- Client-side batching for server upload is needed from day one for NFB/Emotions/Productivity (~5 Hz × 60 s = 300 events/min per stream).

## Details

### Measured rates (real device, Noise/SinWave simulator)

| Stream | Measured rate |
|---|---|
| NFB | 5.0 Hz |
| Emotions | 5.0 Hz |
| Cardio (indexes) | 3.3 Hz |
| Cardio PPG | 3.3 Hz |
| EEG callbacks | 10.0 Hz |
| PSD callbacks | 5.0 Hz |
| PhysiologicalStates | 1 / 120 s |

### How rates were measured

Added a rolling 3-second rate counter to the example app:
- `example/lib/utils/rate_counter.dart` — `rateOf(stream)` transformer
- `example/lib/providers/rate_providers.dart` — per-stream `StreamProvider<double>`
- `example/lib/screens/streams_screen.dart` — `_RateMonitorCard` with live Hz display and a **Log Dump** button that snapshots all rates to the console via `dart:developer` `log(..., name: 'RateMonitor')`

### Expected vs actual

Before measurement, the assumption was that classifiers could fire at up to 25 Hz (the SDK Update() ceiling). In practice they fire at 3–10 Hz — likely because each classifier runs over a sliding window of EEG samples (e.g. 200–500 ms) before emitting a new value.

### Productivity metrics value range

Fields on `ProductivityMetrics` (`fatigueScore`, `reverseFatigueScore`, `gravityScore`, `relaxationScore`, `concentrationScore`, `productivityScore`, `currentValue`, `alpha`, `productivityBaseline`, `accumulatedFatigue`) are **unbounded floats**. Observed values exceed 1.0 in normal operation. The sentinel for "no data yet" is `-1.0` (shared with other SDK types). Do not clamp or normalize these values on the client — pass them as-is to the API and let the server/ML layer handle scaling.

### Implication for server batching

At 5 Hz, a 5-second flush window produces ~25 events per flush per stream. A 1-minute window produces ~300 events. Both are manageable. Recommend a **2–5 second flush window** with a max-batch-size guard (~50 events) as a safe default for the mind_mobile → mind_api pipeline.

## Open Questions

- Do rates differ between the Noise/SinWave simulator and a real Neiry Headband? The 5 Hz figure came from a simulator run — real hardware may differ.
- Does `accumulatedFatigue` have a documented upper bound, or is it truly unbounded over a session?
