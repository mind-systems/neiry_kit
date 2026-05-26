import 'dart:async';

/// Wraps [source] and emits the measured event rate (events/second) once per
/// second using a rolling [window].
///
/// The returned stream is single-subscription; cancel it to release the inner
/// subscription and timer. Riverpod [StreamProvider] handles this automatically.
Stream<double> rateOf(
  Stream<dynamic> source, {
  Duration window = const Duration(seconds: 3),
}) {
  final timestamps = <DateTime>[];
  StreamSubscription<dynamic>? sub;
  Timer? ticker;
  late StreamController<double> ctrl;

  ctrl = StreamController<double>(
    onListen: () {
      sub = source.listen((_) => timestamps.add(DateTime.now()));
      ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        final now = DateTime.now();
        final cutoff = now.subtract(window);
        timestamps.removeWhere((t) => t.isBefore(cutoff));
        if (!ctrl.isClosed) ctrl.add(timestamps.length / window.inSeconds);
      });
    },
    onCancel: () {
      sub?.cancel();
      ticker?.cancel();
      timestamps.clear();
    },
  );

  return ctrl.stream;
}
