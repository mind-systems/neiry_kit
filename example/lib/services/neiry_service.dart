import 'dart:async';

import 'package:neiry_kit/neiry_kit.dart';

/// Singleton-style service that owns the entire device + classifier lifecycle.
///
/// Construct one instance per app session, call [connect] once a serial is
/// known, subscribe to the exposed streams, and call [disconnect] when done.
/// All six classifiers are eagerly created inside [connect] so MEMS and Cardio
/// emit data regardless of which screen is currently visible.
///
/// Long-lived broadcast [StreamController]s are opened in the constructor and
/// kept open until [dispose] — subscribing before [connect] and receiving
/// events after [connect] is intentional behavior.
class NeiryService {
  NeiryService() : _locator = DeviceLocator();

  // ── Locator ────────────────────────────────────────────────────────────────

  final DeviceLocator _locator;

  // ── Device state ───────────────────────────────────────────────────────────

  Device? _device;
  bool _disposed = false;

  /// Re-entry guard owned exclusively by [connect].
  bool _connecting = false;

  IndividualNfbData? _nfbData;
  NfbCalibrator? _calibrator;

  // ── Classifiers ────────────────────────────────────────────────────────────

  NfbClassifier? _nfb;
  PhysioClassifier? _physio;
  EmotionsClassifier? _emotions;
  ProductivityClassifier? _productivity;
  CardioClassifier? _cardio;
  MEMSClassifier? _mems;

  // ── Fan-in subscriptions (cancelled on disconnect) ─────────────────────────

  final List<StreamSubscription<dynamic>> _activeSubscriptions = [];

  // ── Multiplexer controllers ────────────────────────────────────────────────

  final _connectionStateController =
      StreamController<NeiryConnectionState>.broadcast();
  final _modeController = StreamController<NeiryDeviceMode>.broadcast();
  final _eegController = StreamController<EegData>.broadcast();
  final _psdController = StreamController<PsdData>.broadcast();
  final _artifactsController = StreamController<EegArtifactData>.broadcast();
  final _resistanceController = StreamController<ResistanceData>.broadcast();
  final _batteryController = StreamController<int>.broadcast();
  final _physioController =
      StreamController<PhysiologicalStatesValue>.broadcast();
  final _emotionsController = StreamController<EmotionsStates>.broadcast();
  final _cardioController = StreamController<CardioData>.broadcast();
  final _memsController = StreamController<List<MemsSample>>.broadcast();
  final _nfbController = StreamController<NfbUserState>.broadcast();
  final _productivityIndexesController =
      StreamController<ProductivityIndexes>.broadcast();
  final _productivityMetricsController =
      StreamController<ProductivityMetrics>.broadcast();
  final _cardioPpgController = StreamController<PpgData>.broadcast();
  final _physioCalibrationProgressController =
      StreamController<double>.broadcast();
  final _productivityCalibrationProgressController =
      StreamController<double>.broadcast();

  // ── Guards ─────────────────────────────────────────────────────────────────

  void _checkNotDisposed() {
    if (_disposed) throw StateError('NeiryService has been disposed');
  }

  // ── State getters ──────────────────────────────────────────────────────────

  /// Whether the device is currently connected.
  bool get isConnected => _device?.isConnected ?? false;

  /// Whether EEG streaming is currently active.
  bool get isStarted => _device?.isStarted ?? false;

  // ── Scan ───────────────────────────────────────────────────────────────────

  /// Scans for Neiry devices and emits a single list once the scan completes.
  Stream<List<DeviceInfo>> scan({
    NeiryDeviceType type = NeiryDeviceType.any,
    int searchTime = 5,
  }) {
    _checkNotDisposed();
    return _locator.requestDevices(type: type, searchTime: searchTime);
  }

  // ── Connect ────────────────────────────────────────────────────────────────

