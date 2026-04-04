// Integration tests for the Device state machine, classifier factory guards,
// stream return types, and CalibrationEvent sealed dispatch.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neiry_kit/neiry_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─────────────────────────────────────────────────────────────────────────
  // Device state machine — wrong-order throws
  // ─────────────────────────────────────────────────────────────────────────

  group('Device state machine — wrong-order throws', () {
    test('start() before connect() → throws DeviceNotConnectedException',
        () async {
      final device = Device(serial: 'test');
      await expectLater(
        device.start(),
        throwsA(isA<DeviceNotConnectedException>()),
      );
    });

    test('getInfo() before connect() → throws DeviceNotConnectedException',
        () async {
      final device = Device(serial: 'test');
      await expectLater(
        device.getInfo(),
        throwsA(isA<DeviceNotConnectedException>()),
      );
    });

    test(
        'getEEGSampleRate() before connect() → throws DeviceNotConnectedException',
        () async {
      final device = Device(serial: 'test');
      await expectLater(
        device.getEEGSampleRate(),
        throwsA(isA<DeviceNotConnectedException>()),
      );
    });

    test('connect() when already connected → throws StateError', () async {
      final device = Device(serial: 'test');
      final messenger = TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger;

      messenger.setMockMethodCallHandler(
        const MethodChannel(NeiryChannels.device),
        (call) async => null,
      );
      for (final id in [
        NeiryEvents.connectionStatus,
        NeiryEvents.modeSwitched,
        NeiryEvents.battery,
      ]) {
        messenger.setMockMessageHandler(
          id,
          (message) async =>
              const StandardMethodCodec().encodeSuccessEnvelope(null),
        );
      }

      addTearDown(() {
        messenger.setMockMethodCallHandler(
          const MethodChannel(NeiryChannels.device),
          null,
        );
        for (final id in [
          NeiryEvents.connectionStatus,
          NeiryEvents.modeSwitched,
          NeiryEvents.battery,
        ]) {
          messenger.setMockMessageHandler(id, null);
        }
      });

      await device.connect();
      await expectLater(
        device.connect(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('already connected'),
          ),
        ),
      );
    });

    test('methods after dispose() → throws StateError', () async {
      final device = Device(serial: 'test');
      final messenger = TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger;

      messenger.setMockMethodCallHandler(
        const MethodChannel(NeiryChannels.device),
        (call) async => null,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(
            const MethodChannel(NeiryChannels.device),
            null,
          ));

      await device.dispose();

      expect(() => device.eegStream, throwsA(isA<StateError>()));
      expect(() => device.connect(), throwsA(isA<StateError>()));
      expect(() => device.start(), throwsA(isA<StateError>()));
      expect(() => device.getInfo(), throwsA(isA<StateError>()));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Device — initial state
  // ─────────────────────────────────────────────────────────────────────────

  group('Device — initial state', () {
    test('isConnected is false',
        () => expect(Device(serial: 'x').isConnected, isFalse));
    test('isStarted is false',
        () => expect(Device(serial: 'x').isStarted, isFalse));
    test('isValid is true', () => expect(Device(serial: 'x').isValid, isTrue));
    test('battery is null',
        () => expect(Device(serial: 'x').battery, isNull));
    test('mode is null', () => expect(Device(serial: 'x').mode, isNull));
    test('connectionState is disconnected', () {
      expect(
        Device(serial: 'x').connectionState,
        NeiryConnectionState.disconnected,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Classifier factories — throw when device not started
  // ─────────────────────────────────────────────────────────────────────────

  group('Classifier factories — throw when device not started', () {
    test('NfbClassifier(device) → throws StateError', () {
      final device = Device(serial: 'test');
      expect(() => NfbClassifier(device), throwsA(isA<StateError>()));
    });

    test('PhysioClassifier(device) → throws StateError', () {
      final device = Device(serial: 'test');
      expect(() => PhysioClassifier(device), throwsA(isA<StateError>()));
    });

    test('EmotionsClassifier(device) → throws StateError', () {
      final device = Device(serial: 'test');
      expect(() => EmotionsClassifier(device), throwsA(isA<StateError>()));
    });

    test('ProductivityClassifier(device) → throws StateError', () {
      final device = Device(serial: 'test');
      expect(
          () => ProductivityClassifier(device), throwsA(isA<StateError>()));
    });

    test(
        'ProductivityClassifier.withCalibration(device, data) → throws StateError',
        () {
      final device = Device(serial: 'test');
      expect(
        () => ProductivityClassifier.withCalibration(
            device, const IndividualNfbData()),
        throwsA(isA<StateError>()),
      );
    });

    test('CardioClassifier(device) → throws StateError', () {
      final device = Device(serial: 'test');
      expect(() => CardioClassifier(device), throwsA(isA<StateError>()));
    });

    test('CardioClassifier.withCalibration(device, data) → throws StateError',
        () {
      final device = Device(serial: 'test');
      expect(
        () => CardioClassifier.withCalibration(
            device, const IndividualNfbData()),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Device streams — return types match models
  // ─────────────────────────────────────────────────────────────────────────

  group('Device streams — return types match models', () {
    test('eegStream is Stream<EegData>', () {
      expect(Device(serial: 'test').eegStream, isA<Stream<EegData>>());
    });

    test('psdStream is Stream<PsdData>', () {
      expect(Device(serial: 'test').psdStream, isA<Stream<PsdData>>());
    });

    test('artifactsStream is Stream<EegArtifactData>', () {
      expect(Device(serial: 'test').artifactsStream,
          isA<Stream<EegArtifactData>>());
    });

    test('resistanceStream is Stream<ResistanceData>', () {
      expect(Device(serial: 'test').resistanceStream,
          isA<Stream<ResistanceData>>());
    });

    test('batteryStream is Stream<int>', () {
      expect(Device(serial: 'test').batteryStream, isA<Stream<int>>());
    });

    test('errorStream is Stream<String>', () {
      expect(Device(serial: 'test').errorStream, isA<Stream<String>>());
    });

    test('connectionStateStream is Stream<NeiryConnectionState>', () {
      expect(
        Device(serial: 'test').connectionStateStream,
        isA<Stream<NeiryConnectionState>>(),
      );
    });

    test('modeChangedStream is Stream<NeiryDeviceMode>', () {
      expect(
        Device(serial: 'test').modeChangedStream,
        isA<Stream<NeiryDeviceMode>>(),
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // CalibrationEvent — sealed dispatch is exhaustive
  // ─────────────────────────────────────────────────────────────────────────

  group('CalibrationEvent — sealed dispatch is exhaustive', () {
    test('switch covers all subtypes', () {
      final events = <CalibrationEvent>[
        const CalibrationStageFinished(stage: CalibrationStage.stage1),
        const CalibrationCompleted(data: IndividualNfbData()),
      ];
      for (final event in events) {
        final label = switch (event) {
          CalibrationStageFinished(:final stage) => 'stage:${stage.code}',
          CalibrationCompleted(:final data) => 'done:${data.individualFrequency}',
        };
        expect(label, isNotEmpty);
      }
    });

    test('CalibrationStageFinished carries correct stage', () {
      const event = CalibrationStageFinished(stage: CalibrationStage.stage3);
      expect(event.stage, CalibrationStage.stage3);
    });

    test('CalibrationCompleted carries correct data', () {
      const event = CalibrationCompleted(
        data: IndividualNfbData(individualFrequency: 11.5),
      );
      expect(event.data.individualFrequency, 11.5);
    });
  });
}
