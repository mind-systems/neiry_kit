# Code Review: Handle unknown NeiryDeviceMode codes from Android SDK

Plan: `.ai-factory/plans/55-handle-unknown-neirydevicemode-codes-from-android-sdk.md`

## Scope

Three files changed:

- `lib/src/channel/enums.dart` — `NeiryDeviceMode.fromCode` becomes nullable; `NeiryDeviceType.fromCode` / `NeiryConnectionState.fromCode` left throwing as the plan dictated.
- `lib/src/api/device.dart` — adds `dart:developer` import, private `_loggedUnknownModeCodes` set on `Device`, and rebuilds `_modeChangedStream` as an inline broadcast pipeline that decodes, logs once per unknown code, then null-filters via `.where(...).cast<NeiryDeviceMode>()`.
- `test/channel_names_test.dart` — removes the now-stale `NeiryDeviceMode.fromCode(999) throws ArgumentError` assertion from the "throws" group; adds a new "returns null" group covering codes `7` and `999`. The `NeiryDeviceType` / `NeiryConnectionState` "throws" cases are preserved.

## Correctness verification

- **Nullable signature lands cleanly.** `lib/src/channel/enums.dart:64` now reads `static NeiryDeviceMode? fromCode(int code)` and returns `null` on no match. Dartdoc at lines 57–63 documents the new contract and the Android `Device_Status` rationale; the "Throws [ArgumentError]" line is gone. ✅
- **Sole non-test caller migrated.** Grep for `NeiryDeviceMode.fromCode` shows only `lib/src/api/device.dart:73` and `test/channel_names_test.dart` in source — both updated for the nullable return. No other Dart consumer needs follow-up. ✅
- **Stream pipeline types check.** `receiveBroadcastStream({...})` returns `Stream<dynamic>`; the explicit `.map<NeiryDeviceMode?>(...)` narrows to `Stream<NeiryDeviceMode?>`; `.where((mode) => mode != null)` keeps that element type but filters; `.cast<NeiryDeviceMode>()` narrows the static type to `Stream<NeiryDeviceMode>`, matching the field declaration and the public getter. ✅
- **Broadcast semantics preserved.** `Stream.map`/`where`/`cast` all forward `isBroadcast` from the source. The downstream listener in `_startStateTracking` at `device.dart:145-147` and the public `modeChangedStream` getter at `device.dart:246-249` remain valid. ✅
- **Pre-existing api_test still green.** `test/api_test.dart:227-232` asserts `Device(serial: 'test').modeChangedStream is Stream<NeiryDeviceMode>`. The outer stream type is unchanged, so this passes without modification. ✅
- **One-log-per-unknown-code gate is correct.** `Set<int>.add` returns `true` iff the value was newly inserted, so `mode == null && _loggedUnknownModeCodes.add(code)` runs the `log()` call exactly once per distinct unknown `code` per `Device` instance. Short-circuiting also avoids inserting unknown codes into the set when `mode != null` (which can't happen on the same branch, but the conjunction is still well-formed). ✅
- **`late final` initializer using `this`.** Dart evaluates `late final` instance initializers lazily on first access, so the closure's reference to `_loggedUnknownModeCodes` is safe; both fields are declared on the same `Device` instance. ✅
- **Sentinel `_mode` state.** `Device._mode` is `NeiryDeviceMode?` (already null-tolerant), and the listener at `device.dart:145-147` only sees decoded non-null values now — no change in observable state. ✅
- **Test layout.** `test/channel_names_test.dart:285-299` splits the assertion correctly: `NeiryDeviceType.fromCode(999)` and `NeiryConnectionState.fromCode(999)` remain in the `throwsArgumentError` group; `NeiryDeviceMode.fromCode(7)` and `NeiryDeviceMode.fromCode(999)` are in a new `returns null` group. The round-trip group at lines 268–272 (`NeiryDeviceMode.fromCode(v.code) == v` for every enum value) is unaffected because all `v.code` values still map back. ✅

## Findings

### 1. `dart:developer` imported unqualified — minor risk of symbol collision (style only)

`lib/src/api/device.dart:2` does `import 'dart:developer';` (no prefix), so the `log(...)` call at line 75 resolves to `developer.log`. The plan's example wrote `developer.log(...)` and implied an aliased import (`as developer`). Both are functionally identical here — there is currently no `log` symbol elsewhere in this file's import set (no `dart:math`, no `package:logger`, etc.) — so nothing is shadowed today.

Risk is purely future-facing: `dart:math` also exports `log(double)`. If a later edit adds `import 'dart:math';` for some unrelated numeric work, both libraries will bring `log` into scope and Dart will error with an ambiguous-import message. Trivial to fix when it happens.

Suggestion (non-blocking): change to `import 'dart:developer' as developer;` and call `developer.log(...)` to match the plan and pre-empt the collision. Either form is acceptable.

### 2. `_loggedUnknownModeCodes` survives `disconnect()`+`connect()` on the same `Device` instance

The set is initialised at field-init time and only released when the `Device` is garbage-collected. `Device.disconnect()` (`device.dart:182-193`) and `Device.dispose()` (`device.dart:222-235`) do not reset it; `connect()` doesn't either.

Effect: if a caller reuses one `Device` across multiple connection cycles, the second connection's burst of unknown codes (e.g. another `7`) will be silently dropped without a fresh log line. The plan review's positive note assumed "a reconnect produces a fresh `Device`," but nothing in the public API enforces that — `Device.connect()` can be called again after `disconnect()`.

This is intentional per the plan ("logged exactly once per `Device` instance — repeated `7`s during a single connection do not spam the log") and not a defect. Flag only so the implementer / future reader is aware that the diagnostic granularity is coarser than per-connection.

Optional improvement (non-blocking): clear `_loggedUnknownModeCodes` inside `disconnect()` so each connection cycle gets one fresh log per code. Trade-off: marginally more log noise across long-running sessions that flap connections. Either choice is defensible; current behaviour matches the plan literally.

## Non-findings (verified clean)

- Map cast `(raw as Map<Object?, Object?>)['mode'] as int` is unchanged from the pre-existing `_eventStream` shape (`device.dart:127-134`); native side delivers the same payload — no new failure mode.
- The `Set<int>` is bounded by the (small) number of distinct undocumented codes the SDK can emit; no unbounded growth concern.
- No security implications: log payload is a numeric SDK-internal status code, not user data.
- No threading concern: stream callbacks for a given subscription are delivered serially, so the `Set.add` gate doesn't race with itself.
- No migration required (Dart-only change, no native bridge or proto contract touched). ARCHITECTURE.md boundary unchanged: `enums.dart` and `device.dart` are both inside the Dart channel/API layer.

## Verdict

Implementation matches the plan, fixes the stated bug (crash on undocumented Android `Device_Status` code `7`), preserves the public stream contract, and updates the only test that the contract change breaks. The two findings above are stylistic / defensive notes, not defects.

REVIEW_PASS
