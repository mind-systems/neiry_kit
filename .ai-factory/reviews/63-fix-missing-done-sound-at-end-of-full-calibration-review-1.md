# Code Review: 63-fix-missing-done-sound-at-end-of-full-calibration (iteration 1)

## Scope

Changes under review:

- `example/lib/screens/calibration_screen.dart` — `_CalibrationCard` converted
  from `ConsumerWidget` to `ConsumerStatefulWidget` + `_CalibrationCardState`.
- `example/lib/providers/calibration_provider.dart` — `_running = false`
  synchronous assignments replaced with `Future.microtask(() => _running = false)`
  in both `startFull()` (line 89) and `startQuick()` (line 109); doc comment on
  `_running` updated to describe the new microtask-based clearing.

Out-of-scope changes in the staged set: deletion of
`.ai-factory/orchestrator-state.json` and addition of plan / plan-review markdown
files — these are workflow artifacts and not part of the code review.

## Correctness analysis

### Microtask ordering (Tasks 2 & 3)

The race is real and the fix lands the assignment after Riverpod's listener
notification:

1. `state = await AsyncValue.guard(…)` assigns the terminal value. Riverpod
   schedules listener notification onto the microtask queue (M1).
2. `Future.microtask(() => _running = false)` enqueues M2.
3. The synchronous tail (`if (_aborted) return;`, `_writeToSharedProvider()`)
   runs and `startFull` returns to its caller (fire-and-forget from
   `onPressed`).
4. The microtask queue drains FIFO: M1 fires, the `ref.listen` callback reads
   `notifier.isRunning == true` and invokes `playDone()` / `playError()`. M2
   then fires and clears `_running`.

Consistency with the existing `Future.microtask(() => _aborted = false)` in
`abort()` (line 129) is preserved.

### `_writeToSharedProvider()` interaction

`_writeToSharedProvider()` mutates `nfbCalibrationProvider`, not
`calibrationProvider`. It does not re-enter the listener under review. The
ordering of `_running = false` (microtask) vs. `_writeToSharedProvider()`
(synchronous) is therefore irrelevant to the audio cue — both still settle
before any subsequent user input.

### Re-entrancy

The "Recalibrate" button can only be tapped after the next frame paints — well
after both M1 and M2 have drained. A pending `_running = false` microtask
cannot stomp on a new `_running = true` set by a subsequent `startFull()` call
from the UI. Safe under normal interaction.

### Abort path

When `abort()` errors the completer:
- `state` transitions to error; M1 (listener) sees `isAborting == true` and
  early-returns (correct: no `playError()` for user-driven aborts).
- M2 clears `_running`; the existing `if (_aborted) return;` guard in
  `startFull` still short-circuits before `_writeToSharedProvider()`.
- The `abort()`-issued `state = AsyncValue.data(…)` and its trailing
  `Future.microtask(() => _aborted = false)` continue to operate as before.

No new race introduced on the abort path.

### `_CalibrationCard` → `ConsumerStatefulWidget` (Task 1)

The conversion is mechanically correct:
- `createState()` returns `_CalibrationCardState`.
- `_CalibrationCardState extends ConsumerState<_CalibrationCard>` exposes the
  inherited `ref` field, which is a `WidgetRef` and has the same `listen` /
  `read` / `watch` surface used by the prior `ConsumerWidget` build signature.
- Both `ref.listen` calls and both `ref.watch` calls are preserved verbatim;
  widget tree is unchanged.

As the plan review noted, this is not load-bearing for the bug (the bug is the
`_running` race), but it is a harmless defensive cleanup and does not introduce
regressions. `ConsumerState`'s `ref` field is stable across rebuilds, so even
if some future Riverpod version changes listener-tracking semantics, this
widget remains correct.

## Other observations

- The deleted `.ai-factory/orchestrator-state.json` is a workflow artifact; not
  a code concern.
- `dart analyze` clean by inspection (no unused imports introduced, no missing
  overrides, `ConsumerState` and `ConsumerStatefulWidget` are exported by
  `package:flutter_riverpod/flutter_riverpod.dart` which is already imported).
- No public API changes; `_CalibrationCard` and `_CalibrationCardState` are
  library-private.
- No security, migration, or performance implications.

## Findings

None.

REVIEW_PASS
