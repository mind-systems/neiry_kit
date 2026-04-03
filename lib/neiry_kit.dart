
import 'neiry_kit_platform_interface.dart';

class NeiryKit {
  Future<String?> getPlatformVersion() {
    return NeiryKitPlatform.instance.getPlatformVersion();
  }
}
