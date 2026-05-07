import 'package:flutter_riverpod/legacy.dart';
import 'package:neiry_kit/neiry_kit.dart';

/// Shared cross-tab state holding the most recently produced or imported
/// [IndividualNfbData].
///
/// Written by [calibrationProvider] after a completed run or import.
/// Read by NFB, Productivity, and Cardio classifier providers to initialise
/// their classifiers with individual calibration data.
final nfbCalibrationProvider = StateProvider<IndividualNfbData?>((ref) => null);
