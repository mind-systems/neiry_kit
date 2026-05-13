import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:neiry_kit/neiry_kit.dart';

import 'active_device_provider.dart';

/// Emits [NeiryDeviceMode] whenever the active device changes its operating mode.
///
/// Emits nothing ([Stream.empty]) when no device is active.
final deviceModeProvider = StreamProvider<NeiryDeviceMode>((ref) {
  final device = ref.watch(activeDeviceProvider);
  if (device == null) return const Stream.empty();
  return device.modeChangedStream;
});

/// Emits the current BLE connection state of the active device.
///
/// Falls back to [NeiryConnectionState.disconnected] when no device is active.
final deviceConnectionStateProvider = StreamProvider<NeiryConnectionState>(
  (ref) {
    final device = ref.watch(activeDeviceProvider);
    if (device == null) return Stream.value(NeiryConnectionState.disconnected);
    return device.connectionStateStream;
  },
);

/// Whether EEG streaming is currently active on the connected device.
///
/// Set to `true` after a successful `device.start()` call;
/// reset to `false` after `device.stop()` or `disconnectAndDispose()`.
final deviceIsStartedProvider = StateProvider<bool>((ref) => false);

/// Coarse UI state derived from connection + started flag.
enum DeviceUiState {
  /// No device connected (includes connecting in progress).
  idle,

  /// Device is connected but EEG streaming has not been started.
  connected,

  /// Device is connected and EEG streaming is active.
  started,
}

/// Derives a single [DeviceUiState] from the connection stream and started flag.
final deviceUiStateProvider = Provider<DeviceUiState>((ref) {
  final connectionAsync = ref.watch(deviceConnectionStateProvider);
  final isStarted = ref.watch(deviceIsStartedProvider);

  final connectionState = connectionAsync.whenOrNull(data: (s) => s);

  if (connectionState != NeiryConnectionState.connected) {
    return DeviceUiState.idle;
  }
  if (isStarted) return DeviceUiState.started;
  return DeviceUiState.connected;
});
