import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neiry_kit/neiry_kit.dart';

import 'device_locator_provider.dart';

class ActiveDeviceNotifier extends Notifier<Device?> {
  @override
  Device? build() {
    // Last-resort synchronous safety net — async cleanup is done explicitly
    // in disconnectAndDispose() and app-level dispose().
    ref.onDispose(() => state?.dispose());
    return null;
  }

  /// Creates a device handle for [serial] and initiates a BLE connection.
  ///
  /// If a device is already active, it is stopped, disconnected, and disposed
  /// before the new one is created (best-effort — errors are swallowed).
  Future<void> createAndConnect(
    String serial, {
    bool bipolarChannels = false,
  }) async {
    final locator = ref.read(deviceLocatorProvider);

    final existing = state;
    if (existing != null) {
      try {
        if (existing.isStarted) await existing.stop();
      } catch (_) {}
      try {
        await existing.disconnect();
      } catch (_) {}
      try {
        await existing.dispose();
      } catch (_) {}
    }

    final device = await locator.createDevice(serial);
    try {
      await device.connect(bipolarChannels: bipolarChannels);
    } catch (e) {
      try {
        await device.dispose();
      } catch (_) {}
      rethrow;
    }
    state = device;
  }

  /// Stops, disconnects, and disposes the active device.
  Future<void> disconnectAndDispose() async {
    final device = state;
    if (device == null) return;
    // Clear state first so UI reflects idle immediately.
    state = null;
    try {
      if (device.isStarted) await device.stop();
    } catch (_) {}
    try {
      await device.disconnect();
    } catch (_) {}
    try {
      await device.dispose();
    } catch (_) {}
  }
}

final activeDeviceProvider = NotifierProvider<ActiveDeviceNotifier, Device?>(
  ActiveDeviceNotifier.new,
);
