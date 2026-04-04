// When adding new constants to channel_names.dart or enums.dart, add them to
// the corresponding list here so the uniqueness checks stay in sync as the
// channel contract grows.

import 'package:flutter_test/flutter_test.dart';
import 'package:neiry_kit/neiry_kit.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // Channel ID uniqueness
  // ─────────────────────────────────────────────────────────────────────────

  group('NeiryChannels — MethodChannel IDs are unique', () {
    final ids = [
      NeiryChannels.deviceLocator,
      NeiryChannels.device,
      NeiryChannels.nfb,
      NeiryChannels.physiological,
      NeiryChannels.emotions,
      NeiryChannels.productivity,
      NeiryChannels.cardio,
      NeiryChannels.nfbCalibrator,
    ];

    test('no duplicates', () {
      expect(ids.length, equals(Set<String>.from(ids).length));
    });
  });

  group('NeiryEvents — EventChannel IDs are unique', () {
    final ids = [
      NeiryEvents.deviceList,
      NeiryEvents.eeg,
      NeiryEvents.psd,
      NeiryEvents.eegArtifacts,
      NeiryEvents.resistance,
      NeiryEvents.battery,
      NeiryEvents.connectionStatus,
      NeiryEvents.modeSwitched,
      NeiryEvents.nfbState,
      NeiryEvents.physiologicalState,
      NeiryEvents.emotionsState,
      NeiryEvents.productivityMetrics,
      NeiryEvents.productivityIndexes,
      NeiryEvents.cardioData,
      NeiryEvents.ppgData,
      NeiryEvents.memsData,
      NeiryEvents.nfbCalibration,
      NeiryEvents.physiologicalCalibrationProgress,
      NeiryEvents.physiologicalCalibrated,
      NeiryEvents.productivityCalibrationProgress,
      NeiryEvents.productivityCalibrated,
      NeiryEvents.cardioCalibratedEvent,
      NeiryEvents.error,
      NeiryEvents.nfbError,
      NeiryEvents.emotionsError,
      NeiryEvents.productivityError,
    ];

    test('no duplicates', () {
      expect(ids.length, equals(Set<String>.from(ids).length));
    });

    test('count is 26', () {
      expect(ids.length, equals(26));
    });
  });

  group('No overlap between MethodChannel and EventChannel IDs', () {
    final methodIds = {
      NeiryChannels.deviceLocator,
      NeiryChannels.device,
      NeiryChannels.nfb,
      NeiryChannels.physiological,
      NeiryChannels.emotions,
      NeiryChannels.productivity,
      NeiryChannels.cardio,
      NeiryChannels.nfbCalibrator,
    };
    final eventIds = {
      NeiryEvents.deviceList,
      NeiryEvents.eeg,
      NeiryEvents.psd,
      NeiryEvents.eegArtifacts,
      NeiryEvents.resistance,
      NeiryEvents.battery,
      NeiryEvents.connectionStatus,
      NeiryEvents.modeSwitched,
      NeiryEvents.nfbState,
      NeiryEvents.physiologicalState,
      NeiryEvents.emotionsState,
      NeiryEvents.productivityMetrics,
      NeiryEvents.productivityIndexes,
      NeiryEvents.cardioData,
      NeiryEvents.ppgData,
      NeiryEvents.memsData,
      NeiryEvents.nfbCalibration,
      NeiryEvents.physiologicalCalibrationProgress,
      NeiryEvents.physiologicalCalibrated,
      NeiryEvents.productivityCalibrationProgress,
      NeiryEvents.productivityCalibrated,
      NeiryEvents.cardioCalibratedEvent,
      NeiryEvents.error,
      NeiryEvents.nfbError,
      NeiryEvents.emotionsError,
      NeiryEvents.productivityError,
    };

    test('intersection is empty', () {
      expect(methodIds.intersection(eventIds), isEmpty);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Method name uniqueness
  // ─────────────────────────────────────────────────────────────────────────

  group('DeviceLocatorMethods — unique', () {
    final names = [
      DeviceLocatorMethods.create,
      DeviceLocatorMethods.createDevice,
      DeviceLocatorMethods.dispose,
      DeviceLocatorMethods.update,
      DeviceLocatorMethods.setSingleThreaded,
      DeviceLocatorMethods.setLogLevel,
      DeviceLocatorMethods.getVersionString,
    ];

    test('no duplicates', () {
      expect(names.length, equals(Set<String>.from(names).length));
    });
  });

  group('DeviceMethods — unique', () {
    final names = [
      DeviceMethods.createDevice,
      DeviceMethods.connect,
      DeviceMethods.disconnect,
      DeviceMethods.start,
      DeviceMethods.stop,
      DeviceMethods.getMode,
      DeviceMethods.isConnected,
      DeviceMethods.getBatteryCharge,
      DeviceMethods.getInfo,
      DeviceMethods.getEEGSampleRate,
      DeviceMethods.getPPGSampleRate,
      DeviceMethods.getMEMSSampleRate,
      DeviceMethods.getPPGIrAmplitude,
      DeviceMethods.getPPGRedAmplitude,
      DeviceMethods.getChannelNames,
      DeviceMethods.getChannelIndexByName,
      DeviceMethods.getChannelNameByIndex,
      DeviceMethods.getChannelsCount,
    ];

    test('no duplicates', () {
      expect(names.length, equals(Set<String>.from(names).length));
    });
  });

  group('ClassifierMethods — unique', () {
    final names = [
      ClassifierMethods.create,
      ClassifierMethods.createCalibrated,
      ClassifierMethods.startBaselineCalibration,
      ClassifierMethods.stopBaselineCalibration,
      ClassifierMethods.importBaselines,
      ClassifierMethods.resetAccumulatedFatigue,
    ];

    test('no duplicates', () {
      expect(names.length, equals(Set<String>.from(names).length));
    });
  });

  group('NFBCalibratorMethods — unique', () {
    final names = [
      NFBCalibratorMethods.startCalibration,
      NFBCalibratorMethods.stopCalibration,
      NFBCalibratorMethods.importCalibration,
      NFBCalibratorMethods.getCalibration,
      NFBCalibratorMethods.isCalibrated,
    ];

    test('no duplicates', () {
      expect(names.length, equals(Set<String>.from(names).length));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Argument key uniqueness
  // ─────────────────────────────────────────────────────────────────────────

  group('NeiryArgs — unique', () {
    final keys = [
      NeiryArgs.serial,
      NeiryArgs.logDirectory,
      NeiryArgs.deviceType,
      NeiryArgs.searchTime,
      NeiryArgs.mode,
      NeiryArgs.level,
      NeiryArgs.enabled,
      NeiryArgs.baselines,
      NeiryArgs.calibrationData,
      NeiryArgs.calibratorData,
      NeiryArgs.channelName,
      NeiryArgs.index,
      NeiryArgs.bipolarChannels,
    ];

    test('no duplicates', () {
      expect(keys.length, equals(Set<String>.from(keys).length));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Enum int codes match SDK
  // ─────────────────────────────────────────────────────────────────────────

  group('NeiryDeviceType int codes match SDK', () {
    test('headband == 0', () => expect(NeiryDeviceType.headband.code, 0));
    test('buds == 1', () => expect(NeiryDeviceType.buds.code, 1));
    test('headphones == 2', () => expect(NeiryDeviceType.headphones.code, 2));
    test('impulse == 3', () => expect(NeiryDeviceType.impulse.code, 3));
    test('any == 4', () => expect(NeiryDeviceType.any.code, 4));
    test('brainBit == 6', () => expect(NeiryDeviceType.brainBit.code, 6));
    test('sinWave == 100', () => expect(NeiryDeviceType.sinWave.code, 100));
    test('noise == 101', () => expect(NeiryDeviceType.noise.code, 101));
  });

  group('NeiryDeviceMode int codes match SDK', () {
    test('resistance == 0', () => expect(NeiryDeviceMode.resistance.code, 0));
    test('signal == 1', () => expect(NeiryDeviceMode.signal.code, 1));
    test('signalAndResist == 2',
        () => expect(NeiryDeviceMode.signalAndResist.code, 2));
    test('startMEMS == 3', () => expect(NeiryDeviceMode.startMEMS.code, 3));
    test('stopMEMS == 4', () => expect(NeiryDeviceMode.stopMEMS.code, 4));
    test('startPPG == 5', () => expect(NeiryDeviceMode.startPPG.code, 5));
    test('stopPPG == 6', () => expect(NeiryDeviceMode.stopPPG.code, 6));
  });

  group('NeiryConnectionState int codes match SDK', () {
    test('disconnected == 0',
        () => expect(NeiryConnectionState.disconnected.code, 0));
    test('connected == 1',
        () => expect(NeiryConnectionState.connected.code, 1));
    test('unsupportedConnection == 2',
        () => expect(NeiryConnectionState.unsupportedConnection.code, 2));
  });

  // ─────────────────────────────────────────────────────────────────────────
  // fromCode round-trips
  // ─────────────────────────────────────────────────────────────────────────

  group('NeiryDeviceType.fromCode round-trips', () {
    for (final v in NeiryDeviceType.values) {
      test(v.name, () => expect(NeiryDeviceType.fromCode(v.code), v));
    }
  });

  group('NeiryDeviceMode.fromCode round-trips', () {
    for (final v in NeiryDeviceMode.values) {
      test(v.name, () => expect(NeiryDeviceMode.fromCode(v.code), v));
    }
  });

  group('NeiryConnectionState.fromCode round-trips', () {
    for (final v in NeiryConnectionState.values) {
      test(
          v.name, () => expect(NeiryConnectionState.fromCode(v.code), v));
    }
  });

  // ─────────────────────────────────────────────────────────────────────────
  // fromCode throws on unknown code
  // ─────────────────────────────────────────────────────────────────────────

  group('fromCode throws ArgumentError for unknown codes', () {
    test('NeiryDeviceType.fromCode(999)',
        () => expect(() => NeiryDeviceType.fromCode(999), throwsArgumentError));
    test('NeiryDeviceMode.fromCode(999)',
        () => expect(() => NeiryDeviceMode.fromCode(999), throwsArgumentError));
    test(
        'NeiryConnectionState.fromCode(999)',
        () => expect(
            () => NeiryConnectionState.fromCode(999), throwsArgumentError));
  });
}
