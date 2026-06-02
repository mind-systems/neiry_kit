# Code Review (2): Fix post-disconnect crash — guard native disconnect in Device.dispose()

**Scope reviewed:** `git diff HEAD` (staged) — `lib/src/api/device.dart`, `ios/Classes/DeviceBridge.swift`.
**Verdict:** ✅ Approved.

## Review-1 blocking issue — resolved

Review-1 flagged that `import 'dart:developer';` had been deleted while `log(...)` was still called at `lib/src/api/device.dart:74`, which would break the build. That import is now present at `lib/src/api/device.dart:2`, and the `log(...)` usage in the `_modeChangedStream` decoder resolves correctly. The package compiles. ✅

## Core fix — correct

The `dispose()` change (`lib/src/api/device.dart:225-233`) matches the plan and spec:

- The native `DeviceMethods.disconnect` call is guarded by `if (_connected)`. Since `disconnect()` sets `_connected = false` (line 188) before returning, the `disconnect()` → `dispose()` sequence in `NeiryService` now issues the native disconnect exactly once, eliminating the double-teardown that crashed `libCapsuleClient.so` with `Fatal signal 64`.
- The sole-teardown path is preserved: `dispose()` on a still-connected device keeps `_connected == true`, so the native disconnect still runs once.
- Connect-failure path is safe: `connect()` sets `_connected = true` only after the native call succeeds, so a failed connect leaves `_connected == false` and the guarded call is correctly skipped.
- The unconditional state resets after the guard are retained, so the disposed object stays fully locked down regardless of branch taken.
- The misleading "Idempotent on the native side" comment is replaced with an accurate rationale.

## Minor / non-blocking

**`ios/Classes/DeviceBridge.swift`** — the `clCDevice_SetOnErrorEvent` registration is reordered to after the connection/mode callbacks (lines 374-378). Each `clCDevice_SetOn*Event` installs an independent callback, so registration order has no behavioral effect — this is a functional no-op. It is unrelated to the Dart-only task scope and adds diff noise, but introduces no bug. No action required.

No correctness, runtime, or security problems found.

REVIEW_PASS
