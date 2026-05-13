# Сценарий сессии

Полный маршрут от запуска приложения до работающего классификатора. Каждый шаг зависит от предыдущего — порядок строгий.

## 1. Запросить разрешения

На Android нужно запросить BLE-разрешения до любого вызова SDK. Без них `requestDevices` вернёт пустой список или бросит `BluetoothDisabledException`. Подробнее — в [настройке проекта](setup.md).

## 2. Создать DeviceLocator и найти устройство

`DeviceLocator` — синглтон. Первый вызов создаёт нативный хэндл, последующие возвращают тот же экземпляр.

```dart
final locator = DeviceLocator();

final devices = await locator
    .requestDevices(type: NeiryDeviceType.any, searchTime: 5)
    .first;

if (devices.isEmpty) {
  // устройство не найдено — показать инструкцию пользователю
  return;
}
```

Стрим `requestDevices` эмитит один раз — когда `searchTime` истёк. Если нужно повторное сканирование, вызови `requestDevices` снова — предыдущий скан отменится автоматически.

## 3. Подключиться

```dart
final device = await locator.createDevice(devices.first.serial);

device.connectionStateStream.listen((state) {
  // отслеживать ConnectionState.connected / .disconnected
});

await device.connect(bipolarChannels: true);
```

`connect()` неблокирующий — он регистрирует запрос и возвращает управление. Само соединение устанавливается в фоне; фактический момент готовности — `ConnectionState.connected` в `connectionStateStream`.

Флаг `bipolarChannels: true` включает дифференциальный режим: каждый канал показывает разницу между двумя электродами. Это подавляет синфазные помехи и предпочтительно для большинства сценариев.

## 4. Проверить контакт электродов

До запуска стриминга стоит убедиться, что электроды прилегают к коже. Устройство должно быть в режиме `Resistance` или `SignalAndResist`.

```dart
device.resistanceStream.listen((r) {
  for (int i = 0; i < r.channelCount; i++) {
    final ok = r.values[i] < 500; // < 500 кОм — хороший контакт
    print('${r.channelNames[i]}: ${r.values[i].toStringAsFixed(0)} кОм — ${ok ? "ok" : "плохой контакт"}');
  }
});
```

Если хотя бы один электрод показывает > 1000 кОм, EEG-данные будут ненадёжными, а NFB-калибровка, скорее всего, завершится с `tooManyArtifacts`.

## 5. Запустить стриминг

Подписаться на стримы нужно **до** `start()` — иначе первые пакеты будут пропущены.

```dart
device.eegStream.listen((eeg) {
  // eeg.rawValues — сырой сигнал по каналам
  // eeg.processedValues — после фильтрации артефактов
});

await device.start();
```

После `start()` устройство переходит в режим `Signal` и начинает слать данные.

## 6. Создать классификаторы

Классификаторы создаются сразу после `connect()` — до `start()`. SDK допускает только один экземпляр каждого классификатора на устройство, и для него нет явного Destroy. Поэтому создавай классификаторы один раз при подключении и держи их до отключения.

```dart
// Создаётся после connect(), до start()
final nfb = NfbClassifier(device, calibration: savedCalibration);
final physio = PhysioClassifier(device);
final emotions = EmotionsClassifier(device);
// ... остальные классификаторы

// Подписывайся на стримы тоже до start()
nfb.stateStream.listen((state) {
  print('alpha: ${state.alpha?.toStringAsFixed(2)}');
});
```

Если передать сохранённые данные `IndividualNfbData` — результаты NFB, продуктивности и кардио будут точнее.

Поля `delta` и `smr` возвращают `null` без калибровки — они зависят от индивидуального альфа-профиля.

## 7. NFB-калибровка (при необходимости)

Калибровка нужна один раз — результат сохраняется между сессиями. Если у пользователя уже есть сохранённые данные, пропусти этот шаг.

```dart
final calibration = await NfbCalibrator.calibrateIndividual().last
    .then((event) => switch (event) {
          CalibrationCompleted(:final data) when data.isValid => data,
          _ => null,
        });

if (calibration != null) {
  // сохранить calibration.toMap() в хранилище
  // при следующем запуске передать в connect() или конструктор классификатора
}
```

Полная калибровка занимает ~80 секунд (4 стадии по 20 секунд). Пользователь должен сидеть неподвижно, следовать инструкции по открытию/закрытию глаз.

## 8. Завершить сессию

```dart
await device.stop();
await device.disconnect();
device.dispose();
await locator.dispose();
```

После `dispose()` объекты нельзя переиспользовать — нативный C-хэндл освобождён. Для новой сессии создавай `DeviceLocator()` заново.

## Типичные ошибки в порядке вызовов

| Что не так | Что произойдёт |
|---|---|
| `createDevice` до `connect` | Устройство создано, но `start()` бросит `DeviceNotConnectedException` |
| Классификатор до `connect()` | `StateError` — явный guard в Dart API |
| Создание классификатора дважды | `Fatal signal 64` / `clCCardio module already exists` — SDK не допускает повторного создания на одном устройстве |
| `requestDevices` без разрешений Android | Пустой список или `BluetoothDisabledException` |
| `start()` дважды | Второй вызов игнорируется — SDK проверяет состояние |
| `stop()` дважды | SIGABRT — второй `clCDevice_Stop` на уже остановленной сессии приводит к крэшу нативной библиотеки |
