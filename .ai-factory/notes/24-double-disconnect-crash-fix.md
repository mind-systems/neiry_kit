# Double-Disconnect Crash After Device Disconnect

**Date:** 2026-06-02
**Source:** conversation context

## Key Findings

- The post-disconnect crash (`Fatal signal 64` in `libCapsuleClient.so`, Thread-206) is caused by `Device.dispose()` calling native disconnect a second time while the GATT stack is still completing async teardown from the first `Device.disconnect()` call.
- `NeiryService.disconnect()` calls both `_device!.disconnect()` (step 3b) and `_device!.dispose()` (step 3c) — `dispose()` unconditionally invokes `DeviceMethods.disconnect` on the native side regardless of current connection state.
- The double native disconnect causes an anomalous `setCharacteristicNotification enable: true` in the GATT layer after the first disconnect completes, corrupting the SDK's internal state machine and causing it to crash in a background BLE thread.
- Fix is one guard line in `lib/src/api/device.dart:228`: skip native disconnect in `dispose()` when `!_connected` (which is `false` after `disconnect()` returns).

## Details

### Crash Signature

```
W/iry_kit_exampl: 0xebadde09 skipped times: 0
F/Backtrace: [critical] 0# in libCapsuleClient.so
F/Backtrace:             1# in /system/bin/app_process64
F/Backtrace:             2# __kernel_rt_sigreturn in [vdso]
F/libc: Fatal signal 64 (?), code 345765216 (?) in tid 14782 (Thread-206)
```

`0xebadde09` is an ART runtime marker for a bad JNI or native reference. Signal 64 (real-time signal) from `libc` indicates the Capsule SDK deliberately aborts on detecting corrupted internal state.

### Crash Timeline

```
[NeiryService] step 3b: disconnecting device
[Device] disconnect — serial: 820566
[Device] native disconnect returned
[Device] disconnect complete                       ← _connected = false
[NeiryService] step 3b done
[NeiryService] step 3c: disposing device
[Device] dispose — connected: false started: false ← _connected is already false
[Device] dispose complete                          ← BUT native disconnect was still called!
[NeiryService] disconnect complete

D/BluetoothGatt: setCharacteristicNotification enable: true   ← ANOMALY from 2nd disconnect
D/BluetoothGatt: setCharacteristicNotification enable: false
D/BluetoothGatt: cancelOpen()
D/BluetoothGatt: onClientConnectionState() x2
D/BluetoothGatt: close()
D/BluetoothGatt: unregisterApp()
CRASH in libCapsuleClient.so Thread-206
```

The second `nativeDisconnectDevice` arrives while the GATT stack is in mid-teardown. The SDK tries to re-enable a characteristic notification (enable:true on uuid 7e400005, which is the PPG notification), then immediately disables it again. This puts the SDK's state machine into an inconsistent state that causes a crash inside `unregisterApp()`.

### Root Cause in Code

**`lib/src/api/device.dart`** — `dispose()` (line 228):
```dart
Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _stopStateTracking();
    // Comment says "Idempotent on the native side" — this is FALSE.
    // The Capsule SDK crashes if disconnect is called while a prior
    // disconnect is still completing its async GATT teardown.
    await _channel.invokeMethod<void>(DeviceMethods.disconnect, {
      NeiryArgs.serial: serial,
    });
    ...
}
```

**`example/lib/services/neiry_service.dart`** — `disconnect()` (lines 288–293):
```dart
try {
    await _device!.disconnect();  // ← 1st native disconnect, sets _connected = false
} catch (_) {}
try {
    await _device!.dispose();    // ← 2nd native disconnect (unconditional) → CRASH
} catch (_) {}
```

### Fix

In `lib/src/api/device.dart`, guard the native disconnect in `dispose()`:

```dart
Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _stopStateTracking();
    if (_connected) {
        // Only call native disconnect if disconnect() was not already called.
        // The Capsule SDK is NOT idempotent — double disconnect during async
        // GATT teardown corrupts internal state and causes Fatal signal 64.
        await _channel.invokeMethod<void>(DeviceMethods.disconnect, {
          NeiryArgs.serial: serial,
        });
    }
    _started = false;
    _connected = false;
    ...
}
```

`_connected` is set to `false` inside `disconnect()` after the native call returns. When `dispose()` is called after `disconnect()`, `_connected` is already `false`, so the second native call is skipped.

### Files Involved

| File | Role |
|------|------|
| `lib/src/api/device.dart:228` | `dispose()` — add `if (_connected)` guard before native disconnect |
| `example/lib/services/neiry_service.dart:288` | `disconnect()` — calls both `disconnect()` + `dispose()` on device |

### Why `dispose()` Still Has Value

`dispose()` sets `_disposed = true`, which causes all future method calls to throw `StateError('Device has been disposed')`. Even after `disconnect()`, `dispose()` should still be called to lock down the object. The only change is that the native disconnect is skipped when it was already called.

### iOS Parity Note

On iOS, `DeviceBridge.disconnect()` (Swift) does NOT call `unregisterCallbacks()` — only `release()` does. This means C callbacks remain registered after disconnect and can fire during async BLE teardown. While the iOS side has not been observed crashing (the `guard let bridge = DeviceBridge.activeBridge` check silently drops late callbacks), unregistering callbacks in `disconnect()` before calling `clCDevice_Disconnect` would be the safer pattern. This is a secondary concern — the Android crash is the primary bug.

## Open Questions

- Should `unregisterCallbacks()` also be called in iOS `DeviceBridge.disconnect()` before `clCDevice_Disconnect` for symmetry with the Android fix? The current silent-drop guard works but leaves a window where callbacks fire on a disconnected device.
- Does `NeiryService.disconnect()` need to call `_device!.dispose()` at all, given that `_device` is immediately nulled in step 4? Removing the `dispose()` call would also fix the double-disconnect bug, but then the Dart `Device` object is never formally disposed, which means future calls on any held reference would not throw `StateError`.
