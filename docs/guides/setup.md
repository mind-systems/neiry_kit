# Настройка проекта

## Зависимость

Добавь `neiry_kit` в `pubspec.yaml` приложения:

```yaml
dependencies:
  neiry_kit:
    path: ../neiry_kit
```

После этого `flutter pub get` загрузит плагин и подтянет нативные библиотеки для iOS и Android.

## Android

Плагин объявляет BLE-разрешения в своём `AndroidManifest.xml` — они автоматически мёрджатся в манифест приложения при сборке. Никаких ручных правок в `AndroidManifest.xml` приложения не нужно.

Разрешения всё равно требуют **runtime-запроса**. Добавь `permission_handler` в зависимости и запрашивай разрешения перед началом сканирования:

```yaml
dependencies:
  permission_handler: ^11.4.0
```

```dart
import 'package:permission_handler/permission_handler.dart';

Future<bool> requestBlePermissions() async {
  final permissions = [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ];

  final statuses = await permissions.request();

  if (statuses.values.any((s) => s == PermissionStatus.permanentlyDenied)) {
    await openAppSettings();
    return false;
  }

  return statuses.values.every((s) => s == PermissionStatus.granted);
}
```

`locationWhenInUse` нужен только на Android 6–11 — на Android 12+ системный BLE-сканер его уже не требует, но `permission_handler` безвредно проверит его и вернёт `granted` на новых версиях.

Минимальная версия Android: **API 26** (Android 8.0).

## iOS

Добавь ключ в `ios/Runner/Info.plist` приложения:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Приложение использует Bluetooth для подключения к нейрогарнитурам Neiry.</string>
```

Без этого ключа iOS завершит приложение с ошибкой при первом обращении к BLE. Разрешение запрашивается системой автоматически при первом вызове `DeviceLocator().requestDevices()`.

Минимальная версия iOS: **13.0**.

## Логирование SDK

По умолчанию нативный SDK не пишет логи. Чтобы включить запись в файл, передай путь к директории при создании `DeviceLocator`:

```dart
final docsDir = await getApplicationDocumentsDirectory();
final locator = DeviceLocator(logDirectory: docsDir.path);
```

Передавай `logDirectory` только в debug-сборках — логи SDK подробные и быстро занимают место.
