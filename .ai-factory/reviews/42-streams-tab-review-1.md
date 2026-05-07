## Code Review: Streams Tab

**Plan:** `.ai-factory/plans/42-streams-tab.md`
**Files reviewed:** `example/lib/providers/stream_providers.dart`, `example/lib/screens/streams_screen.dart`
**Models cross-checked:** `EegData`, `PsdData`, `ResistanceData`, `EegArtifactData`, `Device`

---

### Finding 1 — `eeg.rawValues[ch].last` crashes on empty sample list

**File:** `example/lib/screens/streams_screen.dart:60`
**Severity:** Bug

```dart
'Ch $ch: ${eeg.rawValues[ch].last.toStringAsFixed(3)} μV',
```

If the SDK delivers an EEG batch with `sampleCount == 0`, the inner list is empty and `.last` throws `StateError("No element")`. The `EegData.fromMap` factory faithfully decodes whatever the native side sends — it does not guarantee non-empty inner lists.

**Fix:** Guard the access:

```dart
final samples = eeg.rawValues[ch];
final label = samples.isEmpty
    ? 'Ch $ch: —'
    : 'Ch $ch: ${samples.last.toStringAsFixed(3)} μV';
Text(label),
```

---

### Finding 2 — `trailing: true` doubles effective throttle rate

**File:** `example/lib/providers/stream_providers.dart:14-17, 24-27, 34-37`
**Severity:** Bug

All three throttled providers pass `trailing: true`:

```dart
device.eegStream.throttleTime(
  const Duration(milliseconds: 100),
  trailing: true,   // ← not in plan
);
```

With both `leading: true` (default) and `trailing: true`, `throttleTime` emits on **both** edges of the window. For a continuous 250 Hz EEG stream this produces ~20 emissions/sec (leading at t=0, trailing at t=100ms, leading at ~t=104ms, ...) — double the plan's stated 10 Hz. Same doubling applies to PSD (4 Hz vs 2 Hz) and battery (2 Hz vs 1 Hz).

The milestone explicitly specifies "10 Hz" for EEG. Either:

- **Remove `trailing: true`** to match the spec (default `leading: true, trailing: false` gives the documented rate), or
- **Set `leading: false`** to keep only trailing (emits the freshest sample per window at exactly the target rate).

`trailing: true` alone isn't wrong — it shows fresher data — but it contradicts the stated rates and doubles widget rebuilds.

---

### Finding 3 — `resistanceMapProvider` gates on `deviceIsStartedProvider`, suppressing impedance-check data

**File:** `example/lib/providers/stream_providers.dart:58, 64`
**Severity:** Design issue

```dart
final isStarted = ref.watch(deviceIsStartedProvider);
// ...
if (device == null || !isStarted) return {};
```

The primary use case for resistance data is **impedance checking before starting EEG** — the device is connected but `start()` has not been called. Gating on `isStarted` prevents resistance data from appearing during that phase, making the display useless for its main purpose.

The other four stream providers (eeg, psd, battery, artifacts) do NOT gate on `isStarted` — they only check `device != null` and let the SDK's own event lifecycle determine when data flows. Resistance should follow the same pattern:

```dart
if (device == null) return {};
```

Drop the `isStarted` watch and the `deviceIsStartedProvider` import (if it becomes unused).
