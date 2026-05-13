import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/neiry_service_provider.dart';
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
  /// [NeiryService.dispose] is idempotent — `ref.onDispose` in
  /// `neiry_service_provider.dart` will also fire when `_container.dispose()`
  /// runs, but the second call returns immediately on `_disposed = true`.
  Future<void> _cleanupAndDispose() async {
    try {
      await _container.read(neiryServiceProvider).dispose();
    } catch (_) {}
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
