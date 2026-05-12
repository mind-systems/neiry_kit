# Plan Review: 56-fix-module-already-exists-crash-when-toggling-use-nfb-calibration (v2)

**Plan file:** `.ai-factory/plans/56-fix-module-already-exists-crash-when-toggling-use-nfb-calibration.md`
**Files Reviewed:** plan + 9 source files (`productivity_cardio_screen.dart`, `mems_screen.dart`, `device_state_providers.dart`, `productivity_classifier_provider.dart`, `cardio_classifier_provider.dart`, `mems_classifier_provider.dart`, `productivity_classifier.dart`, `jni_productivity.cpp`, `jni_cardio.cpp`, `jni_mems.cpp`, `CError.h`, `nfb_calibration_provider.dart`, `calibration_provider.dart`)
**Risk Level:** 🟡 Medium — diagnosis is now correct and the chosen strategy is SDK-legal, but one residual code path can still reach the same SIGABRT, and several smaller details in the JNI task are under-specified.

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`):** present. No module boundaries are crossed by the fix; all changes stay within the example app, the plugin's Dart `ProductivityClassifier`, and the Android JNI. PASS.
- **Rules (`.ai-factory/RULES.md`):** not present. SKIP.
- **Roadmap (`.ai-factory/ROADMAP.md`):** present. Task 56 is listed under MEMS-tab follow-ups. The roadmap entry still describes the *previous* (rejected) dispose-before-create strategy; that's not a blocker for the plan, but the entry will read as stale once this fix lands. WARN — non-blocking.
- **Skill-context (`.ai-factory/skill-context/`):** not present. SKIP.

## Critical Issues

### 1. `nfbCalibrationProvider` is still a `ref.watch` dependency — the crash trigger is not fully removed

The plan's stated strategy is: "removes the trigger that fires the second `_Create`." But it only removes **one** trigger (the `useCalibrationToggleProvider`). The three classifier notifiers also `ref.watch(nfbCalibrationProvider)`:

- `example/lib/providers/productivity_classifier_provider.dart:31`
- `example/lib/providers/cardio_classifier_provider.dart:23`
- `example/lib/providers/mems_classifier_provider.dart:30`

`nfbCalibrationProvider` is mutated by `CalibrationNotifier`:

- `calibration_provider.dart:121` (`importFromFile`)
- `calibration_provider.dart:141` (`_writeToSharedProvider`, called from `startFull`/`startQuick`)

After the fix, the user can still:

1. Connect device → start streaming (toggle is now locked, classifiers are alive).
2. Navigate to the Calibration tab → import calibration from file, **or** run `startQuick`.
3. `nfbCalibrationProvider` mutates → all three classifier notifiers rebuild → second `clCProductivity_Create` / `clCCardio_CreateCalibrated` / `clCMEMS_CreateCalibrated` on the same device → **same SIGABRT**.

The plan's acceptance criterion targets only "Toggling the switch before start" — so this scenario won't be caught by the documented manual repro. But the title of the task ("Fix 'module already exists' crash") implies fixing the underlying lifecycle bug, not just one trigger. Three reasonable options:

- **(a)** Switch the three classifier providers from `ref.watch(nfbCalibrationProvider)` to `ref.read(nfbCalibrationProvider)`, matching the pattern already used in `nfb_classifier_provider.dart:22`. This makes calibration changes take effect only on next `Device.start()` — symmetric with the toggle lock.
- **(b)** Disable the Calibration tab's "Import from file" / "Start" buttons while `deviceUiStateProvider == DeviceUiState.started`.
- **(c)** Explicitly scope the plan as "fix the toggle-triggered crash only; the calibration-import-triggered path is tracked separately" and add a follow-up roadmap entry.

Option (a) is the smallest correct change and is internally consistent with the plan's own reasoning ("classifier is created on `Start` and destroyed on `Stop`"). The plan should pick one; as written, the fix is incomplete relative to its own framing.

### 2. Task 3 — `clCError` construction is under-specified and the chosen error code is wrong-shape

`clCError` in `official/iOS/CapsuleClient.framework/Headers/CError.h:28-32` is:

```c
typedef struct clCError {
    char message[256];
    bool success;
    clCError_Code code;
} clCError;
```

Two issues with the task:

**2a.** The plan says "build a `clCError` with … message `"clCProductivity_CreateWithIndividualData is not exported by the Android Capsule AAR"`". `message` is a fixed-size `char[256]` buffer, not a pointer — the implementer cannot write `error.message = "..."`. The task should specify a `snprintf(error.message, sizeof(error.message), "...")` (the same idiom `throw_sdk_error` uses) so the string is copied into the buffer. Without this hint the implementer is likely to attempt assignment and fail to compile.

**2b.** The plan recommends code `255` (which is `clCError_Unknown` in the SDK enum). The same header defines `clCError_ModuleIsNotSupported` (line 18) — semantically the exact right code for "this symbol is not supported by this build of the SDK." Using `clCError_Unknown` works for the throw path but communicates the wrong intent on the Kotlin side, especially if downstream code ever decides to switch on the code. Recommend `clCError_ModuleIsNotSupported` (value `9` based on enum order) unless there's a deliberate reason to prefer `255`; the plan's stated reason ("matches the existing `255|Unknown error` convention") is weak — that convention is for genuinely unknown errors, not for known-unsupported ones.

Neither sub-issue blocks the fix from working, but both will surface in code review and 2a is a real implementation hazard.

## Other Issues

### 3. Task 5's silent fallback contradicts the acceptance criterion's "explanatory subtitle" requirement on Android

The acceptance criterion (line 18) says:

> "The example app must not enable the calibrated-Productivity path on Android (toggle hidden or shown as disabled with an explanatory subtitle)."

Task 5's implementation is: keep the shared toggle visible and enabled, and in `ProductivityClassifierNotifier.build()` catch `UnsupportedError` and fall back to plain `ProductivityClassifier(device)` with a `debugPrint`.

That satisfies "not enabling the calibrated-Productivity path" but does **not** satisfy "explanatory subtitle." The user toggles the switch on Android, both Productivity and Cardio classifiers are recreated on next `Start`, Cardio gets calibration, Productivity silently doesn't — and the user has no UI signal that one side dropped the request. Worse, the `debugPrint` only fires the first time the provider builds, so the regression is only visible in the device console, not on screen.

Either:

- Drop the "explanatory subtitle" wording from the acceptance criterion (accept the silent fallback as the intentional design), or
- Add an Android-only line under the Productivity card (not the toggle) along the lines of "Individual NFB calibration not available for Productivity on Android" rendered whenever `Platform.isAndroid && useCalibration && nfbData != null`.

Pick one — as written, Task 5 implements the silent-fallback option but the acceptance criterion describes the subtitle option. The implementer should not have to guess which the reviewer cares about.

### 4. Task 5 — missing `debugPrint` import

Task 5 says "Log a single line via `debugPrint`." `productivity_classifier_provider.dart` currently imports `flutter_riverpod`, `flutter_riverpod/legacy`, and `neiry_kit`. `debugPrint` lives in `package:flutter/foundation.dart` (or transitively via `package:flutter/material.dart`); neither is imported. Trivial fix, but the task should call it out so the implementer doesn't paste the line and ship a broken build.

### 5. Task 5's try/catch wrap is broader than needed

The task says "wrap the `ProductivityClassifier.withCalibration(device, nfbData)` call in a `try`". A direct reading risks wrapping the whole `if (useCalibration && nfbData != null) { … } else { … }` block. The safer, more local pattern is:

```dart
final ProductivityClassifier classifier;
if (useCalibration && nfbData != null) {
  try {
    classifier = ProductivityClassifier.withCalibration(device, nfbData);
  } on UnsupportedError {
    debugPrint('ProductivityClassifier.withCalibration unsupported; falling back to plain factory');
    classifier = ProductivityClassifier(device);
  }
} else {
  classifier = ProductivityClassifier(device);
}
```

The plan should spell out this shape to prevent over-wrapping the `else` branch in the same `try`. Minor — the implementer can probably figure it out — but the plan tries hard to be prescriptive elsewhere; this should match.

### 6. iOS UX is silently regressed without acknowledgement

Tasks 1 and 2 disable the toggle on **all** platforms while `isStarted`. The plan's Context acknowledges "iOS appears to tolerate the second `Create` silently" — meaning iOS users currently *can* hot-swap calibration mid-stream, and after this change they no longer can. This is a defensible UX choice (uniformity, respect the SDK's documented lifecycle even when one platform happens to forgive violations), but the plan doesn't acknowledge it as a deliberate iOS regression. Add one sentence to the Context: "On iOS the toggle currently works mid-stream; this change disables it on both platforms for behavioural consistency with the SDK lifecycle contract." Otherwise a future reader (or a future bug report from an iOS-only beta tester) will read this as an oversight.

### 7. The `clCIndividualNFBData` setup block in Task 3 is dead-coded but the task says "remove"

`jni_productivity.cpp:84-97` builds a `clCIndividualNFBData` struct from the JNI args. Task 3 says to "remove the silent-fallback `clCProductivity_Create(dev, &error)` call and the surrounding setup of `clCIndividualNFBData`." That's correct — but worth being explicit: the parameters `ts, failReason, individualFrequency, …, upperFrequency` will be ignored by the new stub. The JNI signature stays so Kotlin doesn't re-bind, but suppress the unused-parameter warning if the project's `-Werror` config flags it. A trivial `(void)ts; (void)failReason; …` block (or just `[[maybe_unused]]` on each param in the signature) keeps the build clean. The plan should call this out; otherwise the implementer may land a build-warning-as-error regression.

### 8. The TODO comment is verbose where a single-line marker would do

Task 3 specifies a multi-line `TODO` explaining when to restore the original code path "from git history." That's reasonable, but combined with the plan-required explicit-error semantics it makes the JNI function ~6 lines of code + 8 lines of comment. Prefer a one-line `// TODO(neiry-aar): restore _CreateWithIndividualData path when AAR exports it.` Anything longer belongs in a tracking issue, not the source. Stylistic, non-blocking.

