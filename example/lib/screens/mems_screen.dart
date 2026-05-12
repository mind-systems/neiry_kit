import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/device_state_providers.dart';
import '../providers/mems_classifier_provider.dart';
import '../providers/nfb_calibration_provider.dart';

/// Shows live accelerometer and gyroscope readings from the MEMS classifier
/// with an optional NFB calibration toggle.
class MemsScreen extends ConsumerWidget {
  const MemsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nfbData = ref.watch(nfbCalibrationProvider);
    final useCalibration = ref.watch(useMemsCalibrationToggleProvider);
    final classifier = ref.watch(memsClassifierProvider);
    final uiState = ref.watch(deviceUiStateProvider);
    final canEditToggle = uiState != DeviceUiState.started;

    return Scaffold(
      appBar: AppBar(title: const Text('MEMS')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('Use NFB Calibration'),
              subtitle: nfbData == null
                  ? const Text(
                      'Run calibration first to enable',
                      style: TextStyle(color: Colors.grey),
                    )
                  : (!canEditToggle
                      ? const Text(
                          'Stop streaming to change this setting',
                          style: TextStyle(color: Colors.grey),
                        )
                      : (useCalibration
                          ? const Text(
                              'Using individual NFB calibration',
                              style: TextStyle(color: Colors.grey),
                            )
                          : null)),
              value: useCalibration && nfbData != null,
              onChanged: (nfbData == null || !canEditToggle)
                  ? null
                  : (val) {
                      ref
                          .read(useMemsCalibrationToggleProvider.notifier)
                          .state = val;
                    },
            ),
            const SizedBox(height: 12),
            if (classifier == null)
              const Text('Waiting for device...')
            else
              ref.watch(memsProvider).when(
                    loading: () => const Text('Waiting for MEMS data...'),
                    error: (e, _) => Text('Error: $e'),
                    data: (samples) {
                      if (samples.isEmpty) {
                        return const Text('Waiting for MEMS data...');
                      }
                      final sample = samples.last;
                      return Column(
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Accelerometer',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  _AxisRow('X', sample.accelerometer.x),
                                  _AxisRow('Y', sample.accelerometer.y),
                                  _AxisRow('Z', sample.accelerometer.z),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Gyroscope',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  _AxisRow('X', sample.gyroscope.x),
                                  _AxisRow('Y', sample.gyroscope.y),
                                  _AxisRow('Z', sample.gyroscope.z),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}

class _AxisRow extends StatelessWidget {
  const _AxisRow(this.label, this.value);

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 40, child: Text(label)),
          Text(value.toStringAsFixed(4)),
        ],
      ),
    );
  }
}
