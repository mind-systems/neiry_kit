import 'package:flutter_test/flutter_test.dart';
import 'package:neiry_kit/neiry_kit.dart';
import 'package:neiry_kit/neiry_kit_platform_interface.dart';
import 'package:neiry_kit/neiry_kit_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockNeiryKitPlatform
    with MockPlatformInterfaceMixin
    implements NeiryKitPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final NeiryKitPlatform initialPlatform = NeiryKitPlatform.instance;

  test('$MethodChannelNeiryKit is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelNeiryKit>());
  });

  test('getPlatformVersion', () async {
    NeiryKit neiryKitPlugin = NeiryKit();
    MockNeiryKitPlatform fakePlatform = MockNeiryKitPlatform();
    NeiryKitPlatform.instance = fakePlatform;

    expect(await neiryKitPlugin.getPlatformVersion(), '42');
  });
}