### 9. Manual repro covers the happy path but not the failure case from issue 1

The acceptance criterion describes:

- toggle disabled while started ✓
- toggling **before** start then starting must not crash ✓
- Android `withCalibration` must throw `UnsupportedError` ✓

It does **not** describe what happens if the user imports calibration **while** the device is started. Per issue 1 above, that scenario reproduces the original SIGABRT. Either:

- Add a repro step: "Start streaming → navigate to Calibration tab → Import calibration from file. The app must not SIGABRT and the Productivity/Cardio/MEMS streams must continue emitting." — and ensure the plan fixes this path; **or**
- Add: "Importing calibration while the device is started is not exercised by this task and may still crash; see follow-up #XX." — at least the constraint is documented.

The current criterion as written can pass with the crash still latent.

## Positive Notes

- The new Context section is correct: it accurately identifies that no `_Destroy` exists for `clCProductivity` / `clCCardio` / `clCMEMS`, that the bridge's `dispose` is callback-unhook only, and that the SDK aborts on a second `_Create`. This is a complete reversal from the v1 diagnosis and matches the v1 reviewer's analysis.
- The "UX gate" strategy (Tasks 1–2) is the cheapest correct fix — it respects the SDK's "classifier is owned by Device for the duration of streaming" lifecycle without requiring an SDK-level destroy that doesn't exist.
- Task 3 correctly identifies that the existing silent fallback is a feature lie on Android and replaces it with an explicit error — exactly what review v1 issue #5 asked for.
- Task 4's Dart-side `Platform.isAndroid` guard is the right place to surface the missing-symbol limitation to API consumers, since the JNI throw lands as a generic `PlatformException` and `UnsupportedError` is the canonical Dart shape for this.
- File paths and line references are accurate: `productivity_classifier.dart:69` is indeed the `withCalibration` factory, `jni_productivity.cpp:70–114` is indeed `nativeCreateProductivityWithIndividualData`, and `useMemsCalibrationToggleProvider` exists at `mems_classifier_provider.dart:14`.
- The plan correctly notes that Cardio and MEMS have real `_CreateCalibrated` symbols on Android via `clCNFBCalibrator_CreateOrGet` (verified in `jni_cardio.cpp:117` and `jni_mems.cpp:104`) and are unaffected by Task 3.
- The plan adds the manual acceptance criterion that v1's review explicitly requested.

