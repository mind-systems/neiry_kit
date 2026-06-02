# Handoff — teardown-scan-crash-fixes

## 1. Frame
Three crash categories in `neiry_kit` Android plugin have been fixed and documented; the scan state machine bug has a Kotlin fix applied that requires a full rebuild to take effect; log infrastructure is partially migrated to `nlog`.

## 2. Read-first map

### Must-read now
- `docs/guides/teardown.md` — authoritative doc on SDK invariants and the one correct disconnect sequence; this is the ground truth
- `android/src/main/kotlin/com/neiry/neiry_kit/DeviceLocatorBridge.kt` — contains the stale-endOfStream fix (Kotlin, needs full rebuild)
- `example/lib/services/neiry_service.dart` — disconnect sequence implementation; `stop()` delegates to `disconnect()`

### Read on demand
- `android/src/main/kotlin/com/neiry/neiry_kit/DeviceBridge.kt` — `unregisterCallbacks()`, `stop()`, `disconnect()` with nativeRelease
- `ios/Classes/DeviceBridge.swift` — iOS mirror of same fixes
- `lib/src/api/device.dart` — `unregisterCallbacks()`, `stopStream()` methods; now uses `nlog`
- `lib/src/channel/channel_names.dart` — `DeviceMethods.unregisterCallbacks` added
- `.ai-factory/notes/25-global-log-helper.md` — spec for nlog migration task (remaining example/ files)

## 3. Current state

**Done:**
- Bug 1: `Device.dispose()` guards `if (_connected)` — no double native disconnect
- Bug 2: `DeviceBridge.stop()` calls `nativeUnregisterDeviceCallbacks` before `nativeStopDevice` — stops SDK background threads before JNI refs deleted
- Bug 3: `nativeReleaseDevice` called immediately after `nativeDisconnectDevice` and `nativeStopDevice` — prevents stale GATT JNI refs (Fatal signal 64)
- Bug 4 (Stop → Disconnect crash): `NeiryService.stop()` now delegates to `disconnect()` — "connected or not" model, no Stop/Start cycle
- New `Device.unregisterCallbacks()` wired through full stack (Dart → Kotlin/Swift → native)
- New `Device.stopStream()` (stop without nativeRelease) used as step 1 of disconnect when streaming
- `NeiryService.disconnect()` sequence: `unregisterCallbacks` → cancel subs → dispose classifiers → `stopStream()` if started → `disconnect()` → `dispose()`
- `docs/guides/teardown.md` created with SDK invariants A/B/C and correct sequence
- `docs/guides/session-guide.md` section 8 updated to correct teardown
- `lib/src/util/nlog.dart` created by user; `device.dart`, `device_locator.dart`, `device_screen.dart`, `device_scan_provider.dart` already migrated to `nlog`
- ROADMAP task 25 added: global log helper migration (remaining example/ files)
- Diagnostic logs added: `NeiryService.connect/start/stop/disconnect`, `Device.connect/start/stop`, `DeviceLocator.requestDevices/createDevice`, `device_scan_provider`, `device_screen`

**In-flight:**
- Scan "Bad state: No element" fix — `DeviceLocatorBridge.kt` `@Volatile currentSink` guard applied but **requires full rebuild** (`flutter run`, not hot restart)
- ROADMAP task 25 (nlog migration) — `lib/` files and some `example/lib/` files done; remaining: `neiry_service.dart`, `router.dart`, `streams_screen.dart`, `calibration_screen.dart`, `classifiers_screen.dart`, `mems_screen.dart`, `productivity_cardio_screen.dart`, `sound_service_provider.dart`

**Uncommitted working-tree state:**
- `android/src/main/kotlin/com/neiry/neiry_kit/DeviceBridge.kt`
- `android/src/main/kotlin/com/neiry/neiry_kit/NeiryKitPlugin.kt`
- `android/src/main/kotlin/com/neiry/neiry_kit/DeviceLocatorBridge.kt`
- `ios/Classes/DeviceBridge.swift`
- `ios/Classes/NeiryKitPlugin.swift`
- `lib/src/api/device.dart`
- `lib/src/api/device_locator.dart`
- `lib/src/channel/channel_names.dart`
- `lib/src/util/nlog.dart` (new)
- `example/lib/services/neiry_service.dart`
- `example/lib/screens/device_screen.dart`
- `example/lib/providers/device_scan_provider.dart`
- `docs/guides/teardown.md` (new)
- `docs/guides/session-guide.md`
- `CLAUDE.md`
- `.ai-factory/ROADMAP.md`
- `.ai-factory/notes/25-global-log-helper.md` (new)

## 4. Next step
Run `flutter run` (full rebuild) to apply the Kotlin `DeviceLocatorBridge` stale-endOfStream fix, then test: Scan → 0 devices → Scan again → should show scan result, not "Bad state: No element".

## 5. Working discipline
- No commits without explicit user request
- User tests on real hardware (Samsung SM A705FN), pastes logcat
- "Don't change anything" = just analyze the log, add logs if needed
- Don't roll back changes unless user explicitly asks
- Hot restart doesn't apply Kotlin/native changes — full rebuild required

## 6. Error log
- **Per-file `_ts()` helpers**: Added `String _ts()` to each file individually instead of a shared helper. User rejected. Reverted completely. Fix: use `lib/src/util/nlog.dart` (already created by user).
- **Task spec listed `_ts()` cleanup**: Roadmap task 25 spec mentioned removing ad-hoc helpers as a deliverable. User rejected — cleaning up prior mistakes is not a task. Rewritten to describe only the feature.
- **Files-to-touch list was incomplete**: Spec note listed 5 files; correct answer is 14. Always grep before listing.

## 7. Orientation
- **`stop()` vs `stopStream()` on `Device`**: `stop()` = nativeUnregister + nativeStop + **nativeRelease** (handle=0); `stopStream()` = nativeUnregister + nativeStop, no release. Only `stopStream()` is safe inside a disconnect sequence. `NeiryService.stop()` delegates to `disconnect()` which uses `stopStream()` internally.
- **Hot restart vs full rebuild**: Kotlin/native changes require full `flutter run`. Hot restart only reloads Dart. If a Kotlin fix doesn't seem to work after hot restart — it wasn't compiled.
- **`0xebadde09`**: ART poisoned JNI global ref marker — background thread used a ref after `DeleteGlobalRef`. Invariant A violation.

## 8. Domain model spine
- **Invariant A** (`DeviceBridge.kt`): `nativeUnregisterDeviceCallbacks` before any JNI EventSink ref is deleted. Don't re-litigate.
- **Invariant B** (`DeviceBridge.kt`): All classifiers disposed before `nativeReleaseDevice`. Don't re-litigate.
- **Invariant C** (`DeviceBridge.kt`): `nativeReleaseDevice` called synchronously after `nativeDisconnectDevice`, before async BLE teardown completes. Don't re-litigate.
- **Stop = Disconnect** (`NeiryService`): No "pause streaming" concept. `stop()` delegates to `disconnect()`. Don't re-litigate.
- **Stale endOfStream** (`DeviceLocatorBridge.kt`): Each scan's EventSink wrapped in guard. `currentSink` replaced on new `onListen` — old guard drops stale event. Needs full rebuild to test.

## 9. Hard rules
- No commits without explicit user permission
- All files in English
- No commit type prefixes — sentence-case noun phrases only
- Memory writes only on explicit trigger phrases
- Never include "cleanup of prior mistakes" in task specs
