import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'neiry_kit_platform_interface.dart';

/// An implementation of [NeiryKitPlatform] that uses method channels.
class MethodChannelNeiryKit extends NeiryKitPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('neiry_kit');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