## Suggested Changes Before Implementation

1. **Resolve issue 1** — either switch the three classifier providers' `ref.watch(nfbCalibrationProvider)` to `ref.read`, or explicitly scope the calibration-import path out of this task with a follow-up roadmap entry. As-is, the title's promise ("Fix 'module already exists' crash") is only partially kept.
2. **Fix Task 3 underspecification** — add the `snprintf(error.message, sizeof(error.message), "...")` idiom, switch to `clCError_ModuleIsNotSupported` (or justify keeping `255`), and add `[[maybe_unused]]`/`(void)param;` for the now-ignored JNI parameters.
3. **Resolve the acceptance-criterion/Task-5 mismatch** — pick "silent fallback" or "explanatory subtitle" and update both sides to match.
4. **Add the missing `debugPrint` import note to Task 5.**
5. **Spell out the try/catch shape in Task 5** so the implementer doesn't wrap the `else` branch.
6. **Add one sentence to Context** acknowledging that the toggle lock is a deliberate iOS UX regression for behavioural symmetry.
7. **Either extend or scope-limit the manual repro** to cover (or explicitly defer) the calibration-import-while-started path.

Once issues 1–3 are addressed the plan is ready to implement; the rest are quality-of-life improvements that will save the reviewer of the resulting patch a round-trip.
