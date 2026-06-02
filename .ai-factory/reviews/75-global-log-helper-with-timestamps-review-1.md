# Code Review: Global log helper with timestamps

**Plan:** `.ai-factory/plans/75-global-log-helper-with-timestamps.md`
**Scope reviewed:** the nlog-related changes — 2 new helper files + 12 migrated source files (`lib/src/api/device.dart`, `lib/src/api/device_locator.dart`, and 10 `example/lib/` files). Unrelated staged changes (`DeviceLocatorBridge.kt`, `docs/guides/teardown.md`, ROADMAP/notes) predate this milestone and are out of scope.
**Risk Level:** 🟢 Low

## Verification performed

- **Both helper files are correct and identical.** `lib/src/util/nlog.dart` and `example/lib/utils/nlog.dart` both define `void nlog(String message, {String name = 'neiry_kit', Object? error, StackTrace? stackTrace})`, build the `HH:mm:ss.SSS` timestamp with correct zero-padding (2/2/2/3), and forward `error`/`stackTrace` to `dart:developer log`. Timestamp arithmetic uses `DateTime.now()` fields directly — no off-by-one or formatting bugs.
- **`error:`/`stackTrace:` forwarding works.** The 4 call sites in `sound_service_provider.dart` (lines 18, 24, 30, 36) pass `error: e, stackTrace: st` and now resolve against the extended signature — no build break, no loss of structured error data.
- **No raw `log(` calls remain.** A `\blog\(` sweep matches only line 12 of each `nlog.dart` (the helper body itself). All other call sites use `nlog(`.
- **`dart:developer` is fully contained.** Only the two `nlog.dart` files import it; every migrated file dropped the import. No aliased (`as developer`) usages remain.
- **Import paths resolve correctly.** `lib/src/api/*` → `../util/nlog.dart` (→ `lib/src/util/`); `example/lib/screens/*` and `example/lib/providers/*` → `../utils/nlog.dart`; `example/lib/services/neiry_service.dart` → `../utils/nlog.dart`; `example/lib/router.dart` → `utils/nlog.dart` (file is directly in `lib/`). All match the plan's corrected table and the existing `rate_counter.dart` precedent.
- **Multi-line call at `device.dart:75` migrated cleanly**, retaining `name: 'neiry_kit'`.
- **Public API kept clean.** `lib/neiry_kit.dart` is unchanged — `nlog` is not exported from the barrel, honoring ARCHITECTURE.md point 4. No name collision: example files import the barrel (which lacks `nlog`) plus their own local `utils/nlog.dart`.
- **`test/` untouched**, as required.

## Findings

None. The implementation matches the plan exactly, compiles cleanly (no unresolved imports, no unused imports, no missing named parameters), and introduces no runtime, type, or correctness regressions. The two-copy duplication is the deliberate, documented trade-off to keep the plugin's public surface clean.

REVIEW_PASS
