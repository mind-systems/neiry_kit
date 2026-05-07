// Platform channel IDs, method names, and argument keys shared by the
// Dart API layer and native bridges.  String literals are defined here
// once — never duplicated in application code.

// ──────────────────────────────────────────────────────────────────────────────
// MethodChannel IDs
// ──────────────────────────────────────────────────────────────────────────────

/// MethodChannel IDs — one channel per C API module.
abstract final class NeiryChannels {
  static const String deviceLocator = 'neiry_kit/device_locator';
  static const String device = 'neiry_kit/device';
  static const String nfb = 'neiry_kit/nfb';
  static const String physiological = 'neiry_kit/physiological';
  static const String emotions = 'neiry_kit/emotions';
  static const String productivity = 'neiry_kit/productivity';
  static const String cardio = 'neiry_kit/cardio';
  static const String mems = 'neiry_kit/mems';
  static const String nfbCalibrator = 'neiry_kit/nfb_calibrator';
}

// ──────────────────────────────────────────────────────────────────────────────
// EventChannel IDs
// ──────────────────────────────────────────────────────────────────────────────

/// EventChannel IDs — one channel per SDK callback / data stream.
abstract final class NeiryEvents {
  static const String deviceList = 'neiry_kit/events/deviceList';
  static const String eeg = 'neiry_kit/events/eeg';
  static const String psd = 'neiry_kit/events/psd';
  static const String eegArtifacts = 'neiry_kit/events/eegArtifacts';
  static const String resistance = 'neiry_kit/events/resistance';
  static const String battery = 'neiry_kit/events/battery';
  static const String connectionStatus = 'neiry_kit/events/connectionStatus';
  static const String modeSwitched = 'neiry_kit/events/modeSwitched';
  static const String nfbState = 'neiry_kit/events/nfbState';
  static const String physiologicalState = 'neiry_kit/events/physiologicalState';
  static const String emotionsState = 'neiry_kit/events/emotionsState';
  static const String productivityMetrics = 'neiry_kit/events/productivityMetrics';
  static const String productivityIndexes = 'neiry_kit/events/productivityIndexes';
  static const String cardioData = 'neiry_kit/events/cardioData';
  static const String ppgData = 'neiry_kit/events/ppgData';
  static const String memsData = 'neiry_kit/events/memsData';
  static const String nfbCalibration = 'neiry_kit/events/nfbCalibration';
  static const String physiologicalCalibrationProgress =
      'neiry_kit/events/physiologicalCalibrationProgress';
  static const String physiologicalCalibrated =
      'neiry_kit/events/physiologicalCalibrated';
  static const String physiologicalIndividualNfb =
      'neiry_kit/events/physiologicalIndividualNfb';
  static const String productivityCalibrationProgress =
      'neiry_kit/events/productivityCalibrationProgress';
  static const String productivityCalibrated =
      'neiry_kit/events/productivityCalibrated';
  static const String productivityBaselines =
      'neiry_kit/events/productivityBaselines';
  static const String productivityIndividualNfb =
      'neiry_kit/events/productivityIndividualNfb';
  // NOTE: exact native callback name for cardio calibration needs confirmation
  // from _c_cardio_8h when implementing iOS/Android bridges.
  static const String cardioCalibratedEvent =
      'neiry_kit/events/cardioCalibratedEvent';
  static const String error = 'neiry_kit/events/error';
  static const String nfbError = 'neiry_kit/events/nfbError';
  static const String emotionsError = 'neiry_kit/events/emotionsError';
  static const String productivityError = 'neiry_kit/events/productivityError';
}

// ──────────────────────────────────────────────────────────────────────────────
// Method names
// ──────────────────────────────────────────────────────────────────────────────

/// Method names for the DeviceLocator MethodChannel.
abstract final class DeviceLocatorMethods {
  static const String create = 'create';
  static const String createDevice = 'createDevice';
  static const String dispose = 'dispose';
  static const String update = 'update';
  static const String setSingleThreaded = 'setSingleThreaded';
  static const String setLogLevel = 'setLogLevel';
  static const String getVersionString = 'getVersionString';
}

/// Method names for the Device MethodChannel.
abstract final class DeviceMethods {
  static const String createDevice = 'createDevice';
  static const String connect = 'connect';
  static const String disconnect = 'disconnect';
  static const String start = 'start';
  static const String stop = 'stop';
  static const String getMode = 'getMode';
  static const String isConnected = 'isConnected';
  static const String getBatteryCharge = 'getBatteryCharge';
  static const String getInfo = 'getInfo';
  static const String getEEGSampleRate = 'getEEGSampleRate';
  static const String getPPGSampleRate = 'getPPGSampleRate';
  static const String getMEMSSampleRate = 'getMEMSSampleRate';
  static const String getPPGIrAmplitude = 'getPPGIrAmplitude';
  static const String getPPGRedAmplitude = 'getPPGRedAmplitude';
  static const String getChannelNames = 'getChannelNames';
  static const String getChannelIndexByName = 'getChannelIndexByName';
  static const String getChannelNameByIndex = 'getChannelNameByIndex';
  static const String getChannelsCount = 'getChannelsCount';
  static const String getFirmwareVersion = 'getFirmwareVersion';
}

/// Method names shared across all classifier MethodChannels
/// (NFB, physiological, emotions, productivity, cardio).
abstract final class ClassifierMethods {
  static const String create = 'create';
  static const String createCalibrated = 'createCalibrated';
  static const String dispose = 'dispose';
  static const String startBaselineCalibration = 'startBaselineCalibration';
  static const String stopBaselineCalibration = 'stopBaselineCalibration';
  static const String importBaselines = 'importBaselines';
  static const String resetAccumulatedFatigue = 'resetAccumulatedFatigue';
}

/// Method names for the NFBCalibrator MethodChannel.
abstract final class NFBCalibratorMethods {
  static const String startCalibration = 'startCalibration';
  static const String stopCalibration = 'stopCalibration';
  static const String importCalibration = 'importCalibration';
  static const String getCalibration = 'getCalibration';
  static const String isCalibrated = 'isCalibrated';
}

// ──────────────────────────────────────────────────────────────────────────────
// Argument keys
// ──────────────────────────────────────────────────────────────────────────────

/// Argument keys used in MethodChannel call Maps.
abstract final class NeiryArgs {
  static const String serial = 'serial';
  static const String logDirectory = 'logDirectory';
  static const String deviceType = 'deviceType';
  static const String searchTime = 'searchTime';
  static const String mode = 'mode';
  static const String level = 'level';
  static const String enabled = 'enabled';
  static const String baselines = 'baselines';
  static const String calibrationData = 'calibrationData';
  static const String calibratorData = 'calibratorData';
  static const String channelName = 'channelName';
  static const String index = 'index';
  static const String bipolarChannels = 'bipolarChannels';
}
