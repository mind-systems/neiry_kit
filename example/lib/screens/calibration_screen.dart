import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neiry_kit/neiry_kit.dart';

import '../providers/calibration_provider.dart';
import '../providers/calibration_timer_provider.dart';
import '../providers/calibration_ui_state.dart';
import '../providers/classifier_stream_providers.dart';
import '../providers/nfb_calibration_provider.dart';
import '../providers/sound_service_provider.dart';
import '../utils/nlog.dart';

/// Shows the NFB calibration pipeline and live NFB band-power readout.
class CalibrationScreen extends ConsumerWidget {
  const CalibrationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calibration')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: const [
            _CalibrationCard(),
            SizedBox(height: 12),
            _NfbCard(),
            SizedBox(height: 12),
            _CalibrationDataCard(),
            SizedBox(height: 12),
            _UseCalibrationCard(),
          ],
        ),
      ),
    );
  }
}

// ── Calibration card ──────────────────────────────────────────────────────────

class _CalibrationCard extends ConsumerStatefulWidget {
  const _CalibrationCard();

  @override
  ConsumerState<_CalibrationCard> createState() => _CalibrationCardState();
}

class _CalibrationCardState extends ConsumerState<_CalibrationCard> {
  @override
  Widget build(BuildContext context) {
    ref.listen(calibrationTimerProvider, (prev, next) {
      if (ref.read(calibrationProvider.notifier).isAborting) return;
      if (next.stage != null && next.stage != prev?.stage) {
        ref.read(soundServiceProvider).playStageStart();
      }
    });

    ref.listen<AsyncValue<IndividualNfbData?>>(calibrationProvider, (prev, next) {
      final notifier = ref.read(calibrationProvider.notifier);
      if (!notifier.isRunning) return; // skip cold-open, import, and Retry rebuilds
      if (notifier.isAborting) return; // abort()'s loading→error→data transitions
      final sound = ref.read(soundServiceProvider);
      if (prev!.isLoading && next.hasValue && next.value != null) {
        sound.playDone();
      } else if (!prev.hasError && next.hasError) {
        sound.playError();
      }
    });

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
          onPressed: () {
            nlog('Calibration: Start Full tapped', name: 'Neiry');
            ref.read(calibrationProvider.notifier).startFull();
          },
          child: const Text('Start Full Calibration'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () {
            nlog('Calibration: Start Quick tapped', name: 'Neiry');
            ref.read(calibrationProvider.notifier).startQuick();
          },
          child: const Text('Start Quick Calibration'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () {
            nlog('Calibration: Import tapped', name: 'Neiry');
            ref.read(calibrationProvider.notifier).importFromFile();
          },
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
          onPressed: () {
            nlog('Calibration: Abort tapped', name: 'Neiry');
            ref.read(calibrationProvider.notifier).abort();
          },
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
        // For handling invalid calibration (failReason, recovery flow):
        // docs/reference/calibration.md → "Результат калибровки"
        Text(
          uiState.isValid ? 'Status: valid' : 'Status: invalid',
          style: TextStyle(
            color: uiState.isValid ? Colors.green : Colors.red,
          ),
        ),
        if (!uiState.isValid) ...[
          const SizedBox(height: 4),
          Text(
            describeFailReason(uiState.data.failReason),
            style: const TextStyle(color: Colors.red),
          ),
        ],
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () async {
            nlog('Calibration: Export tapped', name: 'Neiry');
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
          onPressed: () {
            nlog('Calibration: Start Full tapped', name: 'Neiry');
            ref.read(calibrationProvider.notifier).startFull();
          },
          child: const Text('Start Full Calibration'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () {
            nlog('Calibration: Start Quick tapped', name: 'Neiry');
            ref.read(calibrationProvider.notifier).startQuick();
          },
          child: const Text('Start Quick Calibration'),
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
          onPressed: () {
            nlog('Calibration: Retry tapped', name: 'Neiry');
            ref.invalidate(calibrationProvider);
          },
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
            ref.watch(nfbStateProvider).when(
              loading: () => const Text('Waiting for device...'),
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

// ── Use calibration toggle card ───────────────────────────────────────────────

class _UseCalibrationCard extends ConsumerWidget {
  const _UseCalibrationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nfbData = ref.watch(nfbCalibrationProvider);
    final useCal = ref.watch(useCalibrationToggleProvider);

    return Card(
      child: SwitchListTile(
        title: const Text('Use NFB Calibration'),
        subtitle: nfbData == null
            ? const Text(
                'Run calibration first to enable',
                style: TextStyle(color: Colors.grey),
              )
            : const Text(
                'Applies to Productivity, Cardio & MEMS — takes effect on next connect',
                style: TextStyle(color: Colors.grey),
              ),
        value: useCal && nfbData != null,
        onChanged: nfbData == null
            ? null
            : (val) {
                nlog('Calibration: Use NFB Calibration toggled: $val', name: 'Neiry');
                ref.read(useCalibrationToggleProvider.notifier).state = val;
              },
      ),
    );
  }
}

// ── Calibration data card ─────────────────────────────────────────────────────

class _CalibrationDataCard extends ConsumerWidget {
  const _CalibrationDataCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(calibrationProvider).value ?? const IndividualNfbData();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Individual Alpha',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _BandRow('Peak, Hz', data.individualFrequency),
            _BandRow('Lower, Hz', data.lowerFrequency),
            _BandRow('Upper, Hz', data.upperFrequency),
            _BandRow('Bandwidth, Hz', data.individualBandwidth),
            _BandRow('Norm. power', data.individualNormalizedPower),
          ],
        ),
      ),
    );
  }
}
