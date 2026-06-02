import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/nlog.dart';

/// Plays short WAV cues bundled in `assets/sounds/`.
///
/// A single [AudioPlayer] is shared across all cue methods. Because the cues
/// are shorter than 1 s, a later [play] interrupting an earlier one is
/// acceptable. Errors are caught and logged so callers can fire-and-forget
/// without risking unhandled async errors.
class SoundService {
  final AudioPlayer _player = AudioPlayer();

  Future<void> playStageStart() => _player
      .play(AssetSource('sounds/stage.wav'))
      .catchError((Object e, StackTrace st) {
        nlog('playStageStart failed: $e', name: 'SoundService', error: e, stackTrace: st);
      });

  Future<void> playDone() => _player
      .play(AssetSource('sounds/done.wav'))
      .catchError((Object e, StackTrace st) {
        nlog('playDone failed: $e', name: 'SoundService', error: e, stackTrace: st);
      });

  Future<void> playError() => _player
      .play(AssetSource('sounds/error.wav'))
      .catchError((Object e, StackTrace st) {
        nlog('playError failed: $e', name: 'SoundService', error: e, stackTrace: st);
      });

  Future<void> playModeChange() => _player
      .play(AssetSource('sounds/mode.wav'))
      .catchError((Object e, StackTrace st) {
        nlog('playModeChange failed: $e', name: 'SoundService', error: e, stackTrace: st);
      });

  Future<void> dispose() => _player.dispose();
}

final soundServiceProvider = Provider<SoundService>((ref) {
  final service = SoundService();
  ref.onDispose(service.dispose);
  return service;
});
