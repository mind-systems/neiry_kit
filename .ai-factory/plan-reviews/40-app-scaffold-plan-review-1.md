## Plan Review: 40-app-scaffold

**Tasks Reviewed:** 5
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md:** WARN — screen file names in the plan differ from ARCHITECTURE.md's folder structure template (see Design Considerations below). Non-blocking; the plan's naming is more consistent with the actual tab labels.
- **RULES.md:** not present — skipped.
- **ROADMAP.md:** OK — plan maps 1:1 to the `app scaffold` milestone. Dependencies, tab count, provider type, and routing strategy all match.

### Critical Issues

None.

### Design Considerations

1. **Screen file naming vs ARCHITECTURE.md** — ARCHITECTURE.md defines `discovery_screen.dart` and `streaming_screen.dart`, but the plan creates `device_screen.dart` and `streams_screen.dart`. The plan's naming is more consistent with the tab labels ("Device", "Streams"), GoRouter paths (`/device`, `/streams`), and the exploration note. Either update ARCHITECTURE.md to match the plan's names during implementation, or rename in the plan. Non-blocking — the plan's naming is the better choice.

2. **NotifierProvider vs Provider for deviceLocatorProvider** (Task 4) — The plan specifies `NotifierProvider`, matching the ROADMAP milestone description. However, the exploration note (`notes/12-explore-example-navigation.md`) explicitly recommends a simple `Provider` with the comment: *"Provider (not StateNotifierProvider) — it never changes, just provides."* A `NotifierProvider` requires a `Notifier` subclass with a `build()` method, which is unnecessary boilerplate for a singleton that is never updated via `state = ...`. A plain `Provider<DeviceLocator>` is simpler and more idiomatic for this use case. Either approach works correctly — this is a style/complexity tradeoff, not a correctness issue.

3. **Async dispose in synchronous callback** (Task 4) — `ref.onDispose(() => state.dispose())` fires `DeviceLocator.dispose()` (which returns `Future<void>`) inside a synchronous `onDispose` callback. The returned future is discarded. This is a known Riverpod limitation documented in `notes/13-explore-example-device-providers.md` and is acceptable for app-shutdown cleanup. No action needed — just confirming awareness.

### Verification

- **Dependencies** (Task 1): All 7 packages are needed by later milestones (rxdart for stream throttling, file_picker + path_provider for calibration import/export, wakelock_plus for calibration screen). Versions are current for the 2026 timeframe. ✅
- **Screen stubs** (Task 2): Four StatelessWidget stubs with const constructors and `package:flutter/material.dart` only — minimal and correct for this phase. ✅
- **GoRouter config** (Task 3): `StatefulShellRoute.indexedStack` correctly preserves tab widget state so live EEG streams survive tab switches. `NavigationBar` (M3) is correct over `BottomNavigationBar` (M2). The `_RootScaffold` pattern matches the exploration note skeleton exactly. ✅
- **Entry point** (Task 5): Replaces the spike screen with `ProviderScope` + `MaterialApp.router`. Correctly removes old `MethodChannel` imports. ✅
- **Import path**: Task 4 correctly imports `DeviceLocator` from the barrel export `package:neiry_kit/neiry_kit.dart`, not from `lib/src/` — matching ARCHITECTURE.md dependency rules. ✅
- **Task ordering**: Dependencies (1) → stubs (2) → router (3) + provider (4) → main.dart (5). Dependencies are correct; nothing can compile without packages resolved first, and main.dart depends on both router and provider. ✅

### Positive Notes

- Correct choice of `StatefulShellRoute.indexedStack` over `ShellRoute` — essential for the EEG streaming use case where tab switches must not destroy subscriptions.
- Clean separation: screen stubs import only Flutter, provider imports only the plugin barrel, router is a standalone file. Good for incremental implementation.
- Single commit covering all 5 tasks keeps the example app compilable at commit boundaries — no intermediate broken state.
- Plan correctly references the exploration note skeleton, anchoring implementation to a verified design.

PLAN_REVIEW_PASS
