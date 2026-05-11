# Обработка ошибок

## Типы исключений

Плагин выбрасывает три typed-исключения, которые можно ловить точечно, и `StateError` для нарушений жизненного цикла.

### BluetoothDisabledException

Bluetooth выключен или приложению отказано в разрешении.

Возникает при вызове `requestDevices`, если BLE-адаптер недоступен. На Android это может означать как физически выключенный Bluetooth, так и отклонённые runtime-разрешения.

```dart
try {
  final devices = await locator.requestDevices().first;
} on BluetoothDisabledException {
  // показать диалог: "Включите Bluetooth для поиска устройств"
}
```

### DeviceNotConnectedException

Метод вызван до установки соединения.

Возникает при вызове `start()`, `stop()`, `getInfo()` и других методов `Device` на устройстве, которое ещё не в состоянии `ConnectionState.connected`.

```dart
device.connectionStateStream.listen((state) async {
  if (state == ConnectionState.connected) {
    try {
      await device.start();
    } on DeviceNotConnectedException {
      // не должно происходить, но на всякий случай
    }
  }
});
```

### CalibrationRequiredException

Классификатор требует индивидуальную NFB-калибровку, которая ещё не проведена.

Возникает при создании классификатора, если переданные данные `IndividualNfbData` невалидны (`isValid == false`). Проверяй `data.isValid` перед передачей в конструктор.

```dart
if (calibrationData?.isValid == true) {
  final nfb = NfbClassifier(device, calibration: calibrationData);
} else {
  // запустить калибровку или использовать классификатор без неё
  final nfb = NfbClassifier(device);
}
```

### StateError

Нарушение жизненного цикла объекта.

Выбрасывается непосредственно Dart API при попытке:
- создать классификатор до `device.start()`
- обратиться к методам `DeviceLocator` или `Device` после `dispose()`
- обратиться к стримам классификатора после его `dispose()`

Это всегда ошибка в коде, не runtime-условие. `StateError` не нужно ловить — его нужно устранить.

### NeiryException (базовый)

Любая другая ошибка нативного SDK, которая не попала в typed-подклассы.

```dart
try {
  await device.connect();
} on BluetoothDisabledException {
  // BLE недоступен
} on NeiryException catch (e) {
  // прочие ошибки SDK — e.code и e.message содержат детали
  debugPrint('SDK error ${e.code}: ${e.message}');
}
```

## Потеря соединения

SDK не автоматически переподключается. При потере связи `connectionStateStream` эмитит `ConnectionState.disconnected`. Стримы EEG и классификаторов перестают поступать данные, но не закрываются с ошибкой.

Для переподключения нужно вручную вызвать `device.connect()` снова:

```dart
device.connectionStateStream.listen((state) async {
  if (state == ConnectionState.disconnected && wasConnected) {
    await Future.delayed(const Duration(seconds: 2));
    await device.connect(bipolarChannels: true);
  }
});
```

## Калибровка завершилась неудачей

`CalibrationCompleted` с `isValid == false` — не исключение, а штатный результат. Поле `failReason` объясняет причину:

| Причина | Что делать |
|---|---|
| `tooManyArtifacts` | Проверить импеданс электродов, попросить не двигаться |
| `peakFrequencyAtBorder` | Повторить калибровку — редкий физиологический вариант |

```dart
NfbCalibrator.calibrateIndividual().listen((event) {
  if (event is CalibrationCompleted) {
    if (!event.data.isValid) {
      switch (event.data.failReason) {
        case NfbCalibrationFailReason.tooManyArtifacts:
          // показать подсказку про электроды и неподвижность
        case NfbCalibrationFailReason.peakFrequencyAtBorder:
          // предложить повторить
        case null:
          break;
      }
    }
  }
});
```
