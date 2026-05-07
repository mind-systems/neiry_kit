import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/emotions_classifier_provider.dart';
import '../providers/physio_baselines_file_manager.dart';
import '../providers/physio_classifier_provider.dart';

/// Shows the Emotions and Physiological States classifier readouts.
class ClassifiersScreen extends ConsumerWidget {
  const ClassifiersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Classifiers')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            _EmotionsCard(),
            SizedBox(height: 12),
            _PhysioCard(),
          ],
        ),
      ),
    );
  }
}

// ── Emotions card ─────────────────────────────────────────────────────────────

class _EmotionsCard extends ConsumerWidget {
  const _EmotionsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classifier = ref.watch(emotionsClassifierProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Emotions',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (classifier == null)
              const Text('Waiting for device...')
            else
              ref.watch(emotionsStateProvider).when(
                loading: () => const Text('Waiting for Emotions data...'),
                error: (e, _) => Text('Error: $e'),
                data: (state) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MetricRow('Attention', state.attention),
                    _MetricRow('Relaxation', state.relaxation),
                    _MetricRow('Cognitive Load', state.cognitiveLoad),
                    _MetricRow('Cognitive Control', state.cognitiveControl),
                    _MetricRow('Self-Control', state.selfControl),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Physio card ───────────────────────────────────────────────────────────────

class _PhysioCard extends ConsumerWidget {
  const _PhysioCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classifier = ref.watch(physioClassifierProvider);
    final baselines = ref.watch(physioBaselinesProvider);

    // Show a SnackBar when baseline calibration completes.
    ref.listen(physioCalibratedProvider, (_, next) {
      if (next.hasValue) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Baselines calibrated')),
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
              'Physiological States',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (classifier == null)
              const Text('Waiting for device...')
            else ...[
              ref.watch(physioStateProvider).when(
                loading: () => Opacity(
                  opacity: 0.5,
                  child: const Text('Waiting for first update...'),
                ),
                error: (e, _) => Text('Error: $e'),
                data: (state) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MetricRow('Relaxation', state.relaxation),
                    _MetricRow('Fatigue', state.fatigue),
                    _MetricRow('Concentration', state.concentration),
                    _MetricRow('Involvement', state.involvement),
                    _MetricRow('Stress', state.stress),
                    const Divider(),
                    const Text(
                      'Signal Quality',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    _SignalQualityRow('NFB', state.nfbArtifacts),
                    _SignalQualityRow('Cardio', state.cardioArtifacts),
                    const SizedBox(height: 8),
                    Text(
                      'Last updated: ${_formatTime(state.timestamp)}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Calibration progress bar — visible only while calibration runs.
              ref.watch(physioCalibrationProgressProvider).whenOrNull(
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
                      .read(physioClassifierProvider.notifier)
                      .startBaselineCalibration(),
                  child: const Text('Start Baseline Calibration'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final result =
                        await PhysioBaselinesFileManager.importFromFile();
                    if (result != null) {
                      await ref
                          .read(physioClassifierProvider.notifier)
                          .importBaselines(result);
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Baselines imported')),
                      );
                    }
                  },
                  child: const Text('Import Baselines'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: baselines == null
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final file = await PhysioBaselinesFileManager
                              .exportToFile(baselines);
                          messenger.showSnackBar(
                            SnackBar(content: Text('Saved to ${file.path}')),
                          );
                        },
                  child: const Text('Export Baselines'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}:'
    '${t.second.toString().padLeft(2, '0')}';

// ── Signal quality row ────────────────────────────────────────────────────────

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

// ── Shared helpers ────────────────────────────────────────────────────────────

class _MetricRow extends StatelessWidget {
  const _MetricRow(this.label, this.value);

  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final display = value != null ? value!.toStringAsFixed(3) : '—';
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
