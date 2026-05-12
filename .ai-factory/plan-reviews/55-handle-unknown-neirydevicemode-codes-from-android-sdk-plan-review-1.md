# Plan Review: Handle unknown NeiryDeviceMode codes from Android SDK

**Plan:** `.ai-factory/plans/55-handle-unknown-neirydevicemode-codes-from-android-sdk.md`
**Risk Level:** 🟡 Medium — one concrete blocker (broken pre-existing test), otherwise sound.

## Context Gates

- **ARCHITECTURE.md:** ✅ Aligned. Touches only `lib/src/channel/enums.dart` and `lib/src/api/device.dart` — both are inside the Dart API layer (`lib/src/api/` → `lib/src/channel/`), no cross-layer breaches.
- **RULES.md:** N/A (file not present in repo).
- **ROADMAP.md:** ✅ Linked. The roadmap entry on line 76 ("Handle unknown NeiryDeviceMode codes from Android SDK") matches the plan's intent. Note the roadmap text proposes `.whereType<NeiryDeviceMode>()` after `.map(fromCode)`; the plan instead uses an inline `.where(!= null).cast<NeiryDeviceMode>()` pipeline. Both are semantically equivalent and the plan's choice is a refinement, not a contradiction.

## Codebase Verification

| Plan reference | Actual | Verdict |
|---|---|---|
| `enums.dart` lines 60–65: `NeiryDeviceMode.fromCode` body | Confirmed (`lib/src/channel/enums.dart:60-65`) | ✅ |
| `enums.dart` lines 57–59: dartdoc with "Throws [ArgumentError]" | Confirmed | ✅ |
| `device.dart` lines 65–68: `_modeChangedStream` via `_eventStream` | Confirmed | ✅ |
| `device.dart` line 231: `modeChangedStream` getter | Confirmed (lines 231–234) | ✅ |
| `device.dart` lines 130–132: `_modeChangedStream` listener in `_startStateTracking` | Confirmed | ✅ |
| `_eventStream<T>` is generic, no `null` filtering | Confirmed (lines 112–119) | ✅ |
| `NeiryDeviceType.fromCode` / `NeiryConnectionState.fromCode` should stay throwing | Reasonable — those values originate on the Dart→native and create-device flows where unknown codes indicate a real bug, not transient noise | ✅ |

The only Dart consumer of `NeiryDeviceMode.fromCode` is `device.dart:67`, so changing the return type to nullable does not create unhandled `null`s anywhere else in `lib/`. ✅

## Critical Issues

### 1. Pre-existing test will break — not addressed by the plan
`test/channel_names_test.dart:288-289` contains:

```dart
test('NeiryDeviceMode.fromCode(999)',
    () => expect(() => NeiryDeviceMode.fromCode(999), throwsArgumentError));
```

After Task 1, `NeiryDeviceMode.fromCode(999)` will return `null` instead of throwing — this test will fail. The plan says "Testing: no" (meaning no *new* tests), but pre-existing test maintenance is still required, otherwise `flutter test` breaks and CI/verification fails.

**Required addition:** a Task 3 (or an addendum to Task 1) that updates the test in `test/channel_names_test.dart`:

- Remove the `NeiryDeviceMode.fromCode(999)` case from the `fromCode throws ArgumentError for unknown codes` group (the `NeiryDeviceType` and `NeiryConnectionState` cases must stay — those remain throwing per Task 1).
- Add a replacement assertion in the appropriate group (e.g. a new `NeiryDeviceMode.fromCode returns null for unknown codes` group) asserting `expect(NeiryDeviceMode.fromCode(7), isNull)` and `expect(NeiryDeviceMode.fromCode(999), isNull)`.

Without this, the milestone cannot pass verification even though the production code is correct.

## Suggestions (non-blocking)

### 2. Plan "Settings" say `Logging: minimal` but no logging is specified
The plan's task body explicitly says unknown codes are *silently* dropped — no log line. That contradicts the `Logging: minimal` flag. Either:

- Tighten the flag to `Logging: none` (matches the actual intent), **or**
- Add a one-time `developer.log()` (or `debugPrint`) inside the filter that records the first unknown code seen per `Device` instance (gated by a `Set<int>` so repeated 7s don't spam logs). This is genuinely valuable when the next Android SDK upgrade introduces yet another undocumented status code.

Recommend the second — it costs nothing and gives diagnostic visibility without spamming. The current "silent drop" makes future SDK regressions invisible.

### 3. Minor: `.whereType<NeiryDeviceMode>()` is more idiomatic than `.where(!= null).cast<>()`
Functionally equivalent but `.whereType<T>()` is single-call and the conventional Dart idiom for "filter out nulls and narrow the type." The plan's two-step `.where().cast()` works but is slightly noisier. Not worth blocking on — implementer can use either. Aligning with the roadmap's pre-existing wording (`.whereType<NeiryDeviceMode>()`) would also keep history consistent.

### 4. Minor: re-implementing the body of `_eventStream` inline is acceptable but could be a helper
The plan explicitly forbids a generic helper, which is fine for one call site. If a second nullable-decode stream appears in the future (e.g. another transient enum from the SDK), revisit and extract `_nullableEventStream<T>` then. No action now.

## Positive Notes

- ✅ Correctly identifies the root cause (Android AAR's internal `Device_Status` enum bleeding through the public `Mode` callback) and resists the temptation to add `unknown7(7)` placeholders that would lock in undocumented codes as part of the public API.
- ✅ Scopes the nullable change narrowly to `NeiryDeviceMode` — keeps `NeiryDeviceType` and `NeiryConnectionState` strict because those values come from controlled entry points where a surprise code *should* surface as an error.
- ✅ Calls out exactly which call sites consume the stream (`modeChangedStream` getter at 231, `_startStateTracking` listener at 130–132) and verifies the public `Stream<NeiryDeviceMode>` contract stays stable.
- ✅ File paths, line numbers, and surrounding context references are all accurate.
- ✅ Dependency between Task 1 and Task 2 is explicit.

## Summary

The plan is technically correct and architecturally clean, but **incomplete**: it does not address the unit test that asserts `NeiryDeviceMode.fromCode(999)` throws, which becomes a stale assertion the moment Task 1 lands. Add a test-update task before approving for implementation. Logging guidance should also be reconciled with the `Logging: minimal` setting.

After the test-update task is added, the plan is ready for implementation.
