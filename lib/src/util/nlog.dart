import 'dart:developer';

void nlog(
  String message, {
  String name = 'neiry_kit',
  Object? error,
  StackTrace? stackTrace,
}) {
  final n = DateTime.now();
  final ts = '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}:'
      '${n.second.toString().padLeft(2, '0')}.${n.millisecond.toString().padLeft(3, '0')}';
  log('[$ts] $message', name: name, error: error, stackTrace: stackTrace);
}
