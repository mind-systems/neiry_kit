# Plan review: Handle unknown NeiryDeviceMode codes from Android SDK

**Plan:** `.ai-factory/plans/55-handle-unknown-neirydevicemode-codes-from-android-sdk.md`
**Risk Level:** 🟢 Low

## Context Gates

- **ARCHITECTURE.md:** not present in `.ai-factory/`. No boundary violations to flag — the change stays inside `lib/src/channel/enums.dart` and `lib/src/api/device.dart`, both already part of the public Dart-facing API surface.
- **RULES.md:** not present in `.ai-factory/`. No explicit project-level rules to check against.
- **ROADMAP.md:** not consulted as a blocking gate; plan is a defensive bugfix triggered by an observed runtime crash.

WARN: the three optional context files (`ARCHITECTURE.md`, `RULES.md`, `ROADMAP.md`) are absent from `.ai-factory/`. Non-blocking.

## Verification of plan claims against the codebase

| Plan claim | Verified |
|---|---|
| `NeiryDeviceMode.fromCode` at `lib/src/channel/enums.dart:60–65` throws `ArgumentError` | ✓ matches file |
| Dartdoc to update is at lines 57–59 | ✓ |
| `Device` class defined at `lib/src/api/device.dart:31` (no `_NeiryDevice` symbol exists) | ✓ |
| `_modeChangedStream` lives at lines 65–68 | ✓ |
| State listener for mode at lines 130–132 | ✓ |
| Public `modeChangedStream` getter at line 231 | ✓ |
| `dart:developer` is NOT currently imported in `device.dart` | ✓ — current imports are `dart:async`, `package:flutter/services.dart`, and local files only |
| Test group `'fromCode throws ArgumentError for unknown codes'` at `test/channel_names_test.dart:285–294`, with `NeiryDeviceMode.fromCode(999)` at lines 288–289 | ✓ |
| No other test file references `NeiryDeviceMode.fromCode` | ✓ (grep clean) |
| Native side sends a `Map` with `"mode"` int via `on_mode_switched` in `android/src/main/cpp/jni_device.cpp:729` | ✓ — matches `(raw as Map<Object?, Object?>)['mode'] as int` cast |

## Architectural notes

- **Null-filtering on a broadcast stream:** the proposed pipeline (`receiveBroadcastStream → map<NeiryDeviceMode?> → where → cast<NeiryDeviceMode>`) is correct. `Stream.map`, `where`, and `cast` preserve broadcast semantics, so the resulting `Stream<NeiryDeviceMode>` remains usable from multiple subscribers — same contract the existing `_eventStream` helper provides.
- **`late final` initializer referencing `this`:** the inline pipeline references `_loggedUnknownModeCodes` from the initializer. This is fine in Dart — `late final` initializers run lazily on first access, after the constructor body, so `this` and instance fields are available.
- **Whereabouts of the `whereType` warning:** the plan's reminder that `Stream` does not expose `whereType<T>()` (it's only on `Iterable`) is technically accurate and pre-empts a likely implementation mistake. The substitute `.where(...).cast<NeiryDeviceMode>()` is the canonical fix.
- **Scope discipline:** plan correctly limits the nullable contract to `NeiryDeviceMode.fromCode` only. `NeiryDeviceType.fromCode` is called from `DeviceLocator.requestDevices`/`createDevice` paths (Dart→native input), and `NeiryConnectionState.fromCode` from the connection state stream, where an unknown code really is a contract violation. Keeping them throwing is the right call.
- **One-time-log gating via `Set.add` return value:** standard idiom; per-`Device`-instance scoping is appropriate (a new connection cycle on a new `Device` will re-log, which is desirable for observability).
- **Side effect in `map` callback:** mixing the diagnostic log into `.map` rather than `.listen` is acceptable here because the stream is single-pass per subscription and the closure has no other observable side effect; the public stream type and getter contract stay identical.

## Issues / gaps

None found. The plan:
- specifies exact file paths, line ranges, and the symbol to leave alone (`NeiryDeviceType`/`NeiryConnectionState`);
- spells out the import to add (`dart:developer`);
- gives a working code shape with the correct types and broadcast-friendly operators;
- updates the only impacted test, splitting "still throws" cases from the new "returns null" assertions;
- explicitly forbids the tempting alternative (adding `unknown7(7)` to the enum), which would leak undocumented SDK internals into the public API.

No migration concerns, no security implications, no performance impact (single `Set<int>` lookup per mode event, bounded by the small number of possible undocumented codes).

## Positive notes

- Treats the unknown code as transient noise at the boundary instead of leaking it upward — correct layer for the fix.
- Explicit per-instance log de-duplication prevents log spam during the GATT-discovery burst that motivated the bug report.
- Test update preserves the "throws for unknown" contract for the two enums where it still applies, preventing accidental regression.

PLAN_REVIEW_PASS
