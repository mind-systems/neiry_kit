# Global Log Helper with Timestamps

**Date:** 2026-06-03
**Source:** conversation context

## Key Findings

- All diagnostic `log()` calls across `lib/` and `example/` have no timestamps, making it impossible to correlate logcat events with real time.
- A single shared helper function should prepend `HH:mm:ss.SSS` to every message.
- The plugin lib (`lib/src/`) and the example app (`example/lib/`) are separate packages — the utility needs to be accessible from both.

## Details

### Target behavior

Every `log(...)` call in the codebase should produce output like:
```
[neiry_kit] [02:11:41.922] [NeiryService] step 1: unregistering callbacks
```

### Recommended approach

1. Create `lib/src/util/nlog.dart` inside the plugin library:
   ```dart
   import 'dart:developer';
   void nlog(String message, {String name = 'neiry_kit'}) {
     final n = DateTime.now();
     final ts = '${n.hour.toString().padLeft(2,'0')}:${n.minute.toString().padLeft(2,'0')}:${n.second.toString().padLeft(2,'0')}.${n.millisecond.toString().padLeft(3,'0')}';
     log('[$ts] $message', name: name);
   }
   ```
2. Export it from `lib/neiry_kit.dart` (or keep internal via `lib/src/`).
3. In `lib/src/api/device.dart` and `lib/src/api/device_locator.dart`: replace all `log(...)` calls with `nlog(...)`, remove `import 'dart:developer'` if no longer needed directly, remove any `_ts()` top-level helpers.
4. In `example/lib/`: import `nlog` from the plugin or re-export it via `example/lib/utils/nlog.dart`. Replace all `log(...)` calls with `nlog(...)` across `neiry_service.dart`, `device_screen.dart`, `device_scan_provider.dart`.

### Files to touch

- `lib/src/util/nlog.dart` — create
- `lib/neiry_kit.dart` — export or keep internal
- `lib/src/api/device.dart`
- `lib/src/api/device_locator.dart`
- `example/lib/services/neiry_service.dart`
- `example/lib/providers/device_scan_provider.dart`
- `example/lib/router.dart`
- `example/lib/screens/device_screen.dart`
- `example/lib/screens/streams_screen.dart`
- `example/lib/screens/calibration_screen.dart`
- `example/lib/screens/classifiers_screen.dart`
- `example/lib/screens/mems_screen.dart`
- `example/lib/screens/productivity_cardio_screen.dart`
- `example/lib/providers/sound_service_provider.dart`
