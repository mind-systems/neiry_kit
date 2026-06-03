# Teardown Invariants, Stale endOfStream, and Post-Disconnect Re-Scan Hardening

**Date:** 2026-06-03
**Source:** conversation context

## Key Findings

- Three SIGABRT/Fatal signal crash categories on disconnect were eliminated by establishing three SDK teardown invariants (A/B/C) and a strict 5-step disconnect sequence in `NeiryService`.
- `Bad state: No element` on repeat scan was caused by two independent classes of spurious endOfStream, requiring two independent fixes: one in Kotlin (`DeviceLocatorBridge.kt`) and one in Dart (`device_locator.dart`).
- After `nativeReleaseDevice`, the C SDK clears its internal device list; `createDevice(serial)` fails with "Empty list of available devices" unless a fresh scan is performed first. The UI must clear scan results after every disconnect.

## Details

### Part 1 — SDK Teardown Invariants (SIGABRT / Fatal signal crashes)

Three hard invariants that the C SDK enforces silently via crashes:

| # | Invariant | Crash if violated |
|---|---|---|
| A | `nativeUnregisterDeviceCallbacks` before any JNI EventSink ref is deleted | `0xebadde09` — background SDK thread uses deleted ref |
| B | All classifiers disposed before `nativeReleaseDevice` | `SIGABRT` — `IsClassifierSupported` on freed handle |
| C | `nativeReleaseDevice` called immediately after `nativeDisconnectDevice`, before async BLE teardown | `Fatal signal 64` — stale GATT JNI refs |

**New methods added to support the correct sequence:**

- `Device.unregisterCallbacks()` — `lib/src/api/device.dart` + `DeviceBridge.kt` + `DeviceBridge.swift`; calls `nativeUnregisterDeviceCallbacks`; must be step 1.
- `Device.stopStream()` — stop + unregister without `nativeRelease`; used internally by `NeiryService.disconnect()` when streaming was active.
- `DeviceMethods.unregisterCallbacks` added to `lib/src/channel/channel_names.dart`.

**`NeiryService.disconnect()` 5-step sequence** (`example/lib/services/neiry_service.dart`):
1. `device.unregisterCallbacks()` — satisfies invariant A
2. Cancel all fan-in stream subscriptions — safe, background threads stopped
3. `Future.wait([classifier.dispose()…])` — satisfies invariant B
4. `if (wasStarted) device.stopStream()` — native stop without release
5. `device.disconnect()` — `nativeDisconnect` + `nativeRelease` (satisfies invariant C)
6. `device.dispose()` — Dart cleanup, guarded by `if (_connected)` (no-op here)

`NeiryService.stop()` delegates to `disconnect()` — there is no "pause streaming without disconnect" concept.

Documented in `docs/guides/teardown.md`.

---

### Part 2 — Stale endOfStream on Repeat Scan (`Bad state: No element`)

Flutter's EventChannel binary handler is a singleton per channel name. Two independent classes of spurious endOfStream were identified:

**Class 1 — Kotlin: SDK immediate reset (~54 ms after `nativeRequestDevices`)**

The C SDK fires `endOfStream` on the current sink ~54ms into a new scan, resetting leftover state from the previous scan. No `success` event precedes it.

Fix in `DeviceLocatorBridge.kt` (`DeviceLocatorBridge.onListen`): wrap each scan's sink with `val eventReceived = AtomicBoolean(false)`. Only forward `endOfStream` to Dart if `eventReceived` is true (i.e. at least one `success` or `error` arrived first). `import java.util.concurrent.atomic.AtomicBoolean`.

**Class 2 — Dart: stale null binary message from previous scan**

When scan N completes, `realSink.endOfStream()` sends a null binary message into Dart's binary messenger queue. If scan N+1 registers its handler before Dart drains that null, the null is delivered to the new handler → `controller.close()` → `.first` gets `onDone` without data → `Bad state: No element`.

`receiveBroadcastStream()` cannot be fixed — it closes the controller unconditionally on any null. Fix: bypass it entirely.

Fix in `device_locator.dart` (`DeviceLocator.requestDevices`):
- Register binary handler directly via `ServicesBinding.instance.defaultBinaryMessenger.setMessageHandler(NeiryEvents.deviceList, handler)`.
- Track `bool dataReceived` per scan closure.
- `null` message + `dataReceived == false` → stale endOfStream, silently dropped; handler stays active.
- `null` message + `dataReceived == true` → legitimate endOfStream, close controller.
- Non-null message → decode via `StandardMethodCodec().decodeEnvelope(message)`.
- Send `'listen'`/`'cancel'` via `MethodChannel(NeiryEvents.deviceList).invokeMethod(...)`.
- `_scanSubscription: StreamSubscription?` removed; replaced with `_cancelScan: void Function()?`.

**Key files changed:**
- `android/src/main/kotlin/com/neiry/neiry_kit/DeviceLocatorBridge.kt`
- `lib/src/api/device_locator.dart`

Documented in `docs/guides/teardown.md` — section "Устаревший endOfStream при повторном сканировании".

---

### Part 3 — Post-Disconnect Re-Scan Requirement

After `nativeReleaseDevice`, the C SDK clears its internal list of discovered devices. Calling `nativeCreateDevice(serial)` without a preceding fresh scan fails with `PlatformException(255, Empty list of available devices)`.

Fix in `device_screen.dart` (`_DeviceScreenState`):

- Added `_clearScan()`: calls `setState(() { _scanParams = null; _selectedSerial = null; })` first (removes provider listener), then `WidgetsBinding.instance.addPostFrameCallback((_) { ref.invalidate(deviceScanProvider(params)); })` post-frame (clears cache after the widget stops watching — prevents an unwanted auto-scan).
- Called in both `_stop()` and `_disconnect()` after the service call succeeds.
- `_showError()` now logs via `nlog` before showing the snackbar — all errors shown in the UI are now in logcat.
- `_connect()`, `_disconnect()` catch blocks now log before calling `_showError`.

Documented in `docs/guides/teardown.md` — section "Обязательный повторный скан перед connect" under "Повторное подключение после Disconnect".

---

### Error log (mistakes made during implementation)

- `@Volatile var eventReceived = false` — `@Volatile` is not applicable to Kotlin local variables, only to class properties. Compile error. Fix: `val eventReceived = AtomicBoolean(false)`.
- The `armed` AtomicBoolean approach (post `nativeRequestDevices` on `mainHandler`) failed because `armed.set(true)` fires ~1ms later while the SDK's deferred endOfStream fires ~54ms later — the flag was already true when it arrived. Two rounds wasted on Kotlin-only fixes before identifying the Dart (Class 2) root cause.
- `ref.invalidate()` in `_clearScan()` while the widget still watched the provider triggered an immediate unwanted auto-scan. Fix: setState first, invalidate post-frame.
