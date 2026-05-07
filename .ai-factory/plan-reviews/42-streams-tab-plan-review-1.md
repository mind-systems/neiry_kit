## Plan Review: Streams Tab

**Plan file:** `.ai-factory/plans/42-streams-tab.md`
**Files reviewed:** 12 (plan + explore note + 4 models + 3 providers + device_screen + streams_screen stub + architecture)
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md:** WARN — plan says "Follow the visual style of `device_screen.dart` (`Card` + `Padding` + section titles)" but `device_screen.dart` uses `ListView` with `Column` sections and `Divider` — no `Card` widgets. Minor inconsistency; the plan's proposed `Card`-per-section layout is fine on its own, just not matching the existing pattern as claimed.
- **RULES.md:** not present (WARN, non-blocking).
- **ROADMAP.md:** plan aligns with the `Streams tab` milestone. All five stream types mentioned in the roadmap (EEG, PSD, resistance, battery, artifacts) are covered. Throttle rates and the accumulation strategy match the roadmap description.

### Verified Assumptions

All model field names and types in the plan match the actual codebase:

| Plan reference | Actual model | Match |
|---|---|---|
| `EegData.rawValues[channel].last`, `channelCount` | `List<List<double>> rawValues`, `int channelCount` | ✅ |
| `PsdData.frequencies`, `values[ch][i]`, `deltaLower`/`deltaUpper`... | `List<double> frequencies`, `List<List<double>> values`, `double deltaLower`... | ✅ |
| `ResistanceData.channelNames`, `values`, `channelCount` | `List<String> channelNames`, `List<double> values`, `int channelCount` | ✅ |
| `EegArtifactData.artifacts` (List\<int\>), `qualities` (List\<double\>) | `List<int> artifacts`, `List<double> qualities` | ✅ |
| `device.eegStream`, `psdStream`, `resistanceStream`, `batteryStream`, `artifactsStream` | All present as public getters on `Device` | ✅ |
| `activeDeviceProvider`, `deviceIsStartedProvider` | Both exist in `device_state_providers.dart` / `active_device_provider.dart` | ✅ |
| `rxdart` in example deps | Already in `example/pubspec.yaml` | ✅ |
| `StatefulShellRoute.indexedStack` keeps tabs mounted | Confirmed in `router.dart` | ✅ |

### Suggestions

**1. Guard against empty sample lists in EEG display (correctness)**

The plan says: `"Ch N: X.XXX uV" using the last sample in rawValues[channel].last`.

If a batch arrives with `sampleCount == 0` (edge case — e.g. first partial frame), `.last` throws `StateError`. The implementation should guard:

```dart
final samples = eeg.rawValues[ch];
final label = samples.isEmpty ? '—' : '${samples.last.toStringAsFixed(3)} uV';
```

**2. Guard against division by zero in `_bandPower` (correctness)**

If no frequency indices fall within a band's `[lower, upper]` range (e.g. frequency resolution is coarser than expected), the average computation divides by zero. The helper should return `0.0` (or `double.nan`) when the index count is zero.

**3. Explore note vs plan: resistance API mismatch is resolved correctly**

The explore note (`16-explore-example-streams-tab.md`) uses `data.channelName` (singular) and `data.kOhm` — fields that do not exist on `ResistanceData`. The plan correctly uses the actual model API (`data.channelNames[i]`, `data.values[i]`, loop over `data.channelCount`). No action needed, just noting the discrepancy for awareness.

**4. `deviceIsStartedProvider` gate on resistance — design consideration**

The `ResistanceMapNotifier` gates on `deviceIsStartedProvider`, meaning resistance data is only collected while EEG streaming is active. The SDK fires resistance events during impedance-check mode (device connected, before `start()`), which this gate would suppress. If the Streams tab should also display resistance during pre-stream impedance checks, the gate should be changed to `device != null` only (matching the other four providers).

If this is intentional (Streams tab only shows data during active streaming), the current design is fine. Worth a conscious decision during implementation.

**5. Visual style: `SingleChildScrollView` vs `ListView`**

The plan uses `SingleChildScrollView` + `Column`. The device_screen uses `ListView`. For a fixed number of sections, both work. `ListView` is more consistent with the existing screen. Not blocking.

### Positive Notes

- Provider architecture is well-structured: `StreamProvider` for simple pass-through, `NotifierProvider` for the accumulation case (resistance). The rationale for the Notifier approach is clearly explained.
- Throttle rates are sensible and well-justified (EEG 10 Hz, PSD 2 Hz, battery 1 Hz, artifacts unthrottled).
- Throttle-before-transform principle is correctly stated.
- The plan correctly uses `ConsumerWidget` (stateless) since all state lives in providers — lighter than the `ConsumerStatefulWidget` used for device_screen, which needs local form state.
- Clean separation: providers in one file, UI in another. Both file paths are correct.
- PSD band-power computation is correctly scoped as a private top-level helper to keep the widget clean.

### Critical Issues

None.

PLAN_REVIEW_PASS
