# Plan: Fix scan spinner not showing on repeat scan

## Context
The scan spinner only appears on the first scan because `ref.invalidate(deviceScanProvider(params))` puts the provider into a "refreshing" state (`AsyncData` with `isLoading: true`), which `.when()` routes to `data:` — bypassing the `loading:` branch. Add an explicit `isLoading` guard before `.when()` so the spinner shows for both first-time and repeat scans.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Fix

- [x] **Task 1: Add isLoading guard in `_buildScanResults()`**
  Files: `example/lib/screens/device_screen.dart`
  In `_buildScanResults()` (around line 233), immediately after `final scanAsync = ref.watch(deviceScanProvider(params));` and before the existing `return scanAsync.when(…)`, insert:
  ```dart
  if (scanAsync.isLoading) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(child: CircularProgressIndicator()),
    );
  }
  ```
  This guard fires for both `AsyncLoading` (first scan) and `AsyncData/AsyncError` with `isLoading: true` (repeat scans after `ref.invalidate`). The existing `scanAsync.when(...)` block stays in place to handle the resolved `data`/`error` states. The `loading:` branch inside `.when()` is now unreachable in practice but should be kept for safety. No other changes needed.
