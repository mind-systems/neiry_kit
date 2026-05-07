import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/calibration_provider.dart';
import '../providers/calibration_timer_provider.dart';
import '../providers/calibration_ui_state.dart';
import '../providers/nfb_classifier_provider.dart';

/// Shows the NFB calibration pipeline and live NFB band-power readout.
class CalibrationScreen extends ConsumerWidget {
  const CalibrationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calibration')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            _CalibrationCard(),
            SizedBox(height: 12),
            _NfbCard(),
          ],
        ),
      ),
    );
  }
}

// ── Calibration card ──────────────────────────────────────────────────────────

class _CalibrationCard extends ConsumerWidget {
  const _CalibrationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calibAsync = ref.watch(calibrationProvider);
    final timerState = ref.watch(calibrationTimerProvider);

    // Derive CalibrationUiState from async + timer state.
    final CalibrationUiState? uiState;
    if (calibAsync.isLoading) {
      final stage = timerState.stage;
      if (stage != null) {
        uiState = CalibrationStageActive(stage, timerState.elapsed);
      } else {
        uiState = null; // quick calibration in progress — show generic loading
      }
    } else if (calibAsync.hasError) {
      uiState = CalibrationError(calibAsync.error!.toString());
    } else {
      final data = calibAsync.value;
      uiState = data != null ? CalibrationDone(data) : const CalibrationIdle();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Calibration',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (uiState == null) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 8),
              const Center(child: Text('Quick calibration in progress…')),
            ] else
              switch (uiState) {
                CalibrationIdle() => _IdleContent(uiState),
                CalibrationStageActive() => _ActiveContent(uiState),
                CalibrationDone() => _DoneContent(uiState),
                CalibrationError() => _ErrorContent(uiState),
              },
          ],
        ),
      ),
    );
  }
}

// ── Idle ─────────────────────────────────────────────────────────────────────

class _IdleContent extends ConsumerWidget {
  const _IdleContent(this.uiState);
  final CalibrationIdle uiState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(uiState.instruction),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () =>
              ref.read(calibrationProvider.notifier).startFull(),
          child: const Text('Start Full Calibration'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () =>
              ref.read(calibrationProvider.notifier).startQuick(),
          child: const Text('Start Quick Calibration'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () =>
              ref.read(calibrationProvider.notifier).importFromFile(),
          child: const Text('Import from File'),
        ),
      ],
    );
  }
}

// ── Active stage ──────────────────────────────────────────────────────────────

class _ActiveContent extends ConsumerWidget {
  const _ActiveContent(this.uiState);
  final CalibrationStageActive uiState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          uiState.stageLabel,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(uiState.instruction),
        const SizedBox(height: 8),
        Text(
          '${uiState.elapsedSeconds}s',
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () =>
              ref.read(calibrationProvider.notifier).abort(),
          child: const Text('Abort'),
        ),
      ],
    );
  }
}

// ── Done ──────────────────────────────────────────────────────────────────────

class _DoneContent extends ConsumerWidget {
  const _DoneContent(this.uiState);
  final CalibrationDone uiState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Calibration complete',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          uiState.isValid ? 'Status: valid' : 'Status: invalid',
          style: TextStyle(
            color: uiState.isValid ? Colors.green : Colors.red,
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            final file =
                await ref.read(calibrationProvider.notifier).exportToFile();
            if (file != null) {
              messenger.showSnackBar(
                SnackBar(content: Text('Saved to ${file.path}')),
              );
            }
          },
          child: const Text('Export to File'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () =>
              ref.read(calibrationProvider.notifier).startFull(),
          child: const Text('Recalibrate'),
        ),
      ],
    );
  }
}

// ── Error ──────────────────────────────────────────────────────────────────────

class _ErrorContent extends ConsumerWidget {
  const _ErrorContent(this.uiState);
  final CalibrationError uiState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          uiState.message,
          style: const TextStyle(color: Colors.red),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () => ref.invalidate(calibrationProvider),
          child: const Text('Retry'),
        ),
      ],
    );
  }
}

// ── NFB card ──────────────────────────────────────────────────────────────────

class _NfbCard extends ConsumerWidget {
  const _NfbCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classifier = ref.watch(nfbClassifierProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'NFB Classifier',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (classifier == null)
              const Text('Waiting for device...')
            else
              ref.watch(nfbStateProvider).when(
                loading: () => const Text('Waiting for NFB data...'),
                error: (e, _) => Text('Error: $e'),
                data: (state) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BandRow('Delta', state.delta),
                    _BandRow('Theta', state.theta),
                    _BandRow('Alpha', state.alpha),
                    _BandRow('SMR', state.smr),
                    _BandRow('Beta', state.beta),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BandRow extends StatelessWidget {
  const _BandRow(this.label, this.value);

  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final display = value != null ? value!.toStringAsFixed(3) : '—';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 60, child: Text(label)),
          Text(display),
        ],
      ),
    );
  }
}
