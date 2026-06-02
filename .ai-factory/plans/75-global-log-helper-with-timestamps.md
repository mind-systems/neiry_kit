# Plan: Global log helper with timestamps

## Context
Introduce a single `nlog()` helper that prepends an `HH:mm:ss.SSS` timestamp to every diagnostic log line, and replace all raw `log()` calls across the plugin library and example app so logcat output can be correlated with real time.

Two review findings shape this plan:
- **`nlog` must forward `error:` / `stackTrace:`.** `example/lib/providers/sound_service_provider.dart` has 4 `log(...)` calls passing `error:` and `stackTrace:`. The helper signature must accept and forward them, or those sites break the build (or silently lose stack-trace data). Resolution: extend the signature.
- **Keep the public API clean (ARCHITECTURE.md line 110).** The barrel "exports only what `mind_mobile` needs"; a diagnostic logger is plugin-internal. Resolution: do **not** export `nlog` from the barrel. The plugin lib imports it directly from `lib/src/util/`, and the example app gets its own independent copy at `example/lib/utils/nlog.dart` (the example cannot import `lib/src/`). This accepts one duplicated ~8-line helper to keep the public surface clean — the trade-off the source note (`25-global-log-helper.md`, step 4) explicitly offered.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Helpers

- [x] **Task 1: Create the plugin `nlog` helper**
  Files: `lib/src/util/nlog.dart`
  Create a new file (new `lib/src/util/` directory) with a single top-level function:
  ```dart
  import 'dart:developer';

  void nlog(String message, {String name = 'neiry_kit', Object? error, StackTrace? stackTrace}) {
    final n = DateTime.now();
    final ts = '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}:'
        '${n.second.toString().padLeft(2, '0')}.${n.millisecond.toString().padLeft(3, '0')}';
    log('[$ts] $message', name: name, error: error, stackTrace: stackTrace);
  }
  ```
  The `error` / `stackTrace` parameters are required so the `sound_service_provider.dart` call sites migrate cleanly. Output for `nlog('step 1', name: 'NeiryService')` reads `[NeiryService] [02:11:41.922] step 1`.

- [x] **Task 2: Create the example-app `nlog` copy** (depends on Task 1)
  Files: `example/lib/utils/nlog.dart`
  Create a new file (the `example/lib/utils/` directory already exists — it holds `rate_counter.dart`) containing an identical copy of the helper from Task 1 (same signature including `error` / `stackTrace`). The example app cannot import `lib/src/`, and per ARCHITECTURE.md line 110 `nlog` is **not** exported from the barrel, so the example owns its own copy. Do **not** add any `export` of `nlog` to `lib/neiry_kit.dart`.

### Phase 2: Plugin library

- [x] **Task 3: Switch plugin API files to `nlog`** (depends on Task 1)
  Files: `lib/src/api/device.dart`, `lib/src/api/device_locator.dart`
  Replace every `log(...)` call with `nlog(...)`, preserving any `name:` argument already passed (including the multi-line call at `device.dart:75`). Remove `import 'dart:developer';` from both files and add `import '../util/nlog.dart';` instead. Remove any leftover local timestamp helpers if present (none currently exist). Confirm `dart:developer` is no longer referenced in these files after the change.

### Phase 3: Example app

- [x] **Task 4: Switch example app files to `nlog`** (depends on Task 2)
  Files: `example/lib/services/neiry_service.dart`, `example/lib/providers/device_scan_provider.dart`, `example/lib/providers/sound_service_provider.dart`, `example/lib/router.dart`, `example/lib/screens/device_screen.dart`, `example/lib/screens/streams_screen.dart`, `example/lib/screens/calibration_screen.dart`, `example/lib/screens/classifiers_screen.dart`, `example/lib/screens/mems_screen.dart`, `example/lib/screens/productivity_cardio_screen.dart`
  In each file replace every `log(...)` call with `nlog(...)`, preserving all named arguments — `name:`, and for the 4 calls in `sound_service_provider.dart` also `error:` and `stackTrace:` (these now forward correctly thanks to Task 1/2's signature). Remove `import 'dart:developer';` and add the import to `example/lib/utils/nlog.dart`. `utils/` is a sibling of `screens/`, `providers/`, and `services/` (all one level below `example/lib/`), so the correct relative paths are:

  | File location | Import |
  |---|---|
  | `example/lib/screens/*` (6 files) | `import '../utils/nlog.dart';` |
  | `example/lib/providers/*` (2 files) | `import '../utils/nlog.dart';` |
  | `example/lib/services/neiry_service.dart` | `import '../utils/nlog.dart';` |
  | `example/lib/router.dart` (directly in `lib/`) | `import 'utils/nlog.dart';` |

  (Confirmed against the existing `import '../utils/rate_counter.dart';` in `example/lib/providers/rate_providers.dart`.) After the change, verify no `dart:developer` import or raw `log(` call remains anywhere under `example/lib/`.

## Notes
- Single logical commit: "Add nlog timestamped log helper and replace log() calls".
- Do not touch test files under `test/` — they reference the public API, not `log()`.
- `nlog` is intentionally **not** exported from `lib/neiry_kit.dart` to keep the public API clean (ARCHITECTURE.md line 110); this is why the example app has its own copy.
