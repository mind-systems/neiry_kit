## Code Review Summary

**Files Reviewed:** 12 (plan file + 11 codebase reference files)
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md** — PASS. Plan follows the established layered SDK bridge architecture: JNI C++ → Kotlin bridge → plugin wiring. Each bridge owns its own channels. No cross-bridge calls.
- **RULES.md** — WARN (file not found). No explicit convention file exists; conventions verified against existing codebase patterns.
- **ROADMAP.md** — PASS. The plan implements the `CardioBridge` milestone (line 50). Note: the roadmap lists `cardioError` as the third EventChannel, but the C SDK (`CCardio.h`) defines no error callback — only `IndexesUpdate`, `PPGData`, and `Calibrated`. The plan correctly uses `cardioCalibratedEvent` as the third channel, matching the iOS bridge and the SDK header.

### Critical Issues

None.

### Suggestions (non-blocking)

1. **Task 2 references a misleading pattern**: The plan says "Register all three callbacks" following the pattern from `jni_nfb.cpp`, but `jni_nfb.cpp` registers callbacks **without** `clCError*` parameters (`clCNFB_SetOnUserStateChangedEvent(nfb, on_nfb_state_changed)` — no error param). For Cardio, all three `SetOn*Event` take `clCError*`. The plan's instructions are correct in substance (it explicitly says to check each error), but `jni_physio.cpp` is a more accurate pattern reference since it also checks `clCError*` on callback registration (lines 56–66).

2. **Task 6 — temp buffer allocation unspecified**: The plan says to "populate temp buffers" for PPG values and timestamps before `SetFloatArrayRegion`/`SetLongArrayRegion`, but doesn't specify allocation strategy. For small counts (typical PPG batch), stack-allocated VLAs or `alloca` work; for safety with unknown SDK behavior, heap allocation with `new[]`/`delete[]` is more robust. The implementer should decide, but it's worth calling out. The existing resistance callback in `jni_device.cpp` (referenced by the plan) uses a similar pattern and can guide the choice.

### Positive Notes

- The plan demonstrates excellent iOS parity — the three EventChannel IDs (`cardioData`, `ppgData`, `cardioCalibratedEvent`), callback signatures, and map key names all match `CardioBridge.swift` exactly.
- Correct identification that `clCCardio_SetOn*Event` functions take `clCError*` (unlike NFB's `SetOn*Event` which don't), with proper error-checking instructions.
- Thread-safety pattern (mutex + `NewLocalRef` under lock) is correctly specified, matching the post-review-fix pattern established in the DeviceLocator bridge.
- The PPG callback correctly uses accessor functions (`clCPPGTimedData_GetCount/GetValue/GetTimestampMilli`) rather than direct struct access — matching the opaque handle design.
- Bool field handling with `(jboolean)(data->field != 0)` is more defensive than the existing physio bridge pattern (`(jboolean)data->field`), explicitly guarding against the SDK header bug where bools are initialized with `0.F`.
- Extern declarations in Task 1 include exactly the helpers needed (`map_put_bool`, `map_put_int`, `map_put_object`) — no over-exporting, no missing symbols.
- Disposal pattern correctly identified: no `clCCardio_Destroy` exists in the SDK; disposal is callback-unregister + sink cleanup only.
- Plugin wiring in Task 11 covers all five integration points (field, init, stream handlers, method dispatch, detach) with correct ordering — classifier bridges dispose before device/locator bridges.

PLAN_REVIEW_PASS
