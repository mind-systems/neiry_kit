import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neiry_kit/neiry_kit.dart';

class DeviceLocatorNotifier extends Notifier<DeviceLocator> {
  @override
  DeviceLocator build() {
    final locator = DeviceLocator();
    ref.onDispose(() => locator.dispose());
    return locator;
  }
}

final deviceLocatorProvider =
    NotifierProvider<DeviceLocatorNotifier, DeviceLocator>(
  DeviceLocatorNotifier.new,
);
