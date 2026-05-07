## Code Review: Streams Tab (round 2)

**Plan:** `.ai-factory/plans/42-streams-tab.md`
**Files reviewed:** `example/lib/providers/stream_providers.dart`, `example/lib/screens/streams_screen.dart`
**Models cross-checked:** `EegData`, `PsdData`, `ResistanceData`, `EegArtifactData`, `Device`

---

### Review-1 fix verification

All three findings from review-1 have been resolved:

| # | Finding | Status |
|---|---|---|
| 1 | `eeg.rawValues[ch].last` crashes on empty list | Fixed — `Builder` with `samples.isEmpty` guard (`streams_screen.dart:59-65`) |
| 2 | `trailing: true` doubles throttle rate | Fixed — removed, now uses default leading-only (`stream_providers.dart:13,20,27`) |
| 3 | `resistanceMapProvider` gates on `isStarted` | Fixed — only gates on `device == null` (`stream_providers.dart:49,55`); `deviceIsStartedProvider` import removed |

### Full pass — no new findings

- **Types:** all field accesses match the model definitions (`EegData.rawValues`, `PsdData.frequencies/values/deltaLower..betaUpper`, `ResistanceData.channelNames/values/channelCount`, `EegArtifactData.artifacts/qualities/channelCount`, `Device.batteryStream` → `Stream<int>`).
- **Division safety:** `_bandPower` returns `0` when `count == 0 || channelCount == 0`.
- **Subscription lifecycle:** `ResistanceMapNotifier` cancels in both `build()` (dependency change) and `ref.onDispose()` (provider disposal). Double-cancel is harmless (idempotent).
- **Throttle rates:** `throttleTime` with default `leading: true, trailing: false` gives the specified rates (10 Hz, 2 Hz, 1 Hz).
- **Provider consistency:** all five providers gate on `activeDeviceProvider` only, letting the SDK's own event lifecycle determine data flow.

REVIEW_PASS
