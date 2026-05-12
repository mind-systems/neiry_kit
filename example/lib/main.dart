import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/active_device_provider.dart';
import 'router.dart';

void main() {
  runApp(const NeiryExampleApp());
}

class NeiryExampleApp extends StatefulWidget {
  const NeiryExampleApp({super.key});

  @override
  State<NeiryExampleApp> createState() => _NeiryExampleAppState();
}

class _NeiryExampleAppState extends State<NeiryExampleApp> {
  late final ProviderContainer _container;

  @override
  void initState() {
    super.initState();
    _container = ProviderContainer();
  }

  @override
  void dispose() {
    _cleanupAndDispose();
    super.dispose();
  }

  /// Stops and disconnects the active device before tearing down the container.
  ///
  /// DeviceLocator disposal is intentionally omitted here — `ref.onDispose` in
  /// `device_locator_provider.dart` handles it when `_container.dispose()` runs,
  /// and calling `DeviceLocator.dispose()` twice throws `StateError`.
  Future<void> _cleanupAndDispose() async {
    final device = _container.read(activeDeviceProvider);
    if (device != null) {
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
    _container.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UncontrolledProviderScope(
      container: _container,
      child: MaterialApp.router(routerConfig: appRouter),
    );
  }
}
