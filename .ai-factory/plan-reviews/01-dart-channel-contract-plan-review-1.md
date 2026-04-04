## Plan Review: Dart Channel Contract

**Plan file:** `.ai-factory/plans/01-dart-channel-contract.md`
**Files reviewed:** Plan + spec note + ARCHITECTURE.md + ROADMAP.md + SDK headers + all existing lib/ and test/ files
**Risk Level:** 🟡 Medium

### Context Gates

- **Architecture:** WARN — Plan uses `NeiryChannels` / `NeiryEvents` separation (multiple `abstract final class` containers) instead of the single flat `ChannelNames` example in ARCHITECTURE.md. This is actually an improvement — the architecture example was illustrative, and the plan's separation is cleaner. No conflict with the dependency rules (`lib/src/channel/ → nothing`). File path `lib/src/channel/channel_names.dart` matches architecture folder structure.
- **Rules:** No `.ai-factory/RULES.md` present — WARN (non-blocking).
- **Roadmap:** WARN — Three discrepancies between roadmap milestone description and plan (detailed below in issues #1, #2, #3).

### Issues

**1. Existing tests will break — not addressed by the plan**

Task 5 replaces `lib/neiry_kit.dart` contents, removing the `NeiryKit` class. But `test/neiry_kit_test.dart` imports `package:neiry_kit/neiry_kit.dart` and instantiates `NeiryKit()` (line 22). After the barrel change, this test will fail to compile.

`test/neiry_kit_method_channel_test.dart` only imports `package:neiry_kit/neiry_kit_method_channel.dart` directly — it will still compile since that file stays on disk.

**Fix:** Add a step to Task 5 (or a new Task 5b): delete `test/neiry_kit_test.dart` and `test/neiry_kit_method_channel_test.dart` (both are scaffolding tests for the removed `getPlatformVersion` flow). The new `test/channel_names_test.dart` from Task 6 replaces them. Alternatively, strip the old tests down to only import the platform interface files directly (no barrel import, no `NeiryKit` usage).

**2. EventChannel count: roadmap says 28, spec lists 26, plan lists 26**

The spec note explicitly enumerates 26 EventChannel IDs. The plan correctly lists these same 26 but then hedges with "the milestone says 28 which may account for future additions — match the spec file exactly and document the count." The roadmap milestone also says "22 EventChannels" in the iOS bridges section, creating a third conflicting number.

**Fix:** The plan should state the count as 26 (matching the spec) and note that the roadmap milestone description needs a correction from 28 → 26. Don't pad to 28 with placeholders — that introduces dead constants with no native counterpart.

**3. File path mismatch with roadmap**

Roadmap milestone says `lib/src/channel_names.dart` (flat in `src/`). Plan says `lib/src/channel/channel_names.dart` (inside `channel/` subdirectory). The plan follows ARCHITECTURE.md's folder structure, which is the correct authority. The roadmap description should be updated to match.

**Fix:** Not a plan fix — the roadmap milestone text is the one that's slightly off. The plan's path is correct per architecture. Just note this so the implementer doesn't get confused.

**4. Device mode enum: spec note uncertainty is resolved, but plan should drop the open question**

The spec note flags "Start/StopPPG indices conflict in different docs" as an open question. The SDK header `CDevice.h` confirms `StartPPG=5, StopPPG=6` — no conflict. The plan uses these correct values. However, the plan doesn't explicitly call out that this open question from the spec is now resolved.

Not blocking — just a documentation clarity point.

**5. Test collection of class constants requires manual enumeration**

Task 6 says "collect all `NeiryChannels` values into a `List<String>`" — Dart has no runtime reflection in Flutter, so the test must manually enumerate every constant. With 26 event channels + 8 method channels + ~25 method names + 11 arg keys, that's ~70 constants to list manually in the test. If a new constant is added to the class but not to the test list, the uniqueness check won't cover it.

This is inherent to Dart — no fix needed, but the implementer should be aware. Consider adding a comment in the test file noting that new constants must be added to the test lists manually.

### Suggestions

**6. Consider splitting enums into a separate file**

Task 4 puts three enums (`NeiryDeviceType`, `NeiryDeviceMode`, `NeiryConnectionState`) into `channel_names.dart` alongside string constants. These enums are semantically different — they're data types, not channel contract strings. The architecture shows `channel_names.dart` for "Constants: channel IDs, method names, event channel IDs." Enums with `fromCode` factories are richer types.

A cleaner split: `channel_names.dart` for all string constants, `enums.dart` for the three enums. Both exported from the barrel. This keeps each file focused and makes `channel_names.dart` pure string constants (easy to audit for the uniqueness invariant).

Not blocking — single file works fine at this scale.

**7. `fromCode` could use `firstWhere` instead of throwing raw `ArgumentError`**

The plan specifies `fromCode` throws `ArgumentError` for unknown codes. Consider whether a custom exception or at least a descriptive message (`'Unknown NeiryDeviceType code: $code'`) would be more debuggable when a native bridge sends an unexpected int. The implementer should include the code value in the error message.

**8. Spec note `cardio` channel and `cardioCalibratedEvent` need native-side confirmation**

The spec note flags: "Cardio channel ID for calibration — docs show `cardioCalibratedEvent` but exact channel name needs confirmation from `_c_cardio_8h`." The plan includes it without resolving this. If the native C API doesn't have a cardio calibration callback, this EventChannel ID will be dead code.

Low risk for this milestone (we're just defining strings), but the implementer of the iOS/Android bridges will need to verify.

### Positive Notes

- The plan correctly follows ARCHITECTURE.md's folder structure and layering rules.
- Separating channels, events, methods, and args into distinct `abstract final class` containers is cleaner than the architecture's illustrative flat example.
- Enhanced enum pattern with `code` field and `fromCode` is idiomatic Dart 3.
- Test coverage is thorough — uniqueness, round-trips, and invalid input.
- Commit plan is sensible: contract first, tests second.
- The plan correctly resolves the device mode PPG index uncertainty from the spec note.
