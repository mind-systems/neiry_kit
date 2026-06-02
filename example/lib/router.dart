import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'utils/nlog.dart';

import 'screens/calibration_screen.dart';
import 'screens/classifiers_screen.dart';
import 'screens/device_screen.dart';
import 'screens/mems_screen.dart';
import 'screens/productivity_cardio_screen.dart';
import 'screens/streams_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/device',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          _RootScaffold(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/device', builder: (_, _) => const DeviceScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/streams', builder: (_, _) => const StreamsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/classifiers',
              builder: (_, _) => const ClassifiersScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/productivity',
              builder: (_, _) => const ProductivityCardioScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/mems', builder: (_, _) => const MemsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/calibration',
              builder: (_, _) => const CalibrationScreen()),
        ]),
      ],
    ),
  ],
);

class _RootScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const _RootScaffold({required this.navigationShell});

  static String _tabName(int i) =>
      const ['Device', 'Streams', 'Classifiers', 'Productivity', 'MEMS', 'Calibration'][i];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (int index) {
          nlog('Tab → ${_tabName(index)}', name: 'Neiry');
          navigationShell.goBranch(index);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.devices), label: 'Device'),
          NavigationDestination(
              icon: Icon(Icons.signal_cellular_alt), label: 'Streams'),
          NavigationDestination(
              icon: Icon(Icons.ssid_chart), label: 'Classifiers'),
          NavigationDestination(
              icon: Icon(Icons.trending_up), label: 'Productivity'),
          NavigationDestination(icon: Icon(Icons.sensors), label: 'MEMS'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Calibration'),
        ],
      ),
    );
  }
}
