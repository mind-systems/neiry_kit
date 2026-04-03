import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'neiry_kit_method_channel.dart';

abstract class NeiryKitPlatform extends PlatformInterface {
  /// Constructs a NeiryKitPlatform.
  NeiryKitPlatform() : super(token: _token);

  static final Object _token = Object();

  static NeiryKitPlatform _instance = MethodChannelNeiryKit();

  /// The default instance of [NeiryKitPlatform] to use.
  ///
  /// Defaults to [MethodChannelNeiryKit].
  static NeiryKitPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [NeiryKitPlatform] when
  /// they register themselves.
  static set instance(NeiryKitPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
