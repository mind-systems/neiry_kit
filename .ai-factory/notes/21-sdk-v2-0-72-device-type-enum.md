# SDK v2.0.72 — DeviceType Enum Comparison

## Verdict: No issues, no action required

All integer values are identical across old SDK, new SDK, and our Dart enum. The naming difference in the official Dart wrapper is cosmetic and irrelevant since we don't use that wrapper.

## C enum — unchanged in both versions

```c
typedef enum clCDeviceType {
    clCDeviceType_Headband = 0,
    clCDeviceType_Buds     = 1,
    clCDeviceType_Headphones = 2,
    clCDeviceType_Impulse  = 3,
    clCDeviceType_Any      = 4,
    clCDeviceType_BrainBit = 6,   // gap: 5 unused
    clCDeviceType_SinWave  = 100,
    clCDeviceType_Noise    = 101,
} clCDeviceType;
```

## Our `NeiryDeviceType` Dart enum — fully aligned

```dart
enum NeiryDeviceType {
  headband(0), buds(1), headphones(2), impulse(3),
  any(4), brainBit(6), sinWave(100), noise(101);
  const NeiryDeviceType(this.code);
  final int code;
}
```

All `.code` values match C rawValues exactly.

## Official Dart wrapper enum — naming only differs, not values

```dart
enum DeviceType { Band, Buds, Headphones, Impulse, Any, BrainBit, SinWave, Noise }
```

Note: first value is `Band` (not `Headband`). The wrapper handles non-contiguous values (6, 100, 101) via explicit switch-case. This is the same approach our bridges use.

## Bridge mappings — both correct

- iOS: `clCDeviceInfo_GetType(info).rawValue` → integer passed over channel
- Android: `(jint)clCDeviceInfo_GetType(info)` → integer passed over channel

Both correctly pass the raw C integer, which our Dart enum's `.code` values match.