  /// Creates a device handle for [serial], connects, and eagerly constructs all
  /// six classifiers.
  ///
  /// Pass [nfbData] to initialise classifiers with individual NFB calibration.
  /// Throws [StateError] when called while already connected or while a
  /// previous connect call is still in flight.
  Future<void> connect(
    String serial, {
    bool bipolarChannels = false,
    IndividualNfbData? nfbData,
  }) async {
    _checkNotDisposed();
    if (_connecting) throw StateError('Connect already in flight');
    if (isConnected) throw StateError('Already connected — call disconnect() first');

    _connecting = true;
    try {
      _nfbData = nfbData;

      _device = await _locator.createDevice(serial);

      try {
        await _device!.connect(bipolarChannels: bipolarChannels);
      } catch (e) {
        try {
          await _device!.dispose();
        } catch (_) {}
        _device = null;
        _nfbData = null;
        rethrow;
      }

      // ── Construct all classifiers eagerly ──────────────────────────────────

      _nfb = NfbClassifier(_device!, calibration: _nfbData);
      _physio = PhysioClassifier(_device!);
      _emotions = EmotionsClassifier(_device!);
      _productivity = _nfbData != null
          ? _safeProductivityWithCalibration(_device!, _nfbData!)
          : ProductivityClassifier(_device!);
      _cardio = _nfbData != null
          ? CardioClassifier.withCalibration(_device!, _nfbData!)
          : CardioClassifier(_device!);
      _mems = _nfbData != null
          ? MEMSClassifier.withCalibration(_device!, _nfbData!)
          : MEMSClassifier(_device!);

      // Set calibrator sentinel before wiring fan-in subscriptions.
      _calibrator = NfbCalibrator.handle;

      // ── Wire fan-in subscriptions ──────────────────────────────────────────

      _activeSubscriptions.addAll([
        _device!.connectionStateStream.listen(
          _connectionStateController.add,
          onError: _connectionStateController.addError,
        ),
        _device!.modeChangedStream.listen(
          _modeController.add,
          onError: _modeController.addError,
        ),
        _device!.eegStream.listen(
          _eegController.add,
          onError: _eegController.addError,
        ),
        _device!.psdStream.listen(
          _psdController.add,
          onError: _psdController.addError,
        ),
        _device!.artifactsStream.listen(
          _artifactsController.add,
          onError: _artifactsController.addError,
        ),
        _device!.resistanceStream.listen(
          _resistanceController.add,
          onError: _resistanceController.addError,
        ),
        _device!.batteryStream.listen(
          _batteryController.add,
          onError: _batteryController.addError,
        ),
        _physio!.stateStream.listen(
          _physioController.add,
          onError: _physioController.addError,
        ),
        _emotions!.stateStream.listen(
          _emotionsController.add,
          onError: _emotionsController.addError,
        ),
        _cardio!.stateStream.listen(
          _cardioController.add,
          onError: _cardioController.addError,
        ),
        _cardio!.ppgStream.listen(
          _cardioPpgController.add,
          onError: _cardioPpgController.addError,
        ),
        _mems!.memsStream.listen(
          _memsController.add,
          onError: _memsController.addError,
        ),
        _nfb!.stateStream.listen(
          _nfbController.add,
          onError: _nfbController.addError,
        ),
        _productivity!.indexesStream.listen(
          _productivityIndexesController.add,
          onError: _productivityIndexesController.addError,
        ),
        _productivity!.metricsStream.listen(
          _productivityMetricsController.add,
          onError: _productivityMetricsController.addError,
        ),
        _physio!.calibrationProgress.listen(
          _physioCalibrationProgressController.add,
          onError: _physioCalibrationProgressController.addError,
        ),
        _productivity!.calibrationProgress.listen(
          _productivityCalibrationProgressController.add,
          onError: _productivityCalibrationProgressController.addError,
        ),
      ]);
    } finally {
      _connecting = false;
    }
  }

  // ── Disconnect ─────────────────────────────────────────────────────────────

  /// Stops streaming, disposes all classifiers, and disconnects the device.
  ///
  /// No-op when no device is connected. Multiplexer controllers stay open so
  /// the next [connect] call can re-feed them.
  Future<void> disconnect() async {
    if (_device == null) return;

    // 1. Cancel fan-in subscriptions.
    for (final s in _activeSubscriptions) {
      try {
        await s.cancel();
      } catch (_) {}
    }
    _activeSubscriptions.clear();

    // 2. Dispose classifiers concurrently.
    await Future.wait<void>([
      if (_nfb != null) _nfb!.dispose().catchError((_) {}),
      if (_physio != null) _physio!.dispose().catchError((_) {}),
      if (_emotions != null) _emotions!.dispose().catchError((_) {}),
      if (_productivity != null) _productivity!.dispose().catchError((_) {}),
      if (_cardio != null) _cardio!.dispose().catchError((_) {}),
      if (_mems != null) _mems!.dispose().catchError((_) {}),
    ]);
    _nfb = null;
    _physio = null;
    _emotions = null;
    _productivity = null;
    _cardio = null;
    _mems = null;

    // 3. Tear down the device.
    if (_device!.isStarted) {
      try {
        await _device!.stop();
      } catch (_) {}
    }
    try {
      await _device!.disconnect();
    } catch (_) {}
    try {
      await _device!.dispose();
    } catch (_) {}

    // 4. Reset device-scoped fields.
    _device = null;
    _nfbData = null;
    _calibrator = null;
  }

