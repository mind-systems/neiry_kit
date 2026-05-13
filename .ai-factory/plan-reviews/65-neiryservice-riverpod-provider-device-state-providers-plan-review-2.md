# Plan Review: NeiryService Riverpod provider + device state providers (v2)

**Plan:** `.ai-factory/plans/65-neiryservice-riverpod-provider-device-state-providers.md`
**Risk Level:** 🟢 Low

## Context Gates

- **ARCHITECTURE.md:** Not present at `.ai-factory/ARCHITECTURE.md`. WARN.
- **RULES.md:** Not present at `.ai-factory/RULES.md`. WARN.
- **ROADMAP.md:** Milestone #89 matches this plan's scope; downstream milestones #90–#94 explicitly own the screen/classifier-provider migrations Task 6 is allowed to break. Plan alignment ✅.

## Diff vs. plan-review-1

All four substantive corrections from review-1 are addressed:

| review-1 issue | v2 status |
|---|---|
| Task 6 acknowledged only 3 broken-import sites instead of 8 | Fixed — explicit 8-file enumeration (`main.dart`, `device_screen.dart`, six classifier providers) at lines 137–145. `classifiers_screen.dart` correctly clarified as a cascade, not a direct importer (line 149). |
| `_artifactsController.close()` placement unspecified | Fixed — placement note at line 94: "next to other device-stream controllers, after `_batteryController.close()`, before the classifier controllers". |
| `rxdart` import preservation | Fixed — bold-call-out at line 103. |
| Fire-and-forget disposal via `ref.onDispose(s.dispose)` | Fixed — explanatory note at line 30 deferring authoritative await to `main.dart`'s `_cleanupAndDispose()` in milestone #92. |

## Critical Issues

None.

## Other Issues

### 1. The "only `deviceUiStateProvider` reads `deviceConnectionStateProvider`" claim is inaccurate

Task 3, line 60:

> Verified consumers: only `deviceUiStateProvider` reads `deviceConnectionStateProvider` (grep confirmed — `streams_screen.dart` and other screens watch `deviceUiStateProvider` / `deviceModeProvider` instead).

This is incorrect. `device_screen.dart:168` reads `deviceConnectionStateProvider` directly:

```dart
final connectionAsync = ref.watch(deviceConnectionStateProvider);
// …
_buildStatusSection(uiState, connectionAsync);
// where _buildStatusSection renders:
connectionAsync.when(
  loading: () => const Text('Connection state: …'),
  error:   (e, _) => Text('Connection error: $e'),
  data:    (cs) => Text('Connection state: ${cs.name}'),
)
```

Practical impact is minor: under the previous implementation (`Stream.value(NeiryConnectionState.disconnected)`), the device screen showed `Connection state: disconnected` immediately on app launch. After this plan, it shows `Connection state: …` (the `loading` branch) until `connect()` is called, then transitions to the real state. That's a transient text label, not a functional regression — `_buildActionsSection` is driven by `uiState`, which still maps both the old `disconnected` and the new `loading` paths to `DeviceUiState.idle` (confirmed in `device_state_providers.dart:46–57`).

This is acceptable because:
- `device_screen.dart` itself is explicitly slated for migration in milestone #92 (Task 6 lists it as one of the eight expected broken consumers anyway).
- The change is purely a transient display label, not behavior.

Action: tighten the plan's audit sentence to acknowledge the second direct consumer, e.g. "Direct consumers: `deviceUiStateProvider` (handles loading via `whenOrNull`) and `device_screen.dart:168` (renders loading as `Connection state: …` until first emission — accepted as a transient label; screen will be migrated in #92)." Not a blocker, but the grep claim should match reality.

### 2. `deviceModeProvider` behavior change is also worth a one-line note

Same pattern as Issue #1, smaller surface. Previously the provider returned `Stream.empty()` when no device was active, so `deviceModeProvider` stayed in `AsyncLoading` (empty streams emit no data). After the rewrite it watches `neiryService.modeStream`, which is a broadcast controller that also emits nothing pre-connect — `AsyncLoading` is preserved. Effective behavior is unchanged, but the plan could state this explicitly alongside the `deviceConnectionStateProvider` confirmation so the implementer doesn't second-guess. Strictly cosmetic.

### 3. Verify `_artifactsController` cleanup on `disconnect()` vs `dispose()`

Task 4 specifies adding `_artifactsController.close()` to `dispose()` only, mirroring the other broadcast controllers in `NeiryService.dispose()` (lines 281–299). Confirmed correct against the existing pattern: the long-lived broadcast controllers are not closed on `disconnect()` — they stay open so the next `connect()` can fan-in again. The fan-in `StreamSubscription` itself lives in `_activeSubscriptions`, which `disconnect()` already cancels (lines 213–219). No additional subscription bookkeeping needed in the plan — the existing list handles the artifacts subscription identically to EEG/PSD/etc. ✅ (Just noting this so the implementer doesn't preemptively add a `_artifactsController.close()` to `disconnect()`.)

### 4. Scan invalidation behavior is unchanged (informational)

`service.scan(...).first` matches the prior `locator.requestDevices(...).first` semantics: invalidating the family entry mid-scan orphans the future but the native scan continues to its `searchTime` boundary. Existing behavior, not a regression. (Carried over from review-1 for completeness.)

## Positive Notes

- All four review-1 corrections cleanly incorporated; no introduced regressions in v2 wording.
- Phasing remains clean: scan → state → streams → delete, each commit independently meaningful.
- `_artifactsController` addition is fully specified now: field declaration, getter, fan-in subscription appended to the `_activeSubscriptions.addAll([...])` block, and `dispose()` close site all called out.
- Task 6 explicitly disclaims preemptive fixes to the eight cascading consumers and points each one to its owning downstream milestone (#90/#92/#93) — keeps this milestone tightly scoped.
- The `ResistanceMapNotifier` rewrite preserves the per-channel merge logic byte-for-byte, with `ref.onDispose` still cancelling the subscription. Pre-connect empty-map default falls out naturally from the broadcast controller emitting nothing pre-`connect()`. ✅
- Correct use of `ref.read` vs `ref.watch` for `neiryServiceProvider` in the scan callback, with rationale included.
- Throttle timings (100 / 500 / 1000 ms) preserved bit-for-bit.

## Verdict

The single substantive correction from review-1 (Task 6 enumeration) is addressed correctly and exhaustively. The remaining v2 issue — the grep claim in Task 3 that omits `device_screen.dart:168` as a direct consumer — is a documentation accuracy issue with negligible functional impact (transient `Connection state: …` label on the device screen until migration in #92). Tightening that sentence would be nice; nothing else needs to change before implementation.

PLAN_REVIEW_PASS
