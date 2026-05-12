import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neiry_kit/neiry_kit.dart';

import '../providers/stream_providers.dart';

/// Displays all live data streams: EEG, PSD, resistance, battery, artifacts.
class StreamsScreen extends ConsumerWidget {
  const StreamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Streams')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _EegCard(),
            const SizedBox(height: 12),
            _PsdCard(),
            const SizedBox(height: 12),
            _ResistanceCard(),
            const SizedBox(height: 12),
            _BatteryCard(),
            const SizedBox(height: 12),
            _ArtifactsCard(),
          ],
        ),
      ),
    );
  }
}

// ── EEG ──────────────────────────────────────────────────────────────────────

class _EegCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eegAsync = ref.watch(eegProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('EEG', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            eegAsync.when(
              loading: () => const Text('Waiting for EEG data...'),
              error: (e, _) => Text('Error: $e'),
              data: (eeg) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Channel count: ${eeg.channelCount}'),
                  const SizedBox(height: 4),
                  for (var ch = 0; ch < eeg.channelCount; ch++)
                    Builder(builder: (context) {
                      final samples = eeg.rawValues[ch];
                      final label = samples.isEmpty
                          ? 'Ch $ch: —'
                          : 'Ch $ch: ${samples.last.toStringAsFixed(3)} μV';
                      return Text(label);
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── PSD ──────────────────────────────────────────────────────────────────────

double _bandPower(PsdData psd, double lower, double upper) {
  final lo = lower <= upper ? lower : upper;
  final hi = lower <= upper ? upper : lower;
  double sum = 0;
  int count = 0;
  for (var fi = 0; fi < psd.frequencyCount; fi++) {
    final f = psd.frequencies[fi];
    if (f >= lo && f <= hi) {
      for (var ch = 0; ch < psd.channelCount; ch++) {
        sum += psd.values[ch][fi];
      }
      count++;
    }
  }
  if (count == 0 || psd.channelCount == 0) return 0;
  return sum / (count * psd.channelCount);
}

class _PsdCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final psdAsync = ref.watch(psdProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PSD', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            psdAsync.when(
              loading: () => const Text('Waiting for PSD data...'),
              error: (e, _) => Text('Error: $e'),
              data: (psd) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Delta: ${_bandPower(psd, psd.deltaLower, psd.deltaUpper).toStringAsExponential(2)}',
                  ),
                  Text(
                    'Theta: ${_bandPower(psd, psd.thetaLower, psd.thetaUpper).toStringAsExponential(2)}',
                  ),
                  Text(
                    'Alpha: ${_bandPower(psd, psd.alphaLower, psd.alphaUpper).toStringAsExponential(2)}',
                  ),
                  Text(
                    'SMR: ${_bandPower(psd, psd.smrLower, psd.smrUpper).toStringAsExponential(2)}',
                  ),
                  Text(
                    'Beta: ${_bandPower(psd, psd.betaLower, psd.betaUpper).toStringAsExponential(2)}',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Resistance ───────────────────────────────────────────────────────────────

Color _resistanceColor(double kOhm) {
  if (kOhm < 500) return Colors.green;
  if (kOhm <= 1000) return Colors.orange;
  return Colors.red;
}

class _ResistanceCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final map = ref.watch(resistanceMapProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resistance',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (map.isEmpty)
              const Text('No resistance data')
            else
              for (final entry in map.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 12,
                        color: _resistanceColor(entry.value),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${entry.key}: ${entry.value.toStringAsFixed(1)} kΩ',
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// ── Battery ──────────────────────────────────────────────────────────────────

class _BatteryCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batteryAsync = ref.watch(batteryProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Battery',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            batteryAsync.when(
              loading: () => const Text('Waiting for battery...'),
              error: (e, _) => Text('Error: $e'),
              data: (charge) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Battery: $charge%'),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: charge / 100),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Artifacts ────────────────────────────────────────────────────────────────

class _ArtifactsCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artifactsAsync = ref.watch(artifactsProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Artifacts',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            artifactsAsync.when(
              loading: () => const Text('Waiting for artifacts...'),
              error: (e, _) => Text('Error: $e'),
              data: (data) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var ch = 0; ch < data.channelCount; ch++)
                    Text(
                      'Ch $ch: artifact=${data.artifacts[ch]}  '
                      'quality=${data.qualities[ch].toStringAsFixed(2)}',
                      style: TextStyle(
                        color: data.artifacts[ch] != 0 ? Colors.red : null,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
