import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neiry_kit/neiry_kit.dart';

import '../providers/active_device_provider.dart';
import '../providers/device_scan_provider.dart';
import '../providers/device_state_providers.dart';

class DeviceScreen extends ConsumerStatefulWidget {
  const DeviceScreen({super.key});

  @override
  ConsumerState<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends ConsumerState<DeviceScreen> {
  NeiryDeviceType _selectedType = NeiryDeviceType.any;
  int _searchTime = 5;
  String? _selectedSerial;

  // Non-null once the user has pressed Scan at least once.
  (NeiryDeviceType, int)? _scanParams;

  final _searchTimeController = TextEditingController(text: '5');

  @override
  void dispose() {
    _searchTimeController.dispose();
    super.dispose();
  }

  // ── Scan ──────────────────────────────────────────────────────────────────

  void _scan() {
    final params = (_selectedType, _searchTime);
    if (_scanParams == params) {
      // Same params — invalidate so the provider re-runs the scan.
      ref.invalidate(deviceScanProvider(params));
    }
    setState(() => _scanParams = params);
  }

  // ── Device actions ────────────────────────────────────────────────────────

  Future<void> _connect() async {
    final serial = _selectedSerial;
    if (serial == null) return;
    // Reset started flag before connecting — prevents stale `started` state
    // if the user reconnects after an unexpected disconnect mid-stream.
    ref.read(deviceIsStartedProvider.notifier).state = false;
    try {
      await ref
          .read(activeDeviceProvider.notifier)
          .createAndConnect(serial);
    } catch (e) {
      _showError(e is NeiryException ? e.message : e.toString());
    }
  }

  Future<void> _start() async {
    final device = ref.read(activeDeviceProvider);
    if (device == null) return;
    try {
      await device.start();
      ref.read(deviceIsStartedProvider.notifier).state = true;
    } on NeiryException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _stop() async {
    final device = ref.read(activeDeviceProvider);
    if (device == null) return;
    try {
      await device.stop();
      ref.read(deviceIsStartedProvider.notifier).state = false;
    } on NeiryException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _disconnect() async {
    try {
      await ref.read(activeDeviceProvider.notifier).disconnectAndDispose();
      ref.read(deviceIsStartedProvider.notifier).state = false;
    } on NeiryException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(deviceUiStateProvider);
    final connectionAsync = ref.watch(deviceConnectionStateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Device')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildScanSection(),
          const Divider(height: 32),
          _buildActionsSection(uiState),
          const Divider(height: 32),
          _buildStatusSection(uiState, connectionAsync),
        ],
      ),
    );
  }

  // ── Scan section ──────────────────────────────────────────────────────────

  Widget _buildScanSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Device type'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<NeiryDeviceType>(
                    value: _selectedType,
                    isDense: true,
                    items: NeiryDeviceType.values
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(t.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedType = v);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 72,
              child: TextField(
                controller: _searchTimeController,
                decoration: const InputDecoration(labelText: 'Secs'),
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null && n > 0) setState(() => _searchTime = n);
                },
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _scan,
              child: const Text('Scan'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildScanResults(),
      ],
    );
  }

  Widget _buildScanResults() {
    final params = _scanParams;
    if (params == null) return const SizedBox.shrink();

    final scanAsync = ref.watch(deviceScanProvider(params));

    return scanAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Error: $e',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
      data: (devices) {
        if (devices.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No devices found.'),
          );
        }
        return Column(
          children: devices
              .map(
                (d) => ListTile(
                  title: Text(d.name),
                  subtitle: Text(d.serial),
                  selected: _selectedSerial == d.serial,
                  onTap: () => setState(() => _selectedSerial = d.serial),
                ),
              )
              .toList(),
        );
      },
    );
  }

  // ── Actions section ───────────────────────────────────────────────────────

  Widget _buildActionsSection(DeviceUiState uiState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Actions', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton(
              onPressed: _selectedSerial != null && uiState == DeviceUiState.idle
                  ? _connect
                  : null,
              child: const Text('Connect'),
            ),
            ElevatedButton(
              onPressed: uiState == DeviceUiState.connected ? _start : null,
              child: const Text('Start'),
            ),
            ElevatedButton(
              onPressed: uiState == DeviceUiState.started ? _stop : null,
              child: const Text('Stop'),
            ),
            ElevatedButton(
              onPressed: uiState == DeviceUiState.connected ||
                      uiState == DeviceUiState.started
                  ? _disconnect
                  : null,
              child: const Text('Disconnect'),
            ),
          ],
        ),
      ],
    );
  }

  // ── Status section ────────────────────────────────────────────────────────

  Widget _buildStatusSection(
    DeviceUiState uiState,
    AsyncValue<NeiryConnectionState> connectionAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Status', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('UI state: ${uiState.name}'),
        connectionAsync.when(
          loading: () => const Text('Connection state: …'),
          error: (e, _) => Text('Connection error: $e'),
          data: (cs) => Text('Connection state: ${cs.name}'),
        ),
      ],
    );
  }
}
