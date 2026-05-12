import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/cardio_classifier_provider.dart';
import '../providers/device_state_providers.dart';
import '../providers/nfb_calibration_provider.dart';
import '../providers/productivity_classifier_provider.dart';

// ── Enum label tables ──────────────────────────────────────────────────────

const List<String> _recommendationLabels = [
  'No Recommendation',
  'Involvement',
  'Relaxation',
  'Slight Fatigue',
  'Severe Fatigue',
  'Chronic Fatigue',
];

const List<String> _stressLabels = [
  'No Stress',
  'Anxiety',
  'Stress',
];

const List<String> _fatigueGrowthLabels = [
  'None',
  'Low',
  'Medium',
  'High',
];

String _labelFor(List<String> labels, int value) {
  if (value < 0 || value >= labels.length) return 'Unknown ($value)';
  return labels[value];
}

String _formatTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}:'
    '${t.second.toString().padLeft(2, '0')}';

// ── Screen ─────────────────────────────────────────────────────────────────

/// Shows the Productivity and Cardio classifier readouts with a shared
/// NFB calibration toggle.
class ProductivityCardioScreen extends ConsumerWidget {
  const ProductivityCardioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nfbData = ref.watch(nfbCalibrationProvider);
    final useCalibration = ref.watch(useCalibrationToggleProvider);
    final uiState = ref.watch(deviceUiStateProvider);
    final canEditToggle = uiState != DeviceUiState.started;

    return Scaffold(
      appBar: AppBar(title: const Text('Productivity & Cardio')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ── Shared calibration toggle ──────────────────────────────────
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
                      ref.read(useCalibrationToggleProvider.notifier).state =
                          val;
                    },
            ),
            const SizedBox(height: 12),
            const _ProductivityCard(),
            const SizedBox(height: 12),
            const _CardioCard(),
          ],
        ),
      ),
    );
  }
}

// ── Productivity card ──────────────────────────────────────────────────────

class _ProductivityCard extends ConsumerWidget {
  const _ProductivityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classifier = ref.watch(productivityClassifierProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Productivity',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (classifier == null)
              const Text('Waiting for device...')
            else ...[
              // ── Indexes ───────────────────────────────────────────────────
              ref.watch(productivityIndexesProvider).when(
                loading: () => const Text('Waiting for indexes data...'),
                error: (e, _) => Text('Error: $e'),
                data: (indexes) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Indexes',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    _LabelRow(
                      'Recommendation',
                      _labelFor(_recommendationLabels, indexes.relaxation),
                    ),
                    _LabelRow(
                      'Stress',
                      _labelFor(_stressLabels, indexes.stress),
                    ),
                    _SignalQualityRow('Artifacts', indexes.hasArtifacts),
                  ],
                ),
              ),
              const Divider(),
              // ── Metrics ───────────────────────────────────────────────────
              ref.watch(productivityMetricsProvider).when(
                loading: () => const Text('Waiting for metrics data...'),
                error: (e, _) => Text('Error: $e'),
                data: (metrics) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Metrics',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    _MetricRow('Fatigue Score', metrics.fatigueScore),
                    _MetricRow(
                        'Rev. Fatigue Score', metrics.reverseFatigueScore),
                    _MetricRow('Gravity Score', metrics.gravityScore),
                    _MetricRow('Relaxation Score', metrics.relaxationScore),
                    _MetricRow(
                        'Concentration Score', metrics.concentrationScore),
                    _MetricRow('Productivity Score', metrics.productivityScore),
                    _MetricRow('Current Value', metrics.currentValue),
                    _MetricRow('Alpha', metrics.alpha),
                    _MetricRow(
                        'Productivity Baseline', metrics.productivityBaseline),
                    _MetricRow(
                        'Accumulated Fatigue', metrics.accumulatedFatigue),
                    _LabelRow(
                      'Fatigue Growth Rate',
                      _labelFor(_fatigueGrowthLabels, metrics.fatigueGrowthRate),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 140,
                            child: Text('Artifacts Data'),
                          ),
                          Text(
                            metrics.artifactsData != null
                                ? 'Artifacts: ${metrics.artifactsData!.length} bytes'
                                : 'Artifacts: none',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Calibration progress bar — visible only while calibration runs.
              ref.watch(productivityCalibrationProgressProvider).whenOrNull(
                    data: (progress) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LinearProgressIndicator(value: progress),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ) ??
                  const SizedBox.shrink(),
              // Action buttons
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => ref
                      .read(productivityClassifierProvider.notifier)
                      .startBaselineCalibration(),
                  child: const Text('Start Baseline Calibration'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => ref
                      .read(productivityClassifierProvider.notifier)
                      .resetAccumulatedFatigue(),
                  child: const Text('Reset Fatigue'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Cardio card ────────────────────────────────────────────────────────────

class _CardioCard extends ConsumerWidget {
  const _CardioCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classifier = ref.watch(cardioClassifierProvider);

    // Show a SnackBar when Cardio internal calibration completes.
    ref.listen(cardioCalibratedProvider, (_, next) {
      if (next.hasValue) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cardio calibration complete')),
        );
      }
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cardio',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (classifier == null)
              const Text('Waiting for device...')
            else ...[
              // ── Cardio state ──────────────────────────────────────────────
              ref.watch(cardioStateProvider).when(
                loading: () => const Text('Waiting for Cardio data...'),
                error: (e, _) => Text('Error: $e'),
                data: (data) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!data.metricsAvailable)
                      Opacity(
                        opacity: 0.5,
                        child: const Text('Calibrating... metrics not yet available'),
                      )
                    else ...[
                      _MetricRow('Heart Rate', data.heartRate, decimals: 1),
                      _MetricRow('Stress Index', data.stressIndex),
                      _MetricRow('Kaplan Index', data.kaplanIndex),
                    ],
                    const Divider(),
                    _SignalQualityRow('Artifacts', data.hasArtifacts),
                    _SignalQualityRow('Skin Contact', !data.skinContact),
                    _SignalQualityRow('Motion', data.motionArtifacts),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // ── PPG last value ────────────────────────────────────────────
              ref.watch(cardioPpgProvider).whenOrNull(
                    data: (ppg) => Text(
                      ppg.values.isNotEmpty
                          ? 'PPG: ${ppg.values.last.toStringAsFixed(1)} @ '
                              '${_formatTime(DateTime.fromMillisecondsSinceEpoch(ppg.timestamps.last).toLocal())}'
                          : 'PPG: —',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ) ??
                  const Text(
                    'PPG: —',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────

class _MetricRow extends StatelessWidget {
  const _MetricRow(this.label, this.value, {this.decimals = 3});

  final String label;
  final double? value;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final display = value != null ? value!.toStringAsFixed(decimals) : '—';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(label)),
          Text(display),
        ],
      ),
    );
  }
}

class _LabelRow extends StatelessWidget {
  const _LabelRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(label)),
          Text(value),
        ],
      ),
    );
  }
}

class _SignalQualityRow extends StatelessWidget {
  const _SignalQualityRow(this.label, this.hasArtifacts);

  final String label;
  final bool hasArtifacts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 60, child: Text(label)),
          Icon(
            hasArtifacts ? Icons.error : Icons.check_circle,
            color: hasArtifacts ? Colors.red : Colors.green,
            size: 18,
          ),
        ],
      ),
    );
  }
}