  // ── Start / Stop ───────────────────────────────────────────────────────────

  /// Starts EEG streaming on the connected device.
  ///
  /// Throws [StateError] when not connected.
  Future<void> start() async {
    _checkNotDisposed();
    if (_device == null) throw StateError('Not connected');
    await _device!.start();
  }

  /// Stops EEG streaming.
  ///
  /// No-op when no device is connected. Errors propagate to the caller.
  Future<void> stop() async {
    _checkNotDisposed();
    if (_device == null) return;
    await _device!.stop();
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  /// Releases all resources.
  ///
  /// Idempotent — subsequent calls return immediately.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disconnect();
    await _locator.dispose();
    await _connectionStateController.close();
    await _modeController.close();
    await _eegController.close();
    await _psdController.close();
    await _resistanceController.close();
    await _batteryController.close();
    await _artifactsController.close();
    await _physioController.close();
    await _emotionsController.close();
    await _cardioController.close();
    await _memsController.close();
    await _nfbController.close();
    await _productivityIndexesController.close();
    await _productivityMetricsController.close();
    await _cardioPpgController.close();
    await _physioCalibrationProgressController.close();
    await _productivityCalibrationProgressController.close();
  }

  // ── Data streams ───────────────────────────────────────────────────────────

  /// Emits connection state changes.
  Stream<NeiryConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  /// Emits device mode changes.
  Stream<NeiryDeviceMode> get modeStream => _modeController.stream;

  /// Emits raw EEG sample batches.
  Stream<EegData> get eegStream => _eegController.stream;

  /// Emits power spectral density frames.
  Stream<PsdData> get psdStream => _psdController.stream;

  /// Emits EEG artifact data events.
  Stream<EegArtifactData> get artifactsStream => _artifactsController.stream;

  /// Emits electrode resistance readings.
  Stream<ResistanceData> get resistanceStream => _resistanceController.stream;

  /// Emits battery charge level (0–100).
  Stream<int> get batteryStream => _batteryController.stream;

  /// Emits physiological state values from the [PhysioClassifier].
  Stream<PhysiologicalStatesValue> get physioStream =>
      _physioController.stream;

  /// Emits emotions classifier output values.
  Stream<EmotionsStates> get emotionsStream => _emotionsController.stream;

  /// Emits Cardio classifier output values.
  Stream<CardioData> get cardioStream => _cardioController.stream;

  /// Emits MEMS sample batches (unthrottled — throttle in the consumer).
  Stream<List<MemsSample>> get memsStream => _memsController.stream;

  /// Emits NFB brain-wave band power values.
  Stream<NfbUserState> get nfbStream => _nfbController.stream;

  /// Emits [ProductivityIndexes] from the productivity classifier.
  Stream<ProductivityIndexes> get productivityIndexesStream =>
      _productivityIndexesController.stream;

  /// Emits [ProductivityMetrics] from the productivity classifier.
  Stream<ProductivityMetrics> get productivityMetricsStream =>
      _productivityMetricsController.stream;

  /// Emits PPG sample batches from the [CardioClassifier].
  Stream<PpgData> get cardioPpgStream => _cardioPpgController.stream;

  /// Emits Physio baseline-calibration progress (0.0–1.0).
  Stream<double> get physioCalibrationProgressStream =>
      _physioCalibrationProgressController.stream;

  /// Emits Productivity baseline-calibration progress (0.0–1.0).
  Stream<double> get productivityCalibrationProgressStream =>
      _productivityCalibrationProgressController.stream;

  // ── Classifier accessors ───────────────────────────────────────────────────

  /// The active [PhysioClassifier], or `null` when not connected.
  PhysioClassifier? get physioClassifier => _physio;

  /// The active [ProductivityClassifier], or `null` when not connected.
  ProductivityClassifier? get productivityClassifier => _productivity;

  /// The calibrator sentinel when connected with calibration data, or `null`.
  NfbCalibrator? get calibrator => _calibrator;

  // ── Private helpers ────────────────────────────────────────────────────────

  ProductivityClassifier _safeProductivityWithCalibration(
    Device device,
    IndividualNfbData data,
  ) {
    try {
      return ProductivityClassifier.withCalibration(device, data);
    } on UnsupportedError {
      return ProductivityClassifier(device);
    }
  }
}
