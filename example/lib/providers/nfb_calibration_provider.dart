import 'package:flutter_riverpod/legacy.dart';
import 'package:neiry_kit/neiry_kit.dart';

/// Shared cross-tab state holding the most recently produced or imported
/// [IndividualNfbData].
///
/// Written by [calibrationProvider] after a completed run or import.
/// Read by NFB, Productivity, and Cardio classifier providers to initialise
/// their classifiers with individual calibration data.
final nfbCalibrationProvider = StateProvider<IndividualNfbData?>((ref) => null);

/// User preference: pass [nfbCalibrationProvider] as `nfbData` with
/// `useCalibration: true` to [NeiryService.connect] on the next connect,
/// gating MEMS, Productivity, and Cardio classifiers on individual calibration.
/// Flipping it while connected has no immediate effect — the new value takes
/// effect on the next disconnect→connect cycle.
final useCalibrationToggleProvider = StateProvider<bool>((ref) => false);
