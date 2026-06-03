# Handoff — stale-endofstream-scan-fix

## 1. Frame
The "Bad state: No element" crash on repeat scan is fixed — both Kotlin and Dart layers are in place and confirmed working; all changes are uncommitted.

## 2. Read-first map

### Must-read now
- `docs/guides/teardown.md` — documents both the teardown invariants AND the new "Устаревший endOfStream" section; ground truth for all three crash categories + repeat-scan fix
- `lib/src/api/device_locator.dart` — fully rewritten `requestDevices()` with custom binary handler + `dataReceived` guard; `_scanSubscription` is gone
- `android/src/main/kotlin/com/neiry/neiry_kit/DeviceLocatorBridge.kt` — `eventReceived: AtomicBoolean` guard on wrapped sink

### Read on demand
- `.ai-factory/notes/26-teardown-scan-crash-fixes.md` — prior handoff covering the teardown SIGABRT bugs; those are done, not re-litigated here
- `.ai-factory/notes/25-global-log-helper.md` — spec for ROADMAP task 25 (nlog migration, still pending)

## 3. Current state

**Done:**
- **Class 1 fix (Kotlin):** `DeviceLocatorBridge.onListen` wraps each scan's sink with `AtomicBoolean eventReceived`; `endOfStream()` is only forwarded to Dart if a `success` or `error` event arrived first. Blocks the SDK's immediate ~50ms reset-endOfStream on a new scan.
- **Class 2 fix (Dart):** `DeviceLocator.requestDevices()` bypasses `receiveBroadcastStream()` and registers the binary handler directly via `ServicesBinding.instance.defaultBinaryMessenger.setMessageHandler`. The `dataReceived` flag (Dart-local) blocks stale null binary messages from the previous scan's real completion from closing the new scan's controller.
- `_scanSubscription: StreamSubscription?` field removed from `DeviceLocator`; replaced with `_cancelScan: void Function()?` pointing to the active scan's `teardown()` closure.
- `docs/guides/teardown.md` — "Устаревший endOfStream при повторном сканировании" section added (cause, both classes, both layers of fix).
- Confirmed working in logcat: second scan shows "stale null dropped (no data yet)", then real BLE scan runs and completes normally.

**In-flight:**
- ROADMAP task 25 (nlog migration) — 8 `example/lib/` files still use `dart:developer` `log()` instead of `nlog()`. Spec: `.ai-factory/notes/25-global-log-helper.md`.
- No commits made this session or the previous one — entire working tree is uncommitted.

**Uncommitted working-tree state:**
- `android/src/main/kotlin/com/neiry/neiry_kit/DeviceBridge.kt`
- `android/src/main/kotlin/com/neiry/neiry_kit/NeiryKitPlugin.kt`
- `android/src/main/kotlin/com/neiry/neiry_kit/DeviceLocatorBridge.kt`
- `ios/Classes/DeviceBridge.swift`
- `ios/Classes/NeiryKitPlugin.swift`
- `lib/src/api/device.dart`
- `lib/src/api/device_locator.dart`
- `lib/src/channel/channel_names.dart`
- `lib/src/util/nlog.dart`
- `example/lib/services/neiry_service.dart`
- `example/lib/screens/device_screen.dart`
- `example/lib/providers/device_scan_provider.dart`
- `docs/guides/teardown.md`
- `docs/guides/session-guide.md`
- `CLAUDE.md`
- `.ai-factory/ROADMAP.md`
- `.ai-factory/notes/25-global-log-helper.md` (new)
- `.ai-factory/notes/26-teardown-scan-crash-fixes.md` (new)
- `.ai-factory/notes/27-stale-endofstream-scan-fix.md` (new)

## 4. Next step
User tests the full combined flow: Scan → 0 devices → Scan again (should work) → Connect → Start → Stop → Disconnect. Then commit all pending changes once satisfied.

## 5. Working discipline
- No commits without explicit user request
- User tests on real hardware (Samsung SM A705FN), pastes logcat
- Hot restart doesn't apply Kotlin/native changes — full `flutter run` required
- Don't roll back anything without explicit request

## 6. Error log
- **`@Volatile var eventReceived = false`**: Kotlin's `@Volatile` annotation is only applicable to class fields, not local variables. Compile error. Fix: `val eventReceived = AtomicBoolean(false)` with `import java.util.concurrent.atomic.AtomicBoolean`.
- **Misidentified which class of stale endOfStream was failing**: First two Kotlin-only fixes (`armed` AtomicBoolean, then `eventReceived`) both correctly blocked Class 1 (SDK reset on new scan). But the actual failure after the Kotlin fix was Class 2 (Dart binary messenger stale null from scan N's real completion). This was visible in the log: no `DeviceLocatorBridge.endOfStream` log appeared for failing scans, meaning Kotlin wasn't the source — the null came from a previous cycle already in the Dart queue. Wasted two rounds on Kotlin before identifying the Dart root cause.

## 7. Orientation
- **Two classes of spurious endOfStream, two different fixes**: Class 1 = Kotlin SDK fires immediate `endOfStream` on the current sink ~50ms into a new scan (resetting previous state). Fixed in Kotlin with `eventReceived`. Class 2 = scan N's real `endOfStream` sends a null binary message that lands at scan N+1's Dart handler before scan N's handler was de-registered. Fixed in Dart with `dataReceived`. Both fixes are needed simultaneously.
- **`receiveBroadcastStream()` is fundamentally broken for this use case**: Flutter's EventChannel binary handler is a singleton keyed by channel name — registering a new handler does not drain or discard the pending message queue. Any stale null in the queue is delivered to the next handler. Don't try to fix this by wrapping `receiveBroadcastStream()`; the handler must be registered directly.
- **`_scanSubscription` is gone**: `DeviceLocator` no longer holds a `StreamSubscription`. Cancel-on-overlap uses `_cancelScan: void Function()?`. Don't try to re-introduce the `StreamSubscription` pattern.

## 8. Domain model spine
- **Two-layer endOfStream guard**: Kotlin `eventReceived` (Class 1) + Dart `dataReceived` (Class 2). Both required. Don't re-litigate by removing either layer. Source: `DeviceLocatorBridge.kt` + `device_locator.dart` + `docs/guides/teardown.md`.
- **requestDevices uses raw binary messenger**: `setMessageHandler(NeiryEvents.deviceList, ...)` + `MethodChannel(NeiryEvents.deviceList).invokeMethod('listen'/'cancel')`. Not `receiveBroadcastStream()`. Don't re-litigate. Source: `device_locator.dart`.
- **Stop = Disconnect**: `NeiryService.stop()` delegates to `disconnect()`. No pause concept. Don't re-litigate. Source: `docs/guides/teardown.md`.
- **Teardown invariants A/B/C**: Documented in `docs/guides/teardown.md`. Don't re-litigate.

## 9. Hard rules
- No commits without explicit user permission
- All files in English
- No commit type prefixes — sentence-case noun phrases only
- Memory writes only on explicit trigger ("запомни", "remember this", etc.)
