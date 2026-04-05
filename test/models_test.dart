import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neiry_kit/neiry_kit.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // NeiryErrorCode — int codes match SDK
  // ─────────────────────────────────────────────────────────────────────────

  group('NeiryErrorCode int codes match SDK', () {
    test('ok == 0', () => expect(NeiryErrorCode.ok.code, 0));
    test('failedToConnect == 1',
        () => expect(NeiryErrorCode.failedToConnect.code, 1));
    test('failedToInitConnection == 2',
        () => expect(NeiryErrorCode.failedToInitConnection.code, 2));
    test('failedToInitialize == 3',
        () => expect(NeiryErrorCode.failedToInitialize.code, 3));
    test('deviceError == 4',
        () => expect(NeiryErrorCode.deviceError.code, 4));
    test('individualNfbNotCalibrated == 5',
        () => expect(NeiryErrorCode.individualNfbNotCalibrated.code, 5));
    test('notReceived == 6',
        () => expect(NeiryErrorCode.notReceived.code, 6));
    test('nullPointer == 7',
        () => expect(NeiryErrorCode.nullPointer.code, 7));
    test('moduleAlreadyExists == 8',
        () => expect(NeiryErrorCode.moduleAlreadyExists.code, 8));
    test('moduleIsNotSupported == 9',
        () => expect(NeiryErrorCode.moduleIsNotSupported.code, 9));
    test('failedToSendData == 10',
        () => expect(NeiryErrorCode.failedToSendData.code, 10));
    test('indexOutOfRange == 11',
        () => expect(NeiryErrorCode.indexOutOfRange.code, 11));
    test('emptyCollection == 12',
        () => expect(NeiryErrorCode.emptyCollection.code, 12));
    test('notFound == 13',
        () => expect(NeiryErrorCode.notFound.code, 13));
    test('sizeMismatch == 14',
        () => expect(NeiryErrorCode.sizeMismatch.code, 14));
    test('unknownEnum == 15',
        () => expect(NeiryErrorCode.unknownEnum.code, 15));
    test('unknown == 255',
        () => expect(NeiryErrorCode.unknown.code, 255));
  });

  group('NeiryErrorCode.fromCode round-trips', () {
    for (final v in NeiryErrorCode.values) {
      test(v.name, () => expect(NeiryErrorCode.fromCode(v.code), v));
    }
  });

  group('NeiryErrorCode.fromCode throws on unknown', () {
    test('code 999',
        () => expect(() => NeiryErrorCode.fromCode(999), throwsArgumentError));
  });

  // ─────────────────────────────────────────────────────────────────────────
  // CalibrationStage — int codes match SDK
  // ─────────────────────────────────────────────────────────────────────────

  group('CalibrationStage int codes match SDK', () {
    test('stage1 == 0', () => expect(CalibrationStage.stage1.code, 0));
    test('stage2 == 1', () => expect(CalibrationStage.stage2.code, 1));
    test('stage3 == 2', () => expect(CalibrationStage.stage3.code, 2));
    test('stage4 == 3', () => expect(CalibrationStage.stage4.code, 3));
  });

  group('CalibrationStage.fromCode round-trips', () {
    for (final v in CalibrationStage.values) {
      test(v.name, () => expect(CalibrationStage.fromCode(v.code), v));
    }
  });

  group('CalibrationStage.fromCode throws on unknown', () {
    test('code 99',
        () => expect(
            () => CalibrationStage.fromCode(99), throwsArgumentError));
  });

  // ─────────────────────────────────────────────────────────────────────────
  // NfbCalibrationFailReason — int codes match SDK
  // ─────────────────────────────────────────────────────────────────────────

  group('NfbCalibrationFailReason int codes match SDK', () {
    test('none == 0', () => expect(NfbCalibrationFailReason.none.code, 0));
    test('tooManyArtifacts == 1',
        () => expect(NfbCalibrationFailReason.tooManyArtifacts.code, 1));
    test('peakFrequencyAtBorder == 2',
        () => expect(NfbCalibrationFailReason.peakFrequencyAtBorder.code, 2));
  });

  group('NfbCalibrationFailReason.fromCode round-trips', () {
    for (final v in NfbCalibrationFailReason.values) {
      test(v.name,
          () => expect(NfbCalibrationFailReason.fromCode(v.code), v));
    }
  });

  group('NfbCalibrationFailReason.fromCode throws on unknown', () {
    test('code 99',
        () => expect(() => NfbCalibrationFailReason.fromCode(99),
            throwsArgumentError));
  });

  // ─────────────────────────────────────────────────────────────────────────
  // NfbUserState.fromMap — sentinel fields become null
  // ─────────────────────────────────────────────────────────────────────────

  group('NfbUserState.fromMap — sentinel fields become null', () {
    test('all bands -1.0 → all null', () {
      final state = NfbUserState.fromMap({
        'ts': 1000,
        'delta': -1.0,
        'theta': -1.0,
        'alpha': -1.0,
        'smr': -1.0,
        'beta': -1.0,
      });
      expect(state.delta, isNull);
      expect(state.theta, isNull);
      expect(state.alpha, isNull);
      expect(state.smr, isNull);
      expect(state.beta, isNull);
    });

    test('all bands 0.5 → all populated', () {
      final state = NfbUserState.fromMap({
        'ts': 1000,
        'delta': 0.5,
        'theta': 0.5,
        'alpha': 0.5,
        'smr': 0.5,
        'beta': 0.5,
      });
      expect(state.delta, 0.5);
      expect(state.theta, 0.5);
      expect(state.alpha, 0.5);
      expect(state.smr, 0.5);
      expect(state.beta, 0.5);
    });

    test('int sentinel -1 → all null', () {
      final state = NfbUserState.fromMap({
        'ts': 1000,
        'delta': -1,
        'theta': -1,
        'alpha': -1,
        'smr': -1,
        'beta': -1,
      });
      expect(state.delta, isNull);
      expect(state.theta, isNull);
      expect(state.alpha, isNull);
      expect(state.smr, isNull);
      expect(state.beta, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // PhysiologicalStatesValue.fromMap — sentinel fields become null
  // ─────────────────────────────────────────────────────────────────────────

  group('PhysiologicalStatesValue.fromMap — sentinel fields become null', () {
    test('all nullable fields -1.0 → all null; bool fields valid', () {
      final state = PhysiologicalStatesValue.fromMap({
        'ts': 1000,
        'relaxation': -1.0,
        'fatigue': -1.0,
        'none': -1.0,
        'concentration': -1.0,
        'involvement': -1.0,
        'stress': -1.0,
        'nfbArtifacts': true,
        'cardioArtifacts': false,
      });
      expect(state.relaxation, isNull);
      expect(state.fatigue, isNull);
      expect(state.none, isNull);
      expect(state.concentration, isNull);
      expect(state.involvement, isNull);
      expect(state.stress, isNull);
      expect(state.nfbArtifacts, isTrue);
      expect(state.cardioArtifacts, isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // PhysiologicalStatesBaselines.fromMap — round-trip + sentinels
  // ─────────────────────────────────────────────────────────────────────────

  group('PhysiologicalStatesBaselines.fromMap — round-trip + sentinels', () {
    test('all fields -1 / -1.0 → all null', () {
      final baselines = PhysiologicalStatesBaselines.fromMap({
        'ts': -1,
        'alpha': -1.0,
        'beta': -1.0,
        'alphaGravity': -1.0,
        'betaGravity': -1.0,
        'concentration': -1.0,
      });
      expect(baselines.timestamp, isNull);
      expect(baselines.alpha, isNull);
      expect(baselines.beta, isNull);
      expect(baselines.alphaGravity, isNull);
      expect(baselines.betaGravity, isNull);
      expect(baselines.concentration, isNull);
    });

    test('valid values → fromMap → toMap round-trip', () {
      final map = <Object?, Object?>{
        'ts': 1000,
        'alpha': 0.5,
        'beta': 0.6,
        'alphaGravity': 0.7,
        'betaGravity': 0.8,
        'concentration': 0.9,
      };
      final baselines = PhysiologicalStatesBaselines.fromMap(map);
      final result = baselines.toMap();
      expect(result['ts'], 1000);
      expect(result['alpha'], 0.5);
      expect(result['beta'], 0.6);
      expect(result['alphaGravity'], 0.7);
      expect(result['betaGravity'], 0.8);
      expect(result['concentration'], 0.9);
    });

    test('mixed: some valid, some sentinel', () {
      final baselines = PhysiologicalStatesBaselines.fromMap({
        'ts': 2000,
        'alpha': 0.5,
        'beta': -1.0,
        'alphaGravity': -1.0,
        'betaGravity': 0.8,
        'concentration': -1.0,
      });
      expect(baselines.timestamp, DateTime.fromMillisecondsSinceEpoch(2000));
      expect(baselines.alpha, 0.5);
      expect(baselines.beta, isNull);
      expect(baselines.alphaGravity, isNull);
      expect(baselines.betaGravity, 0.8);
      expect(baselines.concentration, isNull);
      final result = baselines.toMap();
      expect(result['beta'], -1.0);
      expect(result['alphaGravity'], -1.0);
      expect(result['concentration'], -1.0);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // EmotionsStates.fromMap — sentinel fields become null
  // ─────────────────────────────────────────────────────────────────────────

  group('EmotionsStates.fromMap — sentinel fields become null', () {
    test('all fields -1 (int) → all null', () {
      final state = EmotionsStates.fromMap({
        'ts': 1000,
        'attention': -1,
        'relaxation': -1,
        'cognitiveLoad': -1,
        'cognitiveControl': -1,
        'selfControl': -1,
      });
      expect(state.attention, isNull);
      expect(state.relaxation, isNull);
      expect(state.cognitiveLoad, isNull);
      expect(state.cognitiveControl, isNull);
      expect(state.selfControl, isNull);
    });

    test('all fields valid → all populated', () {
      final state = EmotionsStates.fromMap({
        'ts': 1000,
        'attention': 0.3,
        'relaxation': 0.4,
        'cognitiveLoad': 0.5,
        'cognitiveControl': 0.6,
        'selfControl': 0.7,
      });
      expect(state.attention, 0.3);
      expect(state.relaxation, 0.4);
      expect(state.cognitiveLoad, 0.5);
      expect(state.cognitiveControl, 0.6);
      expect(state.selfControl, 0.7);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // ProductivityBaselines.fromMap — sentinel fields become null
  // ─────────────────────────────────────────────────────────────────────────

  group('ProductivityBaselines.fromMap — sentinel fields become null', () {
    test('all fields -1.0 → all null', () {
      final baselines = ProductivityBaselines.fromMap({
        'ts': 1000,
        'gravity': -1.0,
        'productivity': -1.0,
        'fatigue': -1.0,
        'reverseFatigue': -1.0,
        'relaxation': -1.0,
        'concentration': -1.0,
      });
      expect(baselines.gravity, isNull);
      expect(baselines.productivity, isNull);
      expect(baselines.fatigue, isNull);
      expect(baselines.reverseFatigue, isNull);
      expect(baselines.relaxation, isNull);
      expect(baselines.concentration, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // ProductivityIndexes.fromMap — sentinel + always-valid fields
  // ─────────────────────────────────────────────────────────────────────────

  group('ProductivityIndexes.fromMap — sentinel + always-valid fields', () {
    test('nullable float fields sentinel → null; int/bool fields valid', () {
      final indexes = ProductivityIndexes.fromMap({
        'ts': 1000,
        'gravityBaseline': -1.0,
        'productivityBaseline': -1.0,
        'fatigueBaseline': -1.0,
        'reverseFatigueBaseline': -1.0,
        'relaxationBaseline': -1.0,
        'concentrationBaseline': -1.0,
        'relaxation': 2,
        'stress': 1,
        'hasArtifacts': true,
      });
      expect(indexes.gravityBaseline, isNull);
      expect(indexes.productivityBaseline, isNull);
      expect(indexes.fatigueBaseline, isNull);
      expect(indexes.reverseFatigueBaseline, isNull);
      expect(indexes.relaxationBaseline, isNull);
      expect(indexes.concentrationBaseline, isNull);
      expect(indexes.relaxation, 2);
      expect(indexes.stress, 1);
      expect(indexes.hasArtifacts, isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // DeviceInfo.fromMap
  // ─────────────────────────────────────────────────────────────────────────

  group('DeviceInfo.fromMap', () {
    test('construction from map', () {
      final info = DeviceInfo.fromMap({
        'serial': 'ABC123',
        'name': 'Neiry Headband',
        'type': 0,
      });
      expect(info.serial, 'ABC123');
      expect(info.name, 'Neiry Headband');
      expect(info.type, NeiryDeviceType.headband);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // NeiryError.fromMap
  // ─────────────────────────────────────────────────────────────────────────

  group('NeiryError.fromMap', () {
    test('message, success, code round-trip', () {
      final error = NeiryError.fromMap({
        'message': 'Something went wrong',
        'success': false,
        'code': 1,
      });
      expect(error.message, 'Something went wrong');
      expect(error.success, isFalse);
      expect(error.code, NeiryErrorCode.failedToConnect);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // ProductivityMetrics.fromMap — Uint8List? cases + sentinel
  // ─────────────────────────────────────────────────────────────────────────

  group('ProductivityMetrics.fromMap — Uint8List? size=0 case', () {
    Map<Object?, Object?> baseMap({Object? artifactsData}) => {
          'ts': 1000,
          'fatigueGrowthRate': 0,
          'fatigueScore': -1.0,
          'reverseFatigueScore': -1.0,
          'gravityScore': -1.0,
          'relaxationScore': -1.0,
          'concentrationScore': -1.0,
          'productivityScore': -1.0,
          'currentValue': -1.0,
          'alpha': -1.0,
          'productivityBaseline': -1.0,
          'accumulatedFatigue': -1.0,
          'artifactsData': artifactsData,
        };

    test('artifactsData null → field is null', () {
      final m = ProductivityMetrics.fromMap(baseMap());
      expect(m.artifactsData, isNull);
    });

    test('artifactsData Uint8List(0) → field is empty Uint8List', () {
      final m =
          ProductivityMetrics.fromMap(baseMap(artifactsData: Uint8List(0)));
      expect(m.artifactsData, isNotNull);
      expect(m.artifactsData!.length, 0);
    });

    test('artifactsData Uint8List.fromList([1,2,3]) → field has length 3', () {
      final m = ProductivityMetrics.fromMap(
        baseMap(artifactsData: Uint8List.fromList([1, 2, 3])),
      );
      expect(m.artifactsData, isNotNull);
      expect(m.artifactsData!.length, 3);
      expect(m.artifactsData, [1, 2, 3]);
    });

    test('all nullable double fields sentinel → all null', () {
      final m = ProductivityMetrics.fromMap(baseMap());
      expect(m.fatigueScore, isNull);
      expect(m.reverseFatigueScore, isNull);
      expect(m.gravityScore, isNull);
      expect(m.relaxationScore, isNull);
      expect(m.concentrationScore, isNull);
      expect(m.productivityScore, isNull);
      expect(m.currentValue, isNull);
      expect(m.alpha, isNull);
      expect(m.productivityBaseline, isNull);
      expect(m.accumulatedFatigue, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // CalibrationEvent.deserialize — dispatch by type key
  // ─────────────────────────────────────────────────────────────────────────

  group('CalibrationEvent.deserialize — dispatch by type key', () {
    test("type 'stage' → CalibrationStageFinished with stage3", () {
      final event =
          CalibrationEvent.deserialize({'type': 'stage', 'stage': 2});
      expect(event, isA<CalibrationStageFinished>());
      expect((event as CalibrationStageFinished).stage,
          CalibrationStage.stage3);
    });

    test("type 'done' → CalibrationCompleted with isValid true", () {
      final dataMap = <Object?, Object?>{
        'ts': 1000000,
        'failReason': 0,
        'individualFrequency': 10.5,
        'individualPeakFrequency': 10.5,
        'individualPeakFrequencyPower': 3.2,
        'individualPeakFrequencySuppression': 2.1,
        'individualBandwidth': 5.5,
        'individualNormalizedPower': 0.7,
        'lowerFrequency': 8.0,
        'upperFrequency': 13.0,
      };
      final event = CalibrationEvent.deserialize(
          {'type': 'done', 'data': dataMap});
      expect(event, isA<CalibrationCompleted>());
      expect((event as CalibrationCompleted).data.isValid, isTrue);
    });

    test("type 'bogus' → throws ArgumentError", () {
      expect(
        () => CalibrationEvent.deserialize({'type': 'bogus'}),
        throwsArgumentError,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // IndividualNfbData — fromMap → toMap → fromMap round-trip
  // ─────────────────────────────────────────────────────────────────────────

  group('IndividualNfbData — fromMap → toMap → fromMap round-trip', () {
    test('all fields set round-trips correctly', () {
      final original = <Object?, Object?>{
        'ts': 1000000,
        'failReason': 0,
        'individualFrequency': 10.5,
        'individualPeakFrequency': 10.6,
        'individualPeakFrequencyPower': 3.2,
        'individualPeakFrequencySuppression': 2.1,
        'individualBandwidth': 5.5,
        'individualNormalizedPower': 0.7,
        'lowerFrequency': 8.0,
        'upperFrequency': 13.0,
      };
      final first = IndividualNfbData.fromMap(original);
      final second = IndividualNfbData.fromMap(first.toMap());
      expect(second.timestamp, first.timestamp);
      expect(second.failReason, first.failReason);
      expect(second.individualFrequency, first.individualFrequency);
      expect(second.individualPeakFrequency, first.individualPeakFrequency);
      expect(second.individualPeakFrequencyPower,
          first.individualPeakFrequencyPower);
      expect(second.individualPeakFrequencySuppression,
          first.individualPeakFrequencySuppression);
      expect(second.individualBandwidth, first.individualBandwidth);
      expect(second.individualNormalizedPower, first.individualNormalizedPower);
      expect(second.lowerFrequency, first.lowerFrequency);
      expect(second.upperFrequency, first.upperFrequency);
    });

    test('ts: -1 → timestamp null; round-trips back to null', () {
      final map = <Object?, Object?>{
        'ts': -1,
        'failReason': 0,
        'individualFrequency': 10.0,
        'individualPeakFrequency': 10.0,
        'individualPeakFrequencyPower': 3.0,
        'individualPeakFrequencySuppression': 2.0,
        'individualBandwidth': 6.0,
        'individualNormalizedPower': 0.5,
        'lowerFrequency': 7.0,
        'upperFrequency': 13.0,
      };
      final first = IndividualNfbData.fromMap(map);
      expect(first.timestamp, isNull);
      final serialized = first.toMap();
      expect(serialized['ts'], -1);
      final second = IndividualNfbData.fromMap(serialized);
      expect(second.timestamp, isNull);
    });
  });
}
