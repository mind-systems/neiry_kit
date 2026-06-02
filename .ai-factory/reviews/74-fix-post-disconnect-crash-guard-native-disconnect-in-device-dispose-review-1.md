# Code Review: Fix post-disconnect crash — guard native disconnect in Device.dispose()

**Scope reviewed:** `git diff HEAD` (staged) — `lib/src/api/device.dart`, `ios/Classes/DeviceBridge.swift`, plus `.ai-factory/` docs.
**Verdict:** ❌ Changes requested — one build-breaking bug.

## 🔴 Blocking

### 1. Removed `dart:developer` import breaks the build — `log()` is still used

`lib/src/api/device.dart:2` deletes `import 'dart:developer';`:

```diff
 import 'dart:async';
-import 'dart:developer';
```

But `log(...)` is still called in the `_modeChangedStream` decoder at `lib/src/api/device.dart:74`:

```dart
if (mode == null && _loggedUnknownModeCodes.add(code)) {
  log(
    'Ignoring unknown NeiryDeviceMode code $code from native SDK',
    name: 'neiry_kit',
  );
}
```

`log` comes only from `dart:developer`; none of the remaining imports (`dart:async`, `package:flutter/services.dart`, the local channel/model files) export it. With the import gone, `flutter analyze` / compilation fails with `The function 'log' isn't defined` and the package will not build.

This change is also **out of scope** — the plan (Task 1) covers only the `if (_connected)` guard in `dispose()`. The import removal was an unrelated edit (likely a mistaken "unused import" cleanup that missed the line-74 usage).

**Fix:** restore `import 'dart:developer';`.

## 🟢 Correct — the actual planned fix

The core change in `dispose()` (`lib/src/api/device.dart:225-233`) is correct and matches the plan and spec:

- The native `DeviceMethods.disconnect` call is now guarded by `if (_connected)`, so when `disconnect()` already ran (which sets `_connected = false` at line 188), the second native disconnect is skipped — eliminating the double-teardown that crashed `libCapsuleClient.so`.
- The sole-teardown path is preserved: calling `dispose()` directly on a still-connected device keeps `_connected == true`, so the native disconnect still runs exactly once.
- The unconditional state resets after the guard (`_started`, `_connected`, `_connectionState`, `_mode`, `_battery`) are retained, so the object is still fully locked down regardless of which branch ran.
- The misleading "Idempotent on the native side" comment is replaced with the accurate rationale.

No regression in the connect-failure path (`connect()` sets `_connected = true` only after the native call succeeds, so a failed connect leaves `_connected == false` and the guarded call is correctly skipped). The existing `dispose()` test asserts only post-dispose `StateError` behavior, which is driven by `_disposed` and is untouched.

## 🟡 Minor / out of scope

### 2. `ios/Classes/DeviceBridge.swift` — unexplained, out-of-scope reordering

The diff moves the `clCDevice_SetOnErrorEvent` registration from before the connection/mode callbacks to after them (lines 374-378). Each `clCDevice_SetOn*Event` sets an independent callback, so registration order has no behavioral effect — this is a functional no-op. It is, however, unrelated to the stated task (which is Dart-only) and adds noise to the diff. Not blocking; consider dropping it from this change to keep the fix focused, or note why it was made.

### 3. `disconnect()` itself remains unguarded (acceptable)

A direct double `disconnect()` (without `dispose()`) would still invoke the native call twice. This is outside the reported crash path (`disconnect()` → `dispose()`) and outside the plan's scope, so leaving it is acceptable — noting for awareness only.

---

Summary: the intended one-line guard is implemented correctly, but the accidental removal of the `dart:developer` import makes the package fail to compile. Restore that import and the change is good to ship.
